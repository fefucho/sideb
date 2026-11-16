//! Automix (PLAN-024), coordinador nativo de Windows.
//!
//! Mientras suena una canción, el core renderiza la transición hacia la siguiente
//! (`prepare_automix`: un WAV con la canción actual sin tocar, la mezcla y TODA la
//! siguiente sin tocar). Este módulo decide cuándo pedirla, cambia el reproductor
//! de la canción al archivo una sola vez, traduce los tiempos del archivo a los de
//! la canción que se muestra y avanza la cola nativa en el traspaso.
//!
//! Reglas que mantiene (la cola nativa sigue siendo autoritativa):
//! * Toda decisión se toma con el cerrojo de reproducción y se valida contra
//!   `generation`, `queue_epoch`, la cuenta (`auth_generation`) y las ocurrencias
//!   (`entry_id`) actual y siguiente. Si algo cambia, se cancela o se descarta.
//! * El archivo lleva las ganancias de ambas canciones ya aplicadas: mientras suena
//!   `runtime.track_gain` es `None` (sólo queda la parte del volumen exponencial).
//! * El cambio al archivo y el traspaso nunca pasan por `play_song`: el EOF del
//!   reemplazo no avanza la cola (`ends_track`), y el traspaso sube `generation`
//!   como un arranque normal para que los seeks, el historial y los controles
//!   multimedia vean una canción nueva.
//! * Lo que no se pueda hacer se degrada al comportamiento normal; sólo el botón
//!   «Beta · Automix» muestra el motivo.
//!
//! Ninguna URL, cookie ni cabecera pasa por este módulo ni por sus registros.
use crate::queue::QueueEntryDto;
use crate::seek_state::SeekOwner;
use crate::{AppState, PlaybackManager, PlaybackStateDto, PlaybackTrackDto};
use serde::{Deserialize, Serialize};
use std::sync::atomic::Ordering;
use std::time::{Duration, Instant};
use tauri::{Emitter, Manager};

/// Se rinde si la canción ya pasó `a_cut + overlap_start − LATE_MARGIN`.
const LATE_MARGIN: f64 = 0.5;
/// Un seek a la canción que suena desde el archivo exige estar al menos así después
/// de `b_entry`; antes de eso la canción no está en el archivo.
const SEEK_MARGIN: f64 = 1.0;
/// Holgura que se resta al final de la parte «A sin tocar» al calcular el destino.
const OVERLAP_GUARD: f64 = 0.02;
/// Cuánto esperamos a que el reproductor confirme el archivo antes de abandonarlo.
const SWITCH_WATCHDOG: Duration = Duration::from_secs(4);
/// Cuánto se esperan posiciones cercanas al destino tras el seek del empalme.
const SEEK_SETTLE: Duration = Duration::from_secs(2);
/// Margen alrededor del destino para aceptar la primera posición posterior al seek.
const SEEK_NEAR: f64 = 0.75;
/// Estimación de lo que tarda el reanudado tras el seek (se suma al reloj de pared).
const RESUME_LEAD: f64 = 0.03;

// MARK: DTO

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum AutomixPhase {
    /// El ajuste está apagado.
    Off,
    /// Activo, pero sin nada que preparar (sin siguiente, mismo álbum, repetir…).
    Idle,
    Preparing,
    Ready,
    Unavailable,
    /// Suena el archivo de la transición (hasta el final de la mezcla).
    Mixing,
}

/// Estado que ve la interfaz. Sin rutas ni URLs.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct AutomixStatusDto {
    pub enabled: bool,
    pub phase: AutomixPhase,
    pub kind: Option<String>,
    pub bpm_from: Option<f64>,
    pub bpm_to: Option<f64>,
    pub bars: Option<u32>,
    pub stems_model: Option<bool>,
    /// Código estable (la interfaz lo traduce): `no-next`, `album`, `same-song`,
    /// `jam`, `repeat` (en reposo); `unsupported-format`, `too-long`, `late`,
    /// `failed`, `load`, `resolve` (no disponible).
    pub reason: Option<String>,
    /// Segundo de la canción ACTUAL (los de su barra de progreso) donde empieza la mezcla:
    /// `a_cut + overlap_start`. Sólo con una transición lista o sonando antes del traspaso.
    pub marker_seconds: Option<f64>,
}

impl AutomixStatusDto {
    fn plain(enabled: bool, phase: AutomixPhase, reason: Option<&str>) -> Self {
        Self {
            enabled,
            phase,
            kind: None,
            bpm_from: None,
            bpm_to: None,
            bars: None,
            stems_model: None,
            reason: reason.map(str::to_owned),
            marker_seconds: None,
        }
    }
    fn with(mut self, rec: &Transition) -> Self {
        self.kind = Some(rec.kind.clone());
        self.bpm_from = (rec.bpm_from > 0.0).then_some(rec.bpm_from);
        self.bpm_to = (rec.bpm_to > 0.0).then_some(rec.bpm_to);
        self.bars = Some(rec.bars);
        self.stems_model = Some(rec.stems_model);
        self
    }
}

// MARK: Tipos

/// Los números de `AutomixTransitionRecord` que usa el reproductor (sin `request_id`).
#[derive(Clone, Debug, PartialEq)]
pub(crate) struct Transition {
    pub kind: String,
    pub file_path: String,
    pub file_duration: f64,
    pub a_cut: f64,
    pub overlap_start: f64,
    pub overlap_end: f64,
    pub b_offset: f64,
    pub b_entry: f64,
    pub handover: f64,
    pub bpm_from: f64,
    pub bpm_to: f64,
    pub bars: u32,
    pub stems_model: bool,
    pub detail: String,
}

impl From<&sideb_core::automix_job::AutomixTransitionRecord> for Transition {
    fn from(r: &sideb_core::automix_job::AutomixTransitionRecord) -> Self {
        Self {
            kind: r.kind.clone(),
            file_path: r.file_path.clone(),
            file_duration: r.file_duration_seconds,
            a_cut: r.a_cut_seconds,
            overlap_start: r.overlap_start_seconds,
            overlap_end: r.overlap_end_seconds,
            b_offset: r.b_offset_seconds,
            b_entry: r.b_entry_seconds,
            handover: r.handover_seconds,
            bpm_from: r.bpm_from,
            bpm_to: r.bpm_to,
            bars: r.bars,
            stems_model: r.stems_model,
            detail: r.detail.clone(),
        }
    }
}

impl Transition {
    /// Un archivo con números imposibles no se reproduce.
    fn sane(&self) -> bool {
        let finite = [
            self.file_duration, self.a_cut, self.overlap_start, self.overlap_end,
            self.b_offset, self.b_entry, self.handover,
        ]
        .iter()
        .all(|value| value.is_finite());
        finite
            && !self.file_path.is_empty()
            && self.file_duration > 0.0
            && self.a_cut >= 0.0
            && self.overlap_start > 0.0
            && self.overlap_end >= self.overlap_start
            && self.handover >= 0.0
            && self.handover <= self.file_duration
    }
    /// Último segundo de la canción actual en el que todavía se puede empalmar.
    fn splice_deadline(&self) -> f64 {
        self.a_cut + self.overlap_start - LATE_MARGIN
    }
}

/// Qué par de ocurrencias describe una preparación, y de qué reproducción y cuenta.
#[derive(Clone, Debug, PartialEq, Eq)]
pub(crate) struct PlanKey {
    pub auth: u64,
    pub epoch: u64,
    pub generation: u64,
    pub from_entry: String,
    pub to_entry: String,
    pub from_video: String,
    pub to_video: String,
    pub from_upload: bool,
    pub to_upload: bool,
}

/// Por qué no hay nada que preparar.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub(crate) enum Skip {
    Disabled,
    Jam,
    Repeat,
    NoCurrent,
    NoNext,
    SameAlbum,
    SameSong,
}

impl Skip {
    fn code(self) -> Option<&'static str> {
        match self {
            Skip::Disabled | Skip::NoCurrent => None,
            Skip::Jam => Some("jam"),
            Skip::Repeat => Some("repeat"),
            Skip::NoNext => Some("no-next"),
            Skip::SameAlbum => Some("album"),
            Skip::SameSong => Some("same-song"),
        }
    }
}

struct Job {
    request_id: String,
    key: PlanKey,
}

struct Ready {
    key: PlanKey,
    rec: Transition,
    from_gain: Option<f64>,
    to_gain: Option<f64>,
    /// La canción ya pasó el último momento para empalmar (se buscó hacia adelante).
    missed: bool,
}

/// Un par de ocurrencias que ya falló: no se reintenta mientras sigan siendo actual y siguiente.
struct Failure {
    from_entry: String,
    to_entry: String,
    reason: &'static str,
}

impl Failure {
    fn of(key: &PlanKey, reason: &'static str) -> Self {
        Self { from_entry: key.from_entry.clone(), to_entry: key.to_entry.clone(), reason }
    }
}

/// Fase del cambio de la canción al archivo, hasta que el reproductor ya toca el destino.
#[derive(Clone, Copy, Debug, PartialEq)]
enum SwitchPhase {
    /// `loadfile` enviado: el reproductor todavía no confirmó el archivo.
    Loading,
    /// Seek y reanudado enviados: se esperan posiciones cercanas al destino.
    Settling { target: f64, since: Instant },
}

#[derive(Clone, Copy, Debug)]
struct Switching {
    token: u64,
    started: Instant,
    /// Segundo de la canción que se mostraba al decidir el empalme.
    song_at_start: f64,
    was_playing: bool,
    phase: SwitchPhase,
}

/// El reproductor tiene cargado un archivo de transición.
pub(crate) struct OnFile {
    rec: Transition,
    key: PlanKey,
    from_gain: Option<f64>,
    to_gain: Option<f64>,
    /// Dueño actual (sube en el traspaso). Si no coincide con `pb.generation`, otra
    /// operación reemplazó el audio y este estado ya no describe nada.
    generation: u64,
    handed_over: bool,
    switching: Option<Switching>,
    /// Se está volviendo al arranque normal de la ocurrencia: nada más se decide aquí.
    leaving: bool,
    /// Último segundo del archivo reportado (el del reproductor, sin traducir).
    last_raw: f64,
}

impl OnFile {
    fn song_position(&self, raw: f64) -> f64 {
        let position = if self.handed_over { raw - self.rec.b_offset } else { self.rec.a_cut + raw };
        position.max(0.0)
    }
    fn mixing(&self) -> bool {
        self.last_raw < self.rec.overlap_end
    }
    /// Segundo del archivo al que corresponde un segundo de la canción que suena
    /// desde él, o `None` si esa parte de la canción no está en el archivo.
    fn file_seek_target(&self, song: f64) -> Option<f64> {
        if !song.is_finite() {
            return None;
        }
        if self.handed_over {
            (song >= self.rec.b_entry + SEEK_MARGIN)
                .then(|| (song + self.rec.b_offset).min(self.rec.file_duration))
        } else {
            let end = self.rec.a_cut + self.rec.overlap_start - 0.25;
            (song >= self.rec.a_cut && song <= end).then(|| song - self.rec.a_cut)
        }
    }
}

#[derive(Default)]
pub(crate) struct AutomixRuntime {
    pub enabled: bool,
    next_request: u64,
    next_token: u64,
    job: Option<Job>,
    ready: Option<Ready>,
    failed: Option<Failure>,
    on_file: Option<OnFile>,
    /// Generación cuyo historial ya se resolvió (la resolución de la canción siguiente,
    /// que pide la ganancia, pisa el seguimiento que usa `record_playback`).
    history_done: Option<u64>,
    skip: Option<Skip>,
    cancels: Vec<String>,
    last_status: Option<AutomixStatusDto>,
    /// Hay un Jam en marcha: Automix queda fuera sin tocar la preferencia guardada.
    jam: bool,
}

impl AutomixRuntime {
    fn cancel_job(&mut self) {
        if let Some(job) = self.job.take() {
            self.cancels.push(job.request_id);
        }
    }
    /// Descarta todo lo preparado o en preparación (no el archivo que ya suena).
    pub(crate) fn drop_plan(&mut self) {
        self.cancel_job();
        self.ready = None;
        self.failed = None;
    }
    /// Una carga normal (o una detención) reemplaza el audio: el archivo ya no suena.
    pub(crate) fn reset_for_new_load(&mut self) {
        self.drop_plan();
        self.on_file = None;
    }
    pub(crate) fn take_cancels(&mut self) -> Vec<String> {
        std::mem::take(&mut self.cancels)
    }
    fn next_request_id(&mut self) -> String {
        self.next_request = self.next_request.wrapping_add(1);
        let millis = std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .map_or(0, |elapsed| elapsed.as_millis());
        format!("win-{millis}-{}", self.next_request)
    }
    /// Dónde empieza la mezcla en la barra de la canción que se muestra (PLAN-024, igual que en Mac):
    /// con la transición lista, o con el archivo sonando mientras todavía se muestra la canción vieja.
    fn marker_seconds(&self) -> Option<f64> {
        if !self.enabled || self.jam {
            return None;
        }
        let seconds = match (&self.on_file, &self.ready) {
            (Some(file), _) if !file.handed_over && !file.leaving => file.rec.a_cut + file.rec.overlap_start,
            (_, Some(ready)) if !ready.missed => ready.rec.a_cut + ready.rec.overlap_start,
            _ => return None,
        };
        (seconds.is_finite() && seconds >= 0.0).then_some(seconds)
    }
    fn status(&self) -> AutomixStatusDto {
        let mut status = self.phase_status();
        status.marker_seconds = self.marker_seconds();
        status
    }
    fn phase_status(&self) -> AutomixStatusDto {
        use AutomixPhase::*;
        // Un Jam apaga Automix también en la interfaz; `enabled` sigue siendo la preferencia guardada.
        if self.jam {
            return AutomixStatusDto::plain(self.enabled, Unavailable, Some("jam"));
        }
        if !self.enabled {
            return AutomixStatusDto::plain(false, Off, None);
        }
        if let Some(file) = self.on_file.as_ref().filter(|file| file.mixing() && !file.leaving) {
            return AutomixStatusDto::plain(true, Mixing, None).with(&file.rec);
        }
        if let Some(ready) = &self.ready {
            if ready.missed {
                return AutomixStatusDto::plain(true, Unavailable, Some("late"));
            }
            return AutomixStatusDto::plain(true, Ready, None).with(&ready.rec);
        }
        if self.job.is_some() {
            return AutomixStatusDto::plain(true, Preparing, None);
        }
        if let Some(failure) = &self.failed {
            return AutomixStatusDto::plain(true, Unavailable, Some(failure.reason));
        }
        AutomixStatusDto::plain(true, Idle, self.skip.and_then(Skip::code))
    }
    /// El estado si cambió desde la última vez que se emitió.
    fn take_status_change(&mut self) -> Option<AutomixStatusDto> {
        let status = self.status();
        if self.last_status.as_ref() == Some(&status) {
            return None;
        }
        self.last_status = Some(status.clone());
        Some(status)
    }
    pub(crate) fn snapshot(&mut self) -> AutomixStatusDto {
        let status = self.status();
        self.last_status = Some(status.clone());
        status
    }
}

// MARK: Reproductor

/// Lo que este módulo le pide al reproductor (libmpv en la app; un doble en las pruebas).
pub(crate) trait Engine {
    fn pause(&self) -> Result<(), String>;
    fn play(&self) -> Result<(), String>;
    fn load_file(&self, path: &str, gain_db: Option<f64>) -> Result<(), String>;
    fn seek(&self, seconds: f64) -> Result<(), String>;
    fn set_gain(&self, gain_db: Option<f64>) -> Result<(), String>;
}

impl Engine for player::Player {
    fn pause(&self) -> Result<(), String> {
        player::Player::pause(self).map_err(|error| error.to_string())
    }
    fn play(&self) -> Result<(), String> {
        player::Player::play(self).map_err(|error| error.to_string())
    }
    fn load_file(&self, path: &str, gain_db: Option<f64>) -> Result<(), String> {
        player::Player::load(self, path, &std::collections::HashMap::new(), gain_db)
            .map_err(|error| error.to_string())
    }
    fn seek(&self, seconds: f64) -> Result<(), String> {
        player::Player::seek(self, seconds).map_err(|error| error.to_string())
    }
    fn set_gain(&self, gain_db: Option<f64>) -> Result<(), String> {
        player::Player::set_gain(self, gain_db).map_err(|error| error.to_string())
    }
}

pub(crate) struct Ctx<'a> {
    pub now: Instant,
    pub jam_active: bool,
    pub auth_generation: u64,
    pub engine: Option<&'a dyn Engine>,
}

// MARK: Resultado de un evento

pub(crate) struct PrepareJob {
    pub request_id: String,
    pub key: PlanKey,
    pub from_gain: Option<f64>,
}

pub(crate) struct LeaveJob {
    pub entry_id: String,
    pub generation: u64,
    pub paused: bool,
    pub revision: u64,
}

pub(crate) struct HandoverJob {
    pub generation: u64,
    pub video_id: String,
    pub is_upload: bool,
}

/// Trabajo que debe hacerse fuera del cerrojo de reproducción.
#[derive(Default)]
pub(crate) struct Step {
    /// Segundo de la canción que se muestra; `None`: descartar el evento.
    pub position: Option<f64>,
    pub state: Option<PlaybackStateDto>,
    pub status: Option<AutomixStatusDto>,
    pub cancels: Vec<String>,
    pub prepare: Option<PrepareJob>,
    pub handover: Option<HandoverJob>,
    pub leave: Option<LeaveJob>,
    pub watchdog: Option<u64>,
}

// MARK: Elegibilidad

fn album_of<'a>(entry: &'a QueueEntryDto, track: Option<&'a PlaybackTrackDto>) -> Option<&'a str> {
    entry
        .album_id
        .as_deref()
        .or_else(|| track.filter(|t| t.video_id == entry.video_id).and_then(|t| t.album_id.as_deref()))
        .map(str::trim)
        .filter(|id| !id.is_empty())
}

/// El par (actual, siguiente) que habría que mezclar, o por qué no.
pub(crate) fn plan_for(pb: &PlaybackManager, jam_active: bool) -> Result<PlanKey, Skip> {
    if !pb.runtime.automix.enabled {
        return Err(Skip::Disabled);
    }
    if jam_active {
        return Err(Skip::Jam);
    }
    if pb.is_repeat {
        return Err(Skip::Repeat);
    }
    let index = pb.queue.current_index.ok_or(Skip::NoCurrent)?;
    let current = pb.queue.items.get(index).ok_or(Skip::NoCurrent)?;
    let track = pb.current_track.as_ref().filter(|track| track.video_id == current.video_id).ok_or(Skip::NoCurrent)?;
    let next = pb.queue.items.get(index + 1).ok_or(Skip::NoNext)?;
    if next.video_id == current.video_id {
        return Err(Skip::SameSong);
    }
    if let (Some(a), Some(b)) = (album_of(current, Some(track)), album_of(next, None)) {
        if a == b {
            return Err(Skip::SameAlbum);
        }
    }
    Ok(PlanKey {
        auth: pb.observed_auth_generation,
        epoch: pb.queue_epoch,
        generation: pb.generation,
        from_entry: current.entry_id.clone(),
        to_entry: next.entry_id.clone(),
        from_video: current.video_id.clone(),
        to_video: next.video_id.clone(),
        from_upload: current.is_upload || track.is_upload,
        to_upload: next.is_upload,
    })
}

/// ¿Sigue describiendo `key` el estado actual (sin reservar memoria)?
fn key_matches(key: &PlanKey, pb: &PlaybackManager, auth_generation: u64) -> bool {
    let Some(index) = pb.queue.current_index else { return false };
    let (Some(current), Some(next)) = (pb.queue.items.get(index), pb.queue.items.get(index + 1)) else {
        return false;
    };
    key.auth == pb.observed_auth_generation
        && key.auth == auth_generation
        && key.epoch == pb.queue_epoch
        && key.generation == pb.generation
        && key.from_entry == current.entry_id
        && key.to_entry == next.entry_id
        && key.from_video == current.video_id
        && key.to_video == next.video_id
}

/// Ganancia de la canción actual tal como la aplicaría el reproductor sin automix.
fn song_gain(pb: &PlaybackManager) -> Option<f64> {
    match pb.runtime.automix.on_file.as_ref() {
        Some(file) if file.handed_over => file.to_gain,
        Some(file) => file.from_gain,
        None => pb.runtime.track_gain,
    }
}

// MARK: Eventos del reproductor

/// ¿Esta posición es de la canción vieja o del archivo todavía sin confirmar?
enum Gate {
    Pass,
    Swallow,
}

/// Siguiente ocurrencia de la cola (sin reservar memoria).
fn next_entry_id(pb: &PlaybackManager) -> Option<&str> {
    let index = pb.queue.current_index?;
    pb.queue.items.get(index + 1).map(|entry| entry.entry_id.as_str())
}

/// Evento de posición. Devuelve la posición traducida y lo que hay que hacer fuera del cerrojo.
pub(crate) fn on_position(pb: &mut PlaybackManager, raw: f64, ctx: &Ctx) -> Step {
    let mut step = Step::default();
    drop_dead_file(pb);
    if let Gate::Swallow = gate_switch(pb, raw, ctx, &mut step) {
        step.cancels.append(&mut pb.runtime.automix.cancels);
        step.status = pb.runtime.automix.take_status_change();
        return step;
    }
    let position = match pb.runtime.automix.on_file.as_mut() {
        Some(file) => {
            file.last_raw = raw;
            file.song_position(raw)
        }
        None => raw,
    };
    step.position = Some(position);
    validate_plan(pb, ctx, &mut step);
    maybe_hand_over(pb, raw, &mut step);
    if step.leave.is_none() {
        maybe_splice(pb, position, ctx, &mut step);
    }
    if step.leave.is_none() {
        maybe_prepare(pb, ctx, &mut step);
    }
    step.cancels.append(&mut pb.runtime.automix.cancels);
    step.status = pb.runtime.automix.take_status_change();
    step
}

/// Evento de duración. `None`: no tocar `pb.duration`.
pub(crate) fn on_duration(pb: &mut PlaybackManager, raw: f64, ctx: &Ctx) -> (Option<f64>, Step) {
    let mut step = Step::default();
    drop_dead_file(pb);
    let Some(file) = pb.runtime.automix.on_file.as_ref() else {
        return (Some(raw), step);
    };
    let loading = file.switching.is_some_and(|switch| switch.phase == SwitchPhase::Loading);
    let matches_file = (raw - file.rec.file_duration).abs() <= 1.0;
    let handed_over = file.handed_over;
    let song_duration = raw - file.rec.b_offset;
    if loading {
        // El archivo llega con su propia duración; la de la canción vieja no cuenta.
        if matches_file {
            confirm_switch(pb, ctx, &mut step);
        }
        step.status = pb.runtime.automix.take_status_change();
        return (None, step);
    }
    if handed_over {
        return ((song_duration > 0.0).then_some(song_duration), step);
    }
    (None, step)
}

/// ¿Hay que ignorar un `Playing(_)` del reproductor? Sí durante el cambio al archivo:
/// la pausa que lo hace limpio no es una pausa del usuario.
pub(crate) fn swallow_playing(pb: &PlaybackManager) -> bool {
    pb.runtime.automix.on_file.as_ref().is_some_and(|file| file.switching.is_some())
}

/// EOF recibido del reproductor. `false`: no es una canción terminada, no avanzar.
///
/// * Durante el cambio al archivo (o la vuelta al arranque normal) un EOF es el de
///   la canción reemplazada.
/// * Si el archivo termina antes del traspaso, éste se completa primero y el EOF
///   cuenta como el de la canción siguiente.
/// * Un EOF del archivo ya traspasado es el final de la canción: se suelta el archivo.
pub(crate) fn ends_track(pb: &mut PlaybackManager) -> bool {
    drop_dead_file(pb);
    let Some(file) = pb.runtime.automix.on_file.as_ref() else {
        return true;
    };
    if file.switching.is_some() || file.leaving {
        return false;
    }
    if !file.handed_over {
        let end = file.rec.file_duration;
        let mut step = Step::default();
        hand_over(pb, end, &mut step);
    }
    pb.runtime.automix.on_file = None;
    true
}

/// El reproductor falló con el archivo cargado: volver al arranque normal de la ocurrencia.
pub(crate) fn on_track_failed(pb: &mut PlaybackManager) -> Option<Step> {
    drop_dead_file(pb);
    let key = pb.runtime.automix.on_file.as_ref()?.key.clone();
    let position = pb.position;
    let mut step = Step::default();
    step.leave = begin_leave(pb, position);
    if step.leave.is_some() {
        pb.runtime.automix.failed = Some(Failure::of(&key, "load"));
    }
    step.status = pb.runtime.automix.take_status_change();
    Some(step)
}

fn drop_dead_file(pb: &mut PlaybackManager) {
    let generation = pb.generation;
    if pb.runtime.automix.on_file.as_ref().is_some_and(|file| file.generation != generation) {
        pb.runtime.automix.on_file = None;
    }
}

fn gate_switch(pb: &mut PlaybackManager, raw: f64, ctx: &Ctx, step: &mut Step) -> Gate {
    let Some(file) = pb.runtime.automix.on_file.as_mut() else {
        return Gate::Pass;
    };
    let Some(switch) = file.switching else {
        return Gate::Pass;
    };
    match switch.phase {
        SwitchPhase::Loading => {
            // La canción vieja informa segundos >= a_cut; el archivo empieza en 0.
            let is_file = raw + 0.5 < file.rec.a_cut;
            if is_file {
                confirm_switch(pb, ctx, step);
            }
            Gate::Swallow
        }
        SwitchPhase::Settling { target, since } => {
            if (raw - target).abs() <= SEEK_NEAR || ctx.now.saturating_duration_since(since) >= SEEK_SETTLE {
                file.switching = None;
                Gate::Pass
            } else {
                Gate::Swallow
            }
        }
    }
}

/// El archivo ya está abierto: llevarlo al segundo que corresponde y reanudar.
fn confirm_switch(pb: &mut PlaybackManager, ctx: &Ctx, step: &mut Step) {
    let is_playing = pb.is_playing;
    let Some(file) = pb.runtime.automix.on_file.as_mut() else { return };
    let Some(switch) = file.switching else { return };
    if switch.phase != SwitchPhase::Loading {
        return;
    }
    let elapsed = ctx.now.saturating_duration_since(switch.started).as_secs_f64();
    let target = (switch.song_at_start + elapsed + RESUME_LEAD - file.rec.a_cut)
        .clamp(0.0, (file.rec.overlap_start - OVERLAP_GUARD).max(0.0));
    let sought = match ctx.engine {
        Some(engine) => engine.seek(target).and_then(|()| {
            if switch.was_playing && is_playing { engine.play() } else { Ok(()) }
        }),
        None => Err("sin reproductor".to_owned()),
    };
    match sought {
        Ok(()) => {
            file.switching = Some(Switching { phase: SwitchPhase::Settling { target, since: ctx.now }, ..switch });
            eprintln!(
                "[Automix] stage=splice target_ms={} gap_ms={}",
                (target * 1000.0) as i64,
                (elapsed * 1000.0) as i64
            );
        }
        Err(error) => {
            eprintln!("[Automix] stage=splice failed reason={error}");
            let key = file.key.clone();
            let position = switch.song_at_start + elapsed;
            file.switching = None;
            step.leave = begin_leave(pb, position);
            pb.runtime.automix.failed = Some(Failure::of(&key, "load"));
        }
    }
}

/// Lo que ya no corresponde se descarta: otra reproducción, cuenta, siguiente, Jam…
fn validate_plan(pb: &mut PlaybackManager, ctx: &Ctx, step: &mut Step) {
    pb.runtime.automix.jam = ctx.jam_active;
    let (job_stale, ready_stale, failed_stale, next_changed) = {
        let rt = &pb.runtime.automix;
        let jam = ctx.jam_active;
        let auth = ctx.auth_generation;
        let current = pb.queue.current_index.and_then(|index| pb.queue.items.get(index)).map(|entry| entry.entry_id.as_str());
        let next = next_entry_id(pb);
        (
            rt.job.as_ref().is_some_and(|job| jam || !key_matches(&job.key, pb, auth)),
            rt.ready.as_ref().is_some_and(|ready| jam || !key_matches(&ready.key, pb, auth)),
            rt.failed
                .as_ref()
                .is_some_and(|failure| current != Some(failure.from_entry.as_str()) || next != Some(failure.to_entry.as_str())),
            // Mientras suena la parte de A del archivo, el siguiente tiene que seguir siendo el de la mezcla.
            rt.on_file.as_ref().is_some_and(|file| {
                !file.handed_over && !file.leaving && file.switching.is_none() && (pb.is_repeat || next != Some(file.key.to_entry.as_str()))
            }),
        )
    };
    let repeat_on_file = pb.is_repeat
        && pb.runtime.automix.on_file.as_ref().is_some_and(|file| file.handed_over && !file.leaving && file.switching.is_none());
    // Un Jam toma el control de la manera normal: el archivo se suelta (arranque normal en el mismo
    // segundo) y no queda ningún estado de Automix.
    let jam_on_file = ctx.jam_active && pb.runtime.automix.on_file.as_ref().is_some_and(|file| !file.leaving);
    let disabled = !pb.runtime.automix.enabled || ctx.jam_active;
    let rt = &mut pb.runtime.automix;
    if job_stale || disabled {
        rt.cancel_job();
    }
    if ready_stale || disabled {
        rt.ready = None;
    }
    if failed_stale || disabled {
        rt.failed = None;
    }
    if next_changed || repeat_on_file || jam_on_file {
        let position = pb.position;
        step.leave = begin_leave(pb, position);
    }
}

fn maybe_hand_over(pb: &mut PlaybackManager, raw: f64, step: &mut Step) {
    let due = step.leave.is_none()
        && pb.runtime.automix.on_file.as_ref().is_some_and(|file| {
            !file.handed_over && !file.leaving && file.switching.is_none() && raw >= file.rec.handover
        });
    if due && !hand_over(pb, raw, step) {
        let position = pb.position;
        step.leave = begin_leave(pb, position);
    }
}

/// El traspaso: la cola avanza a la ocurrencia siguiente sin cargar su flujo.
///
/// Es un arranque normal visto desde fuera: `generation` sube, la ocurrencia pasa a
/// ser la actual, y posición, duración y metadatos son los de la canción nueva.
fn hand_over(pb: &mut PlaybackManager, raw: f64, step: &mut Step) -> bool {
    let Some(file) = pb.runtime.automix.on_file.as_ref() else { return false };
    if file.handed_over || file.leaving || pb.is_repeat {
        return false;
    }
    if next_entry_id(pb) != Some(file.key.to_entry.as_str()) {
        return false;
    }
    let (b_offset, file_duration) = (file.rec.b_offset, file.rec.file_duration);
    let to_entry = file.key.to_entry.clone();
    let previous_generation = pb.generation;
    let Some(entry) = pb.queue.select_entry(&to_entry) else { return false };
    pb.generation = pb.generation.wrapping_add(1);
    let owner = SeekOwner {
        auth: pb.observed_auth_generation,
        generation: pb.generation,
        entry_id: entry.entry_id.clone(),
    };
    pb.runtime.seek.adopt(previous_generation, &owner);
    pb.current_track = Some(PlaybackTrackDto {
        content_rating: entry.content_rating,
        is_upload: entry.is_upload,
        video_id: entry.video_id.clone(),
        title: entry.title.clone(),
        artists: entry.artists.clone(),
        thumbnail: entry.thumbnail.clone(),
        duration: entry.duration,
        artist_id: entry.artist_id.clone(),
        album_id: entry.album_id.clone(),
        album: entry.album.clone(),
        artist_runs: entry.artist_runs.clone(),
    });
    let position = (raw - b_offset).max(0.0);
    pb.position = position;
    pb.position_observed = Some((position, std::time::SystemTime::now()));
    pb.duration = (file_duration - b_offset).max(0.0);
    pb.loaded_generation = Some(pb.generation);
    pb.is_loading = false;
    pb.is_playing = true;
    pb.is_ended = false;
    pb.error = None;
    pb.eof_waiting = None;
    pb.runtime.pending_next = None;
    let generation = pb.generation;
    let rt = &mut pb.runtime.automix;
    rt.drop_plan();
    if let Some(file) = rt.on_file.as_mut() {
        file.handed_over = true;
        file.generation = generation;
    }
    eprintln!("[Automix] stage=handover generation={generation}");
    step.position = Some(position);
    step.state = Some(pb.to_dto());
    step.handover = Some(HandoverJob { generation, video_id: entry.video_id, is_upload: entry.is_upload });
    true
}

/// Empalme: de la canción al archivo, una sola vez, en el segundo `a_cut` de la canción.
fn maybe_splice(pb: &mut PlaybackManager, position: f64, ctx: &Ctx, step: &mut Step) {
    let Some(ready) = pb.runtime.automix.ready.as_mut() else { return };
    let (a_cut, deadline) = (ready.rec.a_cut, ready.rec.splice_deadline());
    // Pasado el último momento no se empalma; si se vuelve atrás, sigue valiendo.
    ready.missed = position > deadline;
    if ctx.jam_active || position < a_cut || ready.missed {
        if ready.missed {
            eprintln!("[Automix] stage=splice skipped reason=late");
        }
        return;
    }
    let eligible = pb.is_playing
        && !pb.is_loading
        && pb.loaded_generation == Some(pb.generation)
        && pb.runtime.seek.pending.is_none()
        && pb.runtime.automix.on_file.as_ref().map_or(true, |file| file.switching.is_none() && !file.leaving);
    let Some(engine) = ctx.engine.filter(|_| eligible) else { return };
    let previous_gain = crate::volume::combined_gain(pb.volume, pb.runtime.exponential_volume, pb.runtime.track_gain);
    let gain = crate::volume::combined_gain(pb.volume, pb.runtime.exponential_volume, None);
    let Some(path) = pb.runtime.automix.ready.as_ref().map(|ready| ready.rec.file_path.clone()) else { return };
    // Pausar antes de cargar: el archivo se abre quieto, se lleva al segundo exacto y
    // recién entonces suena. Sin eso se oirían unos milisegundos de su comienzo.
    if engine.pause().is_err() {
        return;
    }
    if let Err(error) = engine.load_file(&path, gain) {
        eprintln!("[Automix] stage=splice failed reason={error}");
        let _ = engine.set_gain(previous_gain);
        let _ = engine.play();
        let rt = &mut pb.runtime.automix;
        if let Some(ready) = rt.ready.take() {
            rt.failed = Some(Failure::of(&ready.key, "load"));
        }
        return;
    }
    let was_playing = pb.is_playing;
    let generation = pb.generation;
    let rt = &mut pb.runtime.automix;
    let Some(ready) = rt.ready.take() else { return };
    rt.next_token = rt.next_token.wrapping_add(1);
    let token = rt.next_token;
    rt.on_file = Some(OnFile {
        rec: ready.rec,
        key: ready.key,
        from_gain: ready.from_gain,
        to_gain: ready.to_gain,
        generation,
        handed_over: false,
        switching: Some(Switching {
            token,
            started: ctx.now,
            song_at_start: position,
            was_playing,
            phase: SwitchPhase::Loading,
        }),
        leaving: false,
        last_raw: 0.0,
    });
    // Las ganancias van horneadas en el archivo: la del reproductor por canción se anula.
    pb.runtime.track_gain = None;
    step.watchdog = Some(token);
}

fn maybe_prepare(pb: &mut PlaybackManager, ctx: &Ctx, step: &mut Step) {
    if pb.runtime.automix.job.is_some() || pb.runtime.automix.ready.is_some() {
        return;
    }
    let key = match plan_for(pb, ctx.jam_active) {
        Ok(key) => key,
        Err(skip) => {
            pb.runtime.automix.skip = Some(skip);
            return;
        }
    };
    pb.runtime.automix.skip = None;
    let failed_here = pb.runtime.automix.failed.is_some();
    let busy = pb.runtime.automix.on_file.as_ref().is_some_and(|file| file.switching.is_some() || file.leaving);
    let started = pb.is_playing && !pb.is_loading && pb.loaded_generation == Some(pb.generation);
    // La ganancia de la siguiente se pide resolviéndola, y eso pisa el seguimiento de
    // historial de la actual: se espera a que su escucha ya esté registrada.
    let history_settled = pb.runtime.automix.history_done == Some(pb.generation);
    if failed_here || busy || !started || !history_settled {
        return;
    }
    let from_gain = song_gain(pb);
    let rt = &mut pb.runtime.automix;
    let request_id = rt.next_request_id();
    rt.job = Some(Job { request_id: request_id.clone(), key: key.clone() });
    step.prepare = Some(PrepareJob { request_id, key, from_gain });
}

/// Prepara el regreso al arranque normal de la ocurrencia actual, en `position`.
fn begin_leave(pb: &mut PlaybackManager, position: f64) -> Option<LeaveJob> {
    let entry_id = pb.queue.current()?.entry_id;
    let file = pb.runtime.automix.on_file.as_mut()?;
    if file.leaving {
        return None;
    }
    file.leaving = true;
    file.switching = None;
    let owner = SeekOwner { auth: pb.observed_auth_generation, generation: pb.generation, entry_id: entry_id.clone() };
    let revision = pb.runtime.seek.begin(owner, position.max(0.0), pb.duration, Instant::now(), true);
    pb.runtime.automix.drop_plan();
    eprintln!("[Automix] stage=leave");
    Some(LeaveJob {
        entry_id,
        generation: pb.generation,
        paused: !pb.is_playing && !pb.is_loading,
        revision,
    })
}

// MARK: Seeks

/// Qué hacer con un seek del usuario (en segundos de la canción que se muestra).
#[derive(Debug, PartialEq)]
pub(crate) enum SeekRoute {
    /// Seek normal; el destino se traduce con [`engine_seek_target`].
    Native,
    /// Esa parte de la canción no está en el archivo: arranque normal en ese segundo.
    Restart,
}

pub(crate) fn seek_route(pb: &PlaybackManager, seconds: f64) -> SeekRoute {
    match pb.runtime.automix.on_file.as_ref() {
        Some(file) if file.generation == pb.generation && !file.leaving && file.file_seek_target(seconds).is_none() => {
            SeekRoute::Restart
        }
        _ => SeekRoute::Native,
    }
}

/// Se llama con el cerrojo al aceptar un seek con `SeekRoute::Restart`.
pub(crate) fn mark_leaving(pb: &mut PlaybackManager) {
    pb.runtime.automix.drop_plan();
    if let Some(file) = pb.runtime.automix.on_file.as_mut() {
        file.leaving = true;
        file.switching = None;
    }
}

/// Segundo del reproductor al que corresponde un segundo de la canción.
pub(crate) fn engine_seek_target(pb: &PlaybackManager, song: f64) -> f64 {
    match pb.runtime.automix.on_file.as_ref() {
        Some(file) if file.generation == pb.generation => file.file_seek_target(song).unwrap_or(song),
        _ => song,
    }
}

/// ¿Hay un regreso al arranque normal o un empalme en curso? El seek pendiente espera.
pub(crate) fn seek_blocked(pb: &PlaybackManager) -> bool {
    pb.runtime.automix.on_file.as_ref().is_some_and(|file| file.leaving || file.switching.is_some())
}

// MARK: Jam

/// El Jam empezó o terminó: se aplica en el acto (sin esperar a la próxima posición, que puede no
/// llegar si el reproductor está en pausa) y se avisa a la interfaz.
pub(crate) fn jam_changed(app: &tauri::AppHandle) {
    let jam_active = crate::jam::is_active(app);
    let Some(state) = app.try_state::<AppState>() else { return };
    let auth_generation = state.auth_generation.load(Ordering::SeqCst);
    let step = {
        let Ok(mut pb) = state.playback.lock() else { return };
        let ctx = Ctx { now: Instant::now(), jam_active, auth_generation, engine: None };
        let mut step = Step::default();
        validate_plan(&mut pb, &ctx, &mut step);
        step.cancels.append(&mut pb.runtime.automix.cancels);
        step.status = pb.runtime.automix.take_status_change();
        step
    };
    finish(app, step);
}

// MARK: Historial

/// El historial de `generation` ya se registró (con éxito o no): el seguimiento del
/// core queda libre para que la preparación resuelva la canción siguiente.
pub(crate) fn history_settled(app: &tauri::AppHandle, generation: u64) {
    let state = app.state::<AppState>();
    let Ok(mut pb) = state.playback.lock() else { return };
    if pb.generation == generation {
        pb.runtime.automix.history_done = Some(generation);
    }
}

// MARK: Fuera del cerrojo

/// Ejecuta lo que un evento dejó pendiente. Se llama con el cerrojo ya soltado.
pub(crate) fn finish(app: &tauri::AppHandle, step: Step) {
    if let Some(dto) = &step.state {
        let _ = app.emit("playback-state-changed", dto);
    }
    cancel_requests(app, step.cancels);
    if let Some(status) = &step.status {
        let _ = app.emit("automix-status-changed", status);
    }
    if let Some(job) = step.prepare {
        tauri::async_runtime::spawn(run_prepare(app.clone(), job));
    }
    if let Some(job) = step.handover {
        after_handover(app, job);
    }
    if let Some(job) = step.leave {
        leave_file(app, job);
    }
    if let Some(token) = step.watchdog {
        let app = app.clone();
        tauri::async_runtime::spawn(async move {
            tokio::time::sleep(SWITCH_WATCHDOG).await;
            watchdog(&app, token);
        });
    }
}

pub(crate) fn cancel_requests(app: &tauri::AppHandle, requests: Vec<String>) {
    if requests.is_empty() {
        return;
    }
    let state = app.state::<AppState>();
    let core = state.core.read().ok().and_then(|core| core.clone());
    if let Some(core) = core {
        for request in requests {
            core.cancel_automix(request);
        }
    }
}

fn emit_status(app: &tauri::AppHandle, status: Option<AutomixStatusDto>) {
    if let Some(status) = status {
        let _ = app.emit("automix-status-changed", status);
    }
}

fn leave_file(app: &tauri::AppHandle, job: LeaveJob) {
    let app_for_start = app.clone();
    let LeaveJob { entry_id, generation, paused, revision } = job;
    tauri::async_runtime::spawn(async move {
        if crate::commands::playback::start_queue_entry(app_for_start.clone(), entry_id, generation, paused)
            .await
            .is_err()
        {
            crate::commands::playback::finish_seek_failure(
                &app_for_start,
                revision,
                "No se pudo cargar la canción para cambiar de posición.",
            );
        }
    });
    crate::commands::playback::watch_seek(app.clone(), revision);
}

fn watchdog(app: &tauri::AppHandle, token: u64) {
    let state = app.state::<AppState>();
    let step = {
        let Ok(mut pb) = state.playback.lock() else { return };
        let stuck = pb
            .runtime
            .automix
            .on_file
            .as_ref()
            .is_some_and(|file| file.switching.is_some_and(|sw| sw.token == token && sw.phase == SwitchPhase::Loading));
        if !stuck {
            return;
        }
        eprintln!("[Automix] stage=splice failed reason=watchdog");
        let position = pb.position;
        let mut step = Step::default();
        let key = pb.runtime.automix.on_file.as_ref().map(|file| file.key.clone());
        step.leave = begin_leave(&mut pb, position);
        if let Some(key) = key {
            pb.runtime.automix.failed = Some(Failure::of(&key, "load"));
        }
        step.status = pb.runtime.automix.take_status_change();
        step
    };
    finish(app, step);
}

/// Tras el traspaso: la canción nueva se resuelve en segundo plano (sin reproducirla)
/// para que su historial cuente como el de una reproducción normal, y se hidrata como
/// cualquier arranque.
fn after_handover(app: &tauri::AppHandle, job: HandoverJob) {
    crate::commands::playback::after_start(app.clone());
    let app = app.clone();
    tauri::async_runtime::spawn(async move {
        let state = app.state::<AppState>();
        let auth_generation = state.auth_generation.load(Ordering::SeqCst);
        let _operation = state.auth_operation.read().await;
        let current = |app: &tauri::AppHandle| {
            let state = app.state::<AppState>();
            state.auth_generation.load(Ordering::SeqCst) == auth_generation
                && state.playback.lock().is_ok_and(|pb| pb.generation == job.generation)
        };
        if !current(&app) {
            return;
        }
        let core = state.core.read().ok().and_then(|core| core.clone());
        let Some(core) = core else { return };
        if let Err(error) = core.resolve_stream(job.video_id.clone(), job.is_upload).await {
            eprintln!(
                "[Automix] stage=resolve-next category={}",
                crate::cipher_runtime::resolution_failure_category(&error)
            );
        }
    });
}

// MARK: Preparación

fn failure_reason(error: &sideb_core::SideBError) -> &'static str {
    let message = match error {
        sideb_core::SideBError::StreamError { message } => message.as_str(),
        _ => return "failed",
    };
    if message.starts_with("automix:unsupported-format") {
        "unsupported-format"
    } else if message.starts_with("automix:too-long") {
        "too-long"
    } else {
        "failed"
    }
}

fn is_cancelled(error: &sideb_core::SideBError) -> bool {
    matches!(error, sideb_core::SideBError::StreamError { message } if message.starts_with("automix:cancelled"))
}

fn job_is_current(app: &tauri::AppHandle, request_id: &str) -> bool {
    let state = app.state::<AppState>();
    let auth = state.auth_generation.load(Ordering::SeqCst);
    state.playback.lock().is_ok_and(|pb| {
        pb.runtime
            .automix
            .job
            .as_ref()
            .is_some_and(|job| job.request_id == request_id && key_matches(&job.key, &pb, auth))
    })
}

fn fail_job(app: &tauri::AppHandle, request_id: &str, reason: &'static str) {
    let state = app.state::<AppState>();
    let status = {
        let Ok(mut pb) = state.playback.lock() else { return };
        let rt = &mut pb.runtime.automix;
        let Some(job) = rt.job.take().filter(|job| job.request_id == request_id) else { return };
        rt.failed = Some(Failure::of(&job.key, reason));
        rt.take_status_change()
    };
    emit_status(app, status);
}

async fn run_prepare(app: tauri::AppHandle, job: PrepareJob) {
    let state = app.state::<AppState>();
    let core = state.core.read().ok().and_then(|core| core.clone());
    let Some(core) = core else {
        fail_job(&app, &job.request_id, "failed");
        return;
    };
    let started = Instant::now();
    // La ganancia de la canción siguiente sólo la da `resolve_stream`; con el seguimiento
    // de historial de la actual ya registrado, pisarlo es inocuo.
    let to_gain = {
        let _operation = state.auth_operation.read().await;
        if !job_is_current(&app, &job.request_id) {
            return;
        }
        match core.resolve_stream(job.key.to_video.clone(), job.key.to_upload).await {
            Ok(info) => info.loudness_db.filter(|gain| gain.is_finite()),
            Err(error) => {
                eprintln!(
                    "[Automix] stage=resolve-gain category={}",
                    crate::cipher_runtime::resolution_failure_category(&error)
                );
                fail_job(&app, &job.request_id, "resolve");
                return;
            }
        }
    };
    if !job_is_current(&app, &job.request_id) {
        return;
    }
    let cache_dir = match app.path().app_cache_dir() {
        Ok(dir) => dir.join("automix"),
        Err(_) => {
            fail_job(&app, &job.request_id, "failed");
            return;
        }
    };
    let _ = std::fs::create_dir_all(&cache_dir);
    let result = core
        .prepare_automix(
            job.request_id.clone(),
            job.key.from_video.clone(),
            job.key.from_upload,
            job.from_gain,
            job.key.to_video.clone(),
            job.key.to_upload,
            to_gain,
            cache_dir.to_string_lossy().into_owned(),
        )
        .await;
    let elapsed_ms = started.elapsed().as_millis();
    match result {
        Ok(record) => {
            let rec = Transition::from(&record);
            eprintln!(
                "[Automix] stage=prepared kind={} bars={} stems_model={} elapsed_ms={elapsed_ms} detail={}",
                rec.kind, rec.bars, rec.stems_model, rec.detail
            );
            let status = {
                let auth = state.auth_generation.load(Ordering::SeqCst);
                let Ok(mut pb) = state.playback.lock() else { return };
                let current = pb
                    .runtime
                    .automix
                    .job
                    .as_ref()
                    .is_some_and(|stored| stored.request_id == job.request_id && key_matches(&stored.key, &pb, auth));
                if !current {
                    return;
                }
                let rt = &mut pb.runtime.automix;
                rt.job = None;
                if rec.sane() {
                    rt.ready = Some(Ready { key: job.key.clone(), rec, from_gain: job.from_gain, to_gain, missed: false });
                } else {
                    eprintln!("[Automix] stage=prepared rejected reason=bad-numbers");
                    rt.failed = Some(Failure::of(&job.key, "failed"));
                }
                pb.runtime.automix.take_status_change()
            };
            emit_status(&app, status);
        }
        Err(error) if is_cancelled(&error) => {
            eprintln!("[Automix] stage=prepared cancelled elapsed_ms={elapsed_ms}");
        }
        Err(error) => {
            let reason = failure_reason(&error);
            eprintln!("[Automix] stage=prepared failed reason={reason} elapsed_ms={elapsed_ms}");
            fail_job(&app, &job.request_id, reason);
        }
    }
}

// MARK: Comandos

#[tauri::command]
pub(crate) fn get_automix_status(state: tauri::State<'_, AppState>) -> Result<AutomixStatusDto, crate::CommandError> {
    let mut pb = state
        .playback
        .lock()
        .map_err(|_| crate::CommandError::new("LOCK_ERROR", "No se pudo leer el estado de Automix."))?;
    Ok(pb.runtime.automix.snapshot())
}

#[tauri::command]
pub(crate) fn set_automix_enabled(
    app: tauri::AppHandle,
    state: tauri::State<'_, AppState>,
    enabled: bool,
) -> Result<AutomixStatusDto, crate::CommandError> {
    let (status, cancels) = {
        let mut pb = state
            .playback
            .lock()
            .map_err(|_| crate::CommandError::new("LOCK_ERROR", "No se pudo cambiar Automix."))?;
        let rt = &mut pb.runtime.automix;
        rt.enabled = enabled;
        if !enabled {
            // Apagar descarta lo preparado; un archivo que ya suena termina su traspaso.
            rt.drop_plan();
            rt.skip = None;
        }
        let status = rt.snapshot();
        let cancels = std::mem::take(&mut rt.cancels);
        // Persistir el ajuste junto con el resto de las preferencias de reproducción.
        let _ = pb.to_dto();
        (status, cancels)
    };
    cancel_requests(&app, cancels);
    let _ = app.emit("automix-status-changed", &status);
    Ok(status)
}


#[cfg(test)]
mod tests {
    use super::*;
    use crate::queue::QueueSourceDto;
    use std::cell::RefCell;

    #[derive(Default)]
    struct Fake {
        log: RefCell<Vec<String>>,
        fail_load: bool,
    }
    impl Engine for Fake {
        fn pause(&self) -> Result<(), String> {
            self.log.borrow_mut().push("pause".into());
            Ok(())
        }
        fn play(&self) -> Result<(), String> {
            self.log.borrow_mut().push("play".into());
            Ok(())
        }
        fn load_file(&self, path: &str, gain_db: Option<f64>) -> Result<(), String> {
            self.log.borrow_mut().push(format!("load {path} {gain_db:?}"));
            if self.fail_load { Err("no abre".into()) } else { Ok(()) }
        }
        fn seek(&self, seconds: f64) -> Result<(), String> {
            self.log.borrow_mut().push(format!("seek {seconds:.2}"));
            Ok(())
        }
        fn set_gain(&self, gain_db: Option<f64>) -> Result<(), String> {
            self.log.borrow_mut().push(format!("gain {gain_db:?}"));
            Ok(())
        }
    }

    fn entry(id: &str, album: Option<&str>) -> QueueEntryDto {
        let mut entry = QueueEntryDto::new(id.into(), id.into(), "Artista".into(), None, Some(200.0));
        entry.album_id = album.map(str::to_owned);
        entry
    }

    fn playing(albums: &[Option<&str>]) -> PlaybackManager {
        let mut pb = PlaybackManager::new();
        let items = albums.iter().enumerate().map(|(i, album)| entry(&format!("song{i}"), *album)).collect();
        pb.queue.replace(items, 0, QueueSourceDto { kind: "playlist".into(), id: Some("list".into()), title: None });
        let current = pb.queue.current().unwrap();
        pb.current_track = Some(PlaybackTrackDto {
            content_rating: current.content_rating,
            is_upload: false,
            video_id: current.video_id.clone(),
            title: current.title.clone(),
            artists: current.artists.clone(),
            thumbnail: None,
            duration: Some(200.0),
            artist_id: None,
            album_id: current.album_id.clone(),
            album: None,
            artist_runs: vec![],
        });
        pb.generation = 5;
        pb.loaded_generation = Some(5);
        pb.observed_auth_generation = 1;
        pb.is_playing = true;
        pb.duration = 200.0;
        pb.runtime.track_gain = Some(-3.0);
        pb.runtime.automix.enabled = true;
        pb
    }

    /// a_cut 100; A sin tocar 8 s; mezcla hasta el segundo 24 del archivo; B entra en su
    /// segundo 10 (archivo 24 → b_offset 14); traspaso en el segundo 16 del archivo.
    fn transition() -> Transition {
        Transition {
            kind: "mix".into(),
            file_path: "mix.wav".into(),
            file_duration: 214.0,
            a_cut: 100.0,
            overlap_start: 8.0,
            overlap_end: 24.0,
            b_offset: 14.0,
            b_entry: 10.0,
            handover: 16.0,
            bpm_from: 120.0,
            bpm_to: 124.0,
            bars: 8,
            stems_model: true,
            detail: "prueba".into(),
        }
    }

    fn ctx<'a>(engine: &'a Fake, now: Instant) -> Ctx<'a> {
        Ctx { now, jam_active: false, auth_generation: 1, engine: Some(engine) }
    }

    fn arm(pb: &mut PlaybackManager) {
        let key = plan_for(pb, false).unwrap();
        pb.runtime.automix.ready =
            Some(Ready { key, rec: transition(), from_gain: Some(-3.0), to_gain: Some(-5.0), missed: false });
    }

    /// Lleva `pb` hasta que el reproductor ya toca el archivo en `target`.
    fn spliced(pb: &mut PlaybackManager, engine: &Fake, t0: Instant) -> Step {
        arm(pb);
        let step = on_position(pb, 101.0, &ctx(engine, t0));
        assert!(pb.runtime.automix.on_file.is_some());
        step
    }

    #[test]
    fn eligibility_covers_jam_repeat_next_album_and_same_song() {
        let mut pb = playing(&[Some("a"), Some("b")]);
        assert!(plan_for(&pb, false).is_ok());
        assert_eq!(plan_for(&pb, true), Err(Skip::Jam));
        pb.is_repeat = true;
        assert_eq!(plan_for(&pb, false), Err(Skip::Repeat));
        pb.is_repeat = false;
        pb.runtime.automix.enabled = false;
        assert_eq!(plan_for(&pb, false), Err(Skip::Disabled));
        pb.runtime.automix.enabled = true;
        // Mismo álbum no vacío en la actual y la siguiente: sin mezcla.
        let same = playing(&[Some("a"), Some("a")]);
        assert_eq!(plan_for(&same, false), Err(Skip::SameAlbum));
        // Álbum vacío o ausente no cuenta como el mismo álbum.
        assert!(plan_for(&playing(&[Some(" "), Some(" ")]), false).is_ok());
        assert!(plan_for(&playing(&[None, None]), false).is_ok());
        // Sin siguiente conocida.
        assert_eq!(plan_for(&playing(&[Some("a")]), false), Err(Skip::NoNext));
        // La misma canción dos veces seguidas.
        let mut twice = playing(&[None, None]);
        twice.queue.items[1].video_id = twice.queue.items[0].video_id.clone();
        assert_eq!(plan_for(&twice, false), Err(Skip::SameSong));
    }

    #[test]
    fn preparation_waits_for_history_and_is_asked_once_with_the_current_song_gain() {
        let mut pb = playing(&[None, None]);
        let engine = Fake::default();
        let t0 = Instant::now();
        let step = on_position(&mut pb, 5.0, &ctx(&engine, t0));
        assert!(step.prepare.is_none(), "la historia de la canción actual todavía no se registró");
        pb.runtime.automix.history_done = Some(5);
        let step = on_position(&mut pb, 6.0, &ctx(&engine, t0));
        let job = step.prepare.expect("se pide la preparación");
        assert_eq!(job.from_gain, Some(-3.0));
        assert_eq!(job.key.to_video, "song1");
        assert_eq!(step.status.as_ref().map(|s| s.phase), Some(AutomixPhase::Preparing));
        // Una segunda vez no repite el pedido.
        assert!(on_position(&mut pb, 7.0, &ctx(&engine, t0)).prepare.is_none());
    }

    #[test]
    fn changing_the_next_entry_cancels_the_job_and_drops_the_prepared_file() {
        let mut pb = playing(&[None, None]);
        let engine = Fake::default();
        let t0 = Instant::now();
        pb.runtime.automix.history_done = Some(5);
        let request = on_position(&mut pb, 6.0, &ctx(&engine, t0)).prepare.unwrap().request_id;
        // El usuario pone otra canción como siguiente.
        pb.queue.enqueue(vec![entry("other", None)], true);
        let step = on_position(&mut pb, 7.0, &ctx(&engine, t0));
        assert_eq!(step.cancels, vec![request]);
        assert!(pb.runtime.automix.ready.is_none());
        // Con la siguiente nueva se pide una preparación nueva, con otro id.
        let again = step.prepare.expect("nueva preparación para el par nuevo");
        assert_eq!(again.key.to_video, "other");

        // Lo mismo con un archivo ya listo: otra siguiente, otra cuenta, Jam o apagar.
        let mut ready = playing(&[None, None]);
        arm(&mut ready);
        ready.queue.enqueue(vec![entry("other", None)], true);
        on_position(&mut ready, 7.0, &ctx(&engine, t0));
        assert!(ready.runtime.automix.ready.is_none());
        let mut account = playing(&[None, None]);
        arm(&mut account);
        let mut other_account = ctx(&engine, t0);
        other_account.auth_generation = 2;
        on_position(&mut account, 7.0, &other_account);
        assert!(account.runtime.automix.ready.is_none());
        let mut jam = playing(&[None, None]);
        arm(&mut jam);
        let mut jam_ctx = ctx(&engine, t0);
        jam_ctx.jam_active = true;
        on_position(&mut jam, 7.0, &jam_ctx);
        assert!(jam.runtime.automix.ready.is_none());
        let mut generation = playing(&[None, None]);
        arm(&mut generation);
        generation.generation = 6;
        on_position(&mut generation, 7.0, &ctx(&engine, t0));
        assert!(generation.runtime.automix.ready.is_none());
    }

    #[test]
    fn splice_pauses_loads_without_track_gain_and_the_replaced_stream_eof_does_not_advance() {
        let mut pb = playing(&[None, None]);
        let engine = Fake::default();
        let t0 = Instant::now();
        let step = spliced(&mut pb, &engine, t0);
        assert_eq!(engine.log.borrow().as_slice(), ["pause", "load mix.wav None"]);
        assert_eq!(pb.runtime.track_gain, None, "la ganancia va horneada en el archivo");
        assert!(step.watchdog.is_some());
        assert!(swallow_playing(&pb), "la pausa del empalme no es del usuario");
        // El EOF de la canción reemplazada no avanza la cola.
        let before = (pb.generation, pb.queue.current_index);
        assert!(!ends_track(&mut pb));
        assert_eq!((pb.generation, pb.queue.current_index), before);
        // Las posiciones de la canción vieja (>= a_cut) se descartan hasta confirmar el archivo.
        assert!(on_position(&mut pb, 101.3, &ctx(&engine, t0)).position.is_none());
        assert!(pb.runtime.automix.on_file.as_ref().unwrap().switching.is_some());
    }

    #[test]
    fn the_file_is_sought_to_the_shown_second_and_positions_resume_in_song_time() {
        let mut pb = playing(&[None, None]);
        let engine = Fake::default();
        let t0 = Instant::now();
        spliced(&mut pb, &engine, t0);
        // 0,2 s después llega la duración del archivo: seek al segundo que corresponde.
        let (mapped, _) = on_duration(&mut pb, 214.0, &ctx(&engine, t0 + Duration::from_millis(200)));
        assert_eq!(mapped, None, "la duración del archivo no es la de la canción");
        let log = engine.log.borrow().clone();
        assert_eq!(&log[2..], ["seek 1.23", "play"]); // 101 − 100 + 0,2 + 0,03
        drop(log);
        // Mientras llegan posiciones lejos del destino se descartan.
        assert!(on_position(&mut pb, 0.0, &ctx(&engine, t0)).position.is_none());
        let step = on_position(&mut pb, 1.3, &ctx(&engine, t0));
        assert_eq!(step.position, Some(101.3));
        assert!(!swallow_playing(&pb));
        // Seguidas, se traducen como a_cut + archivo.
        assert_eq!(on_position(&mut pb, 5.0, &ctx(&engine, t0)).position, Some(105.0));
    }

    #[test]
    fn a_paused_user_is_not_resumed_by_the_splice() {
        let mut pb = playing(&[None, None]);
        let engine = Fake::default();
        let t0 = Instant::now();
        spliced(&mut pb, &engine, t0);
        pb.is_playing = false; // el usuario pausó durante el cambio
        on_duration(&mut pb, 214.0, &ctx(&engine, t0));
        assert!(!engine.log.borrow().iter().any(|line| line == "play"));
    }

    #[test]
    fn a_failing_load_restores_the_stream_and_does_not_retry_the_pair() {
        let mut pb = playing(&[None, None]);
        let engine = Fake { fail_load: true, ..Default::default() };
        let t0 = Instant::now();
        arm(&mut pb);
        on_position(&mut pb, 101.0, &ctx(&engine, t0));
        assert!(pb.runtime.automix.on_file.is_none());
        assert!(engine.log.borrow().iter().any(|line| line == "play"));
        assert_eq!(pb.runtime.track_gain, Some(-3.0));
        let step = on_position(&mut pb, 102.0, &ctx(&engine, t0));
        assert!(step.prepare.is_none());
        assert_eq!(pb.runtime.automix.status().phase, AutomixPhase::Unavailable);
    }

    #[test]
    fn a_late_splice_is_skipped_but_valid_again_when_seeking_back() {
        let mut pb = playing(&[None, None]);
        let engine = Fake::default();
        let t0 = Instant::now();
        arm(&mut pb);
        // a_cut 100 + 8 − 0,5 = 107,5: pasado eso no se empalma.
        let step = on_position(&mut pb, 108.0, &ctx(&engine, t0));
        assert!(pb.runtime.automix.on_file.is_none());
        assert!(engine.log.borrow().is_empty());
        let status = step.status.expect("cambió a no disponible");
        assert_eq!((status.phase, status.reason.as_deref()), (AutomixPhase::Unavailable, Some("late")));
        on_position(&mut pb, 103.0, &ctx(&engine, t0));
        assert!(pb.runtime.automix.on_file.is_some());
        // Antes de a_cut tampoco.
        let mut early = playing(&[None, None]);
        arm(&mut early);
        on_position(&mut early, 99.9, &ctx(&engine, t0));
        assert!(early.runtime.automix.on_file.is_none());
    }

    fn on_file_after_splice(pb: &mut PlaybackManager, engine: &Fake, t0: Instant) {
        spliced(pb, engine, t0);
        on_duration(pb, 214.0, &ctx(engine, t0));
        on_position(pb, 1.2, &ctx(engine, t0));
    }

    #[test]
    fn until_the_handover_the_old_song_stays_and_then_the_queue_advances_without_a_stream_load() {
        let mut pb = playing(&[None, None, None]);
        let engine = Fake::default();
        let t0 = Instant::now();
        on_file_after_splice(&mut pb, &engine, t0);
        // Archivo 15 s: sigue la canción vieja, en a_cut + t.
        let step = on_position(&mut pb, 15.0, &ctx(&engine, t0));
        assert_eq!(step.position, Some(115.0));
        assert!(step.handover.is_none());
        assert_eq!(pb.queue.current_index, Some(0));
        // Archivo 16 s: traspaso.
        let before = pb.generation;
        let step = on_position(&mut pb, 16.0, &ctx(&engine, t0));
        assert_eq!(pb.generation, before + 1);
        assert_eq!(pb.queue.current_index, Some(1));
        assert_eq!(pb.current_track.as_ref().unwrap().video_id, "song1");
        assert_eq!(pb.loaded_generation, Some(before + 1));
        assert_eq!(step.position, Some(2.0)); // 16 − b_offset 14
        assert_eq!(pb.duration, 200.0); // 214 − 14
        assert!(pb.is_playing && !pb.is_loading && !pb.is_ended);
        let dto = step.state.expect("estado publicado como un arranque normal");
        assert_eq!(dto.generation, before + 1);
        assert_eq!(dto.current_track.unwrap().video_id, "song1");
        let handover = step.handover.unwrap();
        assert_eq!((handover.generation, handover.video_id.as_str()), (before + 1, "song1"));
        // No se tocó el reproductor en el traspaso.
        assert_eq!(engine.log.borrow().len(), 4);
        // Después de overlap_end la mezcla terminó y las posiciones son archivo − b_offset.
        assert_eq!(on_position(&mut pb, 60.0, &ctx(&engine, t0)).position, Some(46.0));
        assert_eq!(pb.runtime.automix.status().phase, AutomixPhase::Idle);
        // El EOF del archivo es el final de la canción: avanza normal y suelta el archivo.
        assert!(ends_track(&mut pb));
        assert!(pb.runtime.automix.on_file.is_none());
    }

    #[test]
    fn eof_before_the_handover_completes_it_first() {
        let mut pb = playing(&[None, None, None]);
        let engine = Fake::default();
        let t0 = Instant::now();
        on_file_after_splice(&mut pb, &engine, t0);
        assert!(ends_track(&mut pb));
        assert_eq!(pb.queue.current_index, Some(1));
        assert!(pb.runtime.automix.on_file.is_none());
    }

    #[test]
    fn handover_is_abandoned_to_a_normal_start_if_the_next_entry_changed() {
        let mut pb = playing(&[None, None, None]);
        let engine = Fake::default();
        let t0 = Instant::now();
        on_file_after_splice(&mut pb, &engine, t0);
        pb.queue.enqueue(vec![entry("other", None)], true);
        let step = on_position(&mut pb, 10.0, &ctx(&engine, t0));
        let leave = step.leave.expect("vuelve al arranque normal de la actual");
        assert_eq!(pb.queue.current_index, Some(0));
        assert_eq!(leave.entry_id, pb.queue.current().unwrap().entry_id);
        assert!(pb.runtime.seek.pending.as_ref().unwrap().resuming);
        assert!(seek_blocked(&pb), "el seek pendiente espera a la carga nueva");
        assert!(!ends_track(&mut pb), "el EOF del archivo abandonado no avanza");
    }

    #[test]
    fn repeat_while_a_file_plays_leaves_it() {
        let mut pb = playing(&[None, None, None]);
        let engine = Fake::default();
        let t0 = Instant::now();
        on_file_after_splice(&mut pb, &engine, t0);
        on_position(&mut pb, 30.0, &ctx(&engine, t0));
        pb.is_repeat = true;
        assert!(on_position(&mut pb, 31.0, &ctx(&engine, t0)).leave.is_some());
    }

    #[test]
    fn seeks_map_to_the_file_or_restart_normally() {
        let mut pb = playing(&[None, None, None]);
        let engine = Fake::default();
        let t0 = Instant::now();
        assert_eq!(seek_route(&pb, 50.0), SeekRoute::Native);
        assert_eq!(engine_seek_target(&pb, 50.0), 50.0);
        on_file_after_splice(&mut pb, &engine, t0);
        // Antes del traspaso sólo vale la parte de A sin tocar del archivo.
        assert_eq!(seek_route(&pb, 103.0), SeekRoute::Native);
        assert_eq!(engine_seek_target(&pb, 103.0), 3.0);
        assert_eq!(seek_route(&pb, 40.0), SeekRoute::Restart);
        on_position(&mut pb, 16.0, &ctx(&engine, t0));
        // B desde b_entry + margen: archivo = s + b_offset.
        assert_eq!(seek_route(&pb, 90.0), SeekRoute::Native);
        assert_eq!(engine_seek_target(&pb, 90.0), 104.0);
        assert_eq!(seek_route(&pb, 10.5), SeekRoute::Restart);
        assert_eq!(seek_route(&pb, 2.0), SeekRoute::Restart);
        mark_leaving(&mut pb);
        assert_eq!(seek_route(&pb, 2.0), SeekRoute::Native, "ya se está saliendo del archivo");
    }

    #[test]
    fn chaining_uses_the_second_song_gain_and_the_second_files_own_clock() {
        let mut pb = playing(&[None, None, None]);
        let engine = Fake::default();
        let t0 = Instant::now();
        on_file_after_splice(&mut pb, &engine, t0);
        on_position(&mut pb, 16.0, &ctx(&engine, t0)); // B (song1) actual, suena del archivo 1
        on_position(&mut pb, 60.0, &ctx(&engine, t0)); // posición 46
        // La preparación B→C usa la ganancia de B (la de la mezcla), no la del reproductor (None).
        pb.runtime.automix.history_done = Some(pb.generation);
        let job = on_position(&mut pb, 61.0, &ctx(&engine, t0)).prepare.expect("B → C");
        assert_eq!(job.from_gain, Some(-5.0));
        assert_eq!((job.key.from_video.as_str(), job.key.to_video.as_str()), ("song1", "song2"));
        // Listo el archivo 2 (a_cut en segundos de B): se empalma al llegar B a a_cut.
        let mut second = transition();
        second.file_path = "mix2.wav".into();
        second.a_cut = 120.0;
        pb.runtime.automix.job = None;
        pb.runtime.automix.ready =
            Some(Ready { key: job.key, rec: second, from_gain: job.from_gain, to_gain: Some(0.0), missed: false });
        // Archivo 1 en 134 s → B en 120 s = a_cut del archivo 2.
        let step = on_position(&mut pb, 134.0, &ctx(&engine, t0 + Duration::from_secs(1)));
        assert!(step.watchdog.is_some());
        assert_eq!(engine.log.borrow().last().unwrap(), "load mix2.wav None");
        // En el archivo 2, antes del traspaso se muestra B en a_cut + t.
        on_duration(&mut pb, 214.0, &ctx(&engine, t0 + Duration::from_secs(1)));
        assert_eq!(on_position(&mut pb, 0.2, &ctx(&engine, t0)).position, Some(120.2));
        let handover = on_position(&mut pb, 16.0, &ctx(&engine, t0));
        assert_eq!(pb.queue.current_index, Some(2));
        assert_eq!(handover.position, Some(2.0));
    }

    #[test]
    fn a_failure_of_the_file_goes_back_to_the_normal_start() {
        let mut pb = playing(&[None, None]);
        let engine = Fake::default();
        let t0 = Instant::now();
        on_file_after_splice(&mut pb, &engine, t0);
        let step = on_track_failed(&mut pb).expect("lo maneja Automix");
        assert!(step.leave.is_some());
        assert_eq!(pb.runtime.automix.status().reason.as_deref(), Some("load"));
        // Sin archivo cargado, un fallo es el de siempre.
        let mut plain = playing(&[None, None]);
        assert!(on_track_failed(&mut plain).is_none());
    }

    #[test]
    fn a_jam_cancels_the_preparation_and_disables_automix_without_touching_the_preference() {
        let mut pb = playing(&[None, None]);
        let engine = Fake::default();
        let t0 = Instant::now();
        pb.runtime.automix.history_done = Some(5);
        let request = on_position(&mut pb, 6.0, &ctx(&engine, t0)).prepare.unwrap().request_id;
        let mut jam = ctx(&engine, t0);
        jam.jam_active = true;
        let step = on_position(&mut pb, 7.0, &jam);
        assert_eq!(step.cancels, vec![request]);
        assert!(step.prepare.is_none(), "no se prepara nada durante un Jam");
        let status = step.status.expect("la interfaz se entera");
        assert_eq!((status.enabled, status.phase, status.reason.as_deref()), (true, AutomixPhase::Unavailable, Some("jam")));
        assert!(pb.runtime.automix.enabled, "la preferencia guardada no cambia");
        // El archivo ya preparado tampoco se usa.
        let mut ready = playing(&[None, None]);
        arm(&mut ready);
        on_position(&mut ready, 101.0, &jam);
        assert!(ready.runtime.automix.ready.is_none() && ready.runtime.automix.on_file.is_none());
        assert!(engine.log.borrow().is_empty());
        // Al terminar el Jam vuelve a aplicarse la preferencia.
        pb.runtime.automix.history_done = Some(5);
        let step = on_position(&mut pb, 8.0, &ctx(&engine, t0));
        assert!(step.prepare.is_some());
        assert_eq!(pb.runtime.automix.status().reason, None);
        // Con la preferencia apagada el Jam también se ve como no disponible, y sigue apagada.
        let mut off = playing(&[None, None]);
        off.runtime.automix.enabled = false;
        on_position(&mut off, 1.0, &jam);
        let status = off.runtime.automix.status();
        assert_eq!((status.enabled, status.phase), (false, AutomixPhase::Unavailable));
    }

    #[test]
    fn a_jam_starting_while_the_file_plays_leaves_it_and_no_automix_state_remains() {
        let mut pb = playing(&[None, None, None]);
        let engine = Fake::default();
        let t0 = Instant::now();
        on_file_after_splice(&mut pb, &engine, t0);
        let mut jam = ctx(&engine, t0);
        jam.jam_active = true;
        let step = on_position(&mut pb, 5.0, &jam);
        let leave = step.leave.expect("el Jam toma el control de la manera normal");
        assert_eq!(leave.generation, pb.generation);
        assert!(!ends_track(&mut pb), "el EOF del archivo abandonado no avanza la cola");
        assert_eq!(step.status.unwrap().marker_seconds, None);
        // La carga normal (play_song) suelta el archivo y deja el estado limpio.
        pb.runtime.automix.reset_for_new_load();
        assert!(pb.runtime.automix.on_file.is_none() && pb.runtime.automix.ready.is_none() && pb.runtime.automix.job.is_none());
        assert!(pb.runtime.automix.enabled);
        // También después del traspaso (B sonando del archivo).
        let mut late = playing(&[None, None, None]);
        on_file_after_splice(&mut late, &engine, t0);
        on_position(&mut late, 20.0, &ctx(&engine, t0));
        assert!(on_position(&mut late, 21.0, &jam).leave.is_some());
    }

    #[test]
    fn jam_changed_style_revalidation_cancels_without_a_position_event() {
        let mut pb = playing(&[None, None]);
        let engine = Fake::default();
        let t0 = Instant::now();
        arm(&mut pb);
        let mut jam = ctx(&engine, t0);
        jam.jam_active = true;
        let mut step = Step::default();
        validate_plan(&mut pb, &jam, &mut step);
        assert!(pb.runtime.automix.ready.is_none());
        assert_eq!(pb.runtime.automix.status().reason.as_deref(), Some("jam"));
    }

    #[test]
    fn the_progress_marker_is_a_cut_plus_overlap_start_while_ready_or_before_the_handover_only() {
        let mut pb = playing(&[None, None, None]);
        let engine = Fake::default();
        let t0 = Instant::now();
        let marker = |pb: &PlaybackManager| pb.runtime.automix.status().marker_seconds;
        assert_eq!(marker(&pb), None, "sin transición no hay marca");
        arm(&mut pb);
        assert_eq!(marker(&pb), Some(108.0));
        // Pasado el último momento no habrá empalme: sin marca; si se vuelve atrás, vuelve.
        on_position(&mut pb, 109.0, &ctx(&engine, t0));
        assert_eq!(marker(&pb), None);
        on_position(&mut pb, 50.0, &ctx(&engine, t0));
        assert_eq!(marker(&pb), Some(108.0));
        // Sonando el archivo, hasta el traspaso.
        on_position(&mut pb, 101.0, &ctx(&engine, t0));
        on_duration(&mut pb, 214.0, &ctx(&engine, t0));
        on_position(&mut pb, 1.2, &ctx(&engine, t0));
        assert_eq!(marker(&pb), Some(108.0));
        on_position(&mut pb, 15.0, &ctx(&engine, t0));
        assert_eq!(marker(&pb), Some(108.0));
        let step = on_position(&mut pb, 16.0, &ctx(&engine, t0));
        assert_eq!(marker(&pb), None, "traspasada: la marca desaparece");
        assert_eq!(step.status.as_ref().unwrap().marker_seconds, None);
        // Cancelada, apagada o abandonada.
        let mut cancelled = playing(&[None, None]);
        arm(&mut cancelled);
        cancelled.queue.enqueue(vec![entry("other", None)], true);
        on_position(&mut cancelled, 7.0, &ctx(&engine, t0));
        assert_eq!(marker(&cancelled), None);
        let mut off = playing(&[None, None]);
        arm(&mut off);
        off.runtime.automix.enabled = false;
        assert_eq!(marker(&off), None);
        let mut left = playing(&[None, None, None]);
        on_file_after_splice(&mut left, &engine, t0);
        mark_leaving(&mut left);
        assert_eq!(marker(&left), None);
        // Los números imposibles no dan marca.
        let mut bad = playing(&[None, None]);
        arm(&mut bad);
        bad.runtime.automix.ready.as_mut().unwrap().rec.a_cut = f64::NAN;
        assert_eq!(marker(&bad), None);
        // La marca viaja a la interfaz en camelCase.
        let mut shown = playing(&[None, None]);
        arm(&mut shown);
        assert_eq!(serde_json::to_value(shown.runtime.automix.status()).unwrap()["markerSeconds"], 108.0);
    }

    #[test]
    fn status_mapping_follows_the_setting_and_the_state() {
        let mut rt = AutomixRuntime::default();
        assert_eq!(rt.status().phase, AutomixPhase::Off);
        rt.enabled = true;
        assert_eq!(rt.status().phase, AutomixPhase::Idle);
        rt.skip = Some(Skip::SameAlbum);
        assert_eq!(rt.status().reason.as_deref(), Some("album"));
        let json = serde_json::to_value(rt.status()).unwrap();
        assert_eq!(json["phase"], "idle");
        assert!(json.get("filePath").is_none());
    }

    #[test]
    fn numbers_that_make_no_sense_are_not_played() {
        let mut bad = transition();
        assert!(bad.sane());
        bad.handover = 999.0;
        assert!(!bad.sane());
        let mut nan = transition();
        nan.a_cut = f64::NAN;
        assert!(!nan.sane());
        let mut empty = transition();
        empty.file_path.clear();
        assert!(!empty.sane());
    }
}
