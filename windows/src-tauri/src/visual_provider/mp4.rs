//! Validation of the single file a provider may hand back. Windows has no AVFoundation, so the
//! ISO-BMFF container is parsed directly (no decoder, no external tools): file type, the one video
//! track's sample entry (`avc1`/`avc3` = H.264), pixel size, movie duration and nominal frame rate
//! (samples / media duration, the same definition as `AVAssetTrack.nominalFrameRate`).
//! Anything unusual (fragmented movies, several video tracks, other codecs) is rejected.

use super::protocol::{Failure, Outcome};
use std::io::{Read, Seek, SeekFrom};
use std::path::Path;

pub const MAX_FILE_BYTES: u64 = 24 * 1024 * 1024;
const MAX_MOOV_BYTES: u64 = 8 * 1024 * 1024;
const MAX_DEPTH: u32 = 8;
const MAX_BOXES: u32 = 4096;

#[derive(Debug, Clone, PartialEq)]
pub struct VideoAsset {
    pub codec: &'static str,
    pub width: u32,
    pub height: u32,
    pub frame_rate: f64,
    pub duration: f64,
    pub size_bytes: u64,
}

/// Portrait envelope: height 720-1920, width <= 1080, about 9:16, 0 < fps <= 60.1.
pub fn valid_dimensions(width: f64, height: f64, fps: f64) -> bool {
    width > 0.0
        && (720.0..=1920.0).contains(&height)
        && width <= 1080.0
        && (0.55..=0.58).contains(&(width / height.max(1.0)))
        && fps.is_finite()
        && fps > 0.0
        && fps <= 60.1
}

pub fn valid_duration(seconds: f64) -> bool {
    seconds.is_finite() && (2.5..=8.5).contains(&seconds)
}

/// Regular file, no symlink/reparse point, 1 byte to 24 MiB. Returns its size.
pub fn plain_file_size(path: &Path, max: u64) -> Outcome<u64> {
    let meta = std::fs::symlink_metadata(path).map_err(|_| Failure::Invalid)?;
    if meta.file_type().is_symlink() || !meta.is_file() || meta.len() == 0 || meta.len() > max {
        return Err(Failure::Invalid);
    }
    #[cfg(windows)]
    {
        use std::os::windows::fs::MetadataExt;
        const FILE_ATTRIBUTE_REPARSE_POINT: u32 = 0x400;
        if meta.file_attributes() & FILE_ATTRIBUTE_REPARSE_POINT != 0 {
            return Err(Failure::Invalid);
        }
    }
    Ok(meta.len())
}

pub fn validate_file(path: &Path) -> Outcome<VideoAsset> {
    let size = plain_file_size(path, MAX_FILE_BYTES)?;
    let mut file = std::fs::File::open(path).map_err(|_| Failure::Invalid)?;
    let info = parse(&mut file, size)?;
    if !valid_duration(info.duration)
        || !valid_dimensions(info.width as f64, info.height as f64, info.frame_rate)
    {
        return Err(Failure::Invalid);
    }
    Ok(VideoAsset {
        codec: "h264",
        width: info.width,
        height: info.height,
        frame_rate: info.frame_rate,
        duration: info.duration,
        size_bytes: size,
    })
}

#[derive(Debug, Clone, Copy, PartialEq)]
pub struct ContainerInfo {
    pub width: u32,
    pub height: u32,
    pub frame_rate: f64,
    pub duration: f64,
}

#[derive(Clone, Copy)]
struct BoxHeader {
    kind: [u8; 4],
    /// Offset of the payload and its length.
    start: u64,
    len: u64,
}

fn read_exact<R: Read>(reader: &mut R, buf: &mut [u8]) -> Outcome<()> {
    reader.read_exact(buf).map_err(|_| Failure::Invalid)
}

fn read_header<R: Read + Seek>(reader: &mut R, pos: u64, end: u64) -> Outcome<Option<BoxHeader>> {
    if pos == end {
        return Ok(None);
    }
    if end - pos < 8 {
        return Err(Failure::Invalid);
    }
    reader
        .seek(SeekFrom::Start(pos))
        .map_err(|_| Failure::Invalid)?;
    let mut head = [0u8; 8];
    read_exact(reader, &mut head)?;
    let size32 = u32::from_be_bytes([head[0], head[1], head[2], head[3]]) as u64;
    let kind = [head[4], head[5], head[6], head[7]];
    let (header_len, total) = match size32 {
        0 => (8, end - pos),
        1 => {
            let mut big = [0u8; 8];
            read_exact(reader, &mut big)?;
            (16, u64::from_be_bytes(big))
        }
        n => (8, n),
    };
    if total < header_len || total > end - pos {
        return Err(Failure::Invalid);
    }
    Ok(Some(BoxHeader {
        kind,
        start: pos + header_len,
        len: total - header_len,
    }))
}

fn children<R: Read + Seek>(
    reader: &mut R,
    start: u64,
    len: u64,
    budget: &mut u32,
) -> Outcome<Vec<BoxHeader>> {
    let end = start + len;
    let mut pos = start;
    let mut found = Vec::new();
    while let Some(header) = read_header(reader, pos, end)? {
        *budget = budget.checked_sub(1).ok_or(Failure::Invalid)?;
        pos = header.start + header.len;
        found.push(header);
    }
    Ok(found)
}

fn first<'a>(boxes: &'a [BoxHeader], kind: &[u8; 4]) -> Option<&'a BoxHeader> {
    boxes.iter().find(|b| &b.kind == kind)
}

fn payload<R: Read + Seek>(reader: &mut R, header: &BoxHeader, cap: u64) -> Outcome<Vec<u8>> {
    if header.len > cap {
        return Err(Failure::Invalid);
    }
    reader
        .seek(SeekFrom::Start(header.start))
        .map_err(|_| Failure::Invalid)?;
    let mut buf = vec![0u8; header.len as usize];
    read_exact(reader, &mut buf)?;
    Ok(buf)
}

fn be32(buf: &[u8], at: usize) -> Outcome<u32> {
    buf.get(at..at + 4)
        .map(|b| u32::from_be_bytes([b[0], b[1], b[2], b[3]]))
        .ok_or(Failure::Invalid)
}
fn be16(buf: &[u8], at: usize) -> Outcome<u16> {
    buf.get(at..at + 2)
        .map(|b| u16::from_be_bytes([b[0], b[1]]))
        .ok_or(Failure::Invalid)
}
fn be64(buf: &[u8], at: usize) -> Outcome<u64> {
    buf.get(at..at + 8)
        .map(|b| u64::from_be_bytes([b[0], b[1], b[2], b[3], b[4], b[5], b[6], b[7]]))
        .ok_or(Failure::Invalid)
}

/// `mvhd`/`mdhd`: (timescale, duration) for version 0 and 1.
fn timescale_and_duration(buf: &[u8]) -> Outcome<(u32, u64)> {
    match buf.first().copied().ok_or(Failure::Invalid)? {
        0 => Ok((be32(buf, 12)?, be32(buf, 16)? as u64)),
        1 => Ok((be32(buf, 20)?, be64(buf, 24)?)),
        _ => Err(Failure::Invalid),
    }
}

fn sample_count_from_stts(buf: &[u8]) -> Outcome<u64> {
    let entries = be32(buf, 4)? as usize;
    if entries > 1 << 20 {
        return Err(Failure::Invalid);
    }
    let mut total = 0u64;
    for i in 0..entries {
        total = total
            .checked_add(be32(buf, 8 + i * 8)? as u64)
            .ok_or(Failure::Invalid)?;
    }
    Ok(total)
}

struct VideoTrack {
    width: u32,
    height: u32,
    codec_ok: bool,
    samples: u64,
    media_seconds: f64,
}

fn parse_track<R: Read + Seek>(
    reader: &mut R,
    trak: &BoxHeader,
    depth: u32,
    budget: &mut u32,
) -> Outcome<Option<VideoTrack>> {
    if depth > MAX_DEPTH {
        return Err(Failure::Invalid);
    }
    let parts = children(reader, trak.start, trak.len, budget)?;
    let mdia = first(&parts, b"mdia").ok_or(Failure::Invalid)?;
    let media = children(reader, mdia.start, mdia.len, budget)?;
    let hdlr = first(&media, b"hdlr").ok_or(Failure::Invalid)?;
    let handler = payload(reader, hdlr, 4096)?;
    if handler.get(8..12) != Some(b"vide") {
        return Ok(None);
    }
    let tkhd = payload(
        reader,
        first(&parts, b"tkhd").ok_or(Failure::Invalid)?,
        4096,
    )?;
    let (tk_w, tk_h) = match tkhd.first().copied().ok_or(Failure::Invalid)? {
        0 => (be32(&tkhd, 76)? >> 16, be32(&tkhd, 80)? >> 16),
        1 => (be32(&tkhd, 88)? >> 16, be32(&tkhd, 92)? >> 16),
        _ => return Err(Failure::Invalid),
    };
    let (scale, duration) = timescale_and_duration(&payload(
        reader,
        first(&media, b"mdhd").ok_or(Failure::Invalid)?,
        4096,
    )?)?;
    let minf = first(&media, b"minf").ok_or(Failure::Invalid)?;
    let minf_children = children(reader, minf.start, minf.len, budget)?;
    let stbl = first(&minf_children, b"stbl").ok_or(Failure::Invalid)?;
    let table = children(reader, stbl.start, stbl.len, budget)?;
    let stsd = payload(
        reader,
        first(&table, b"stsd").ok_or(Failure::Invalid)?,
        MAX_MOOV_BYTES,
    )?;
    // full box header (4) + entry count (4) + first entry: size, type, then the visual sample entry.
    if be32(&stsd, 4)? == 0 {
        return Err(Failure::Invalid);
    }
    let entry_type = stsd.get(12..16).ok_or(Failure::Invalid)?;
    let codec_ok = entry_type == b"avc1" || entry_type == b"avc3";
    let (entry_w, entry_h) = (be16(&stsd, 16 + 24)? as u32, be16(&stsd, 16 + 26)? as u32);
    let (width, height) = if entry_w > 0 && entry_h > 0 {
        (entry_w, entry_h)
    } else {
        (tk_w, tk_h)
    };
    let samples = sample_count_from_stts(&payload(
        reader,
        first(&table, b"stts").ok_or(Failure::Invalid)?,
        MAX_MOOV_BYTES,
    )?)?;
    if scale == 0 {
        return Err(Failure::Invalid);
    }
    Ok(Some(VideoTrack {
        width,
        height,
        codec_ok,
        samples,
        media_seconds: duration as f64 / scale as f64,
    }))
}

/// Reads container facts without decoding. `len` is the file length.
pub fn parse<R: Read + Seek>(reader: &mut R, len: u64) -> Outcome<ContainerInfo> {
    let mut budget = MAX_BOXES;
    let top = children(reader, 0, len, &mut budget)?;
    if first(&top, b"ftyp").is_none() || first(&top, b"mdat").is_none() {
        return Err(Failure::Invalid);
    }
    let moov = first(&top, b"moov").ok_or(Failure::Invalid)?;
    if moov.len > MAX_MOOV_BYTES {
        return Err(Failure::Invalid);
    }
    let movie = children(reader, moov.start, moov.len, &mut budget)?;
    // Fragmented movies carry their samples in `moof`: not what a short Canvas looks like.
    if first(&movie, b"mvex").is_some() || first(&top, b"moof").is_some() {
        return Err(Failure::Invalid);
    }
    let (scale, movie_duration) = timescale_and_duration(&payload(
        reader,
        first(&movie, b"mvhd").ok_or(Failure::Invalid)?,
        4096,
    )?)?;
    if scale == 0 {
        return Err(Failure::Invalid);
    }
    let mut video = None;
    for trak in movie.iter().filter(|b| &b.kind == b"trak") {
        if let Some(track) = parse_track(reader, trak, 1, &mut budget)? {
            if video.replace(track).is_some() {
                return Err(Failure::Invalid); // exactly one video track
            }
        }
    }
    let track = video.ok_or(Failure::Invalid)?;
    if !track.codec_ok || track.samples == 0 || track.media_seconds <= 0.0 {
        return Err(Failure::Invalid);
    }
    Ok(ContainerInfo {
        width: track.width,
        height: track.height,
        frame_rate: track.samples as f64 / track.media_seconds,
        duration: movie_duration as f64 / scale as f64,
    })
}

#[cfg(test)]
pub(crate) mod fixture {
    //! Minimal MP4 builder shared by tests.
    pub fn boxed(kind: &[u8; 4], body: &[u8]) -> Vec<u8> {
        let mut out = ((body.len() + 8) as u32).to_be_bytes().to_vec();
        out.extend_from_slice(kind);
        out.extend_from_slice(body);
        out
    }

    pub struct Spec {
        pub codec: &'static [u8; 4],
        pub width: u16,
        pub height: u16,
        pub timescale: u32,
        pub duration: u32,
        pub samples: u32,
        pub video_tracks: usize,
        pub fragmented: bool,
    }

    impl Spec {
        pub fn canvas() -> Self {
            Self {
                codec: b"avc1",
                width: 720,
                height: 1280,
                timescale: 24_000,
                duration: 169_176,
                samples: 169,
                video_tracks: 1,
                fragmented: false,
            }
        }
    }

    fn track(spec: &Spec, handler: &[u8; 4]) -> Vec<u8> {
        let mut tkhd = vec![0u8; 84];
        tkhd[76..80].copy_from_slice(&((spec.width as u32) << 16).to_be_bytes());
        tkhd[80..84].copy_from_slice(&((spec.height as u32) << 16).to_be_bytes());
        let mut mdhd = vec![0u8; 20];
        mdhd[12..16].copy_from_slice(&spec.timescale.to_be_bytes());
        mdhd[16..20].copy_from_slice(&spec.duration.to_be_bytes());
        let mut hdlr = vec![0u8; 8];
        hdlr.extend_from_slice(handler);
        hdlr.extend_from_slice(&[0u8; 13]);
        let mut entry = vec![0u8; 6 + 2 + 16];
        entry.extend_from_slice(&spec.width.to_be_bytes());
        entry.extend_from_slice(&spec.height.to_be_bytes());
        entry.extend_from_slice(&[0u8; 50]);
        let mut stsd = vec![0, 0, 0, 0, 0, 0, 0, 1];
        stsd.extend(boxed(spec.codec, &entry));
        let mut stts = vec![0, 0, 0, 0, 0, 0, 0, 1];
        stts.extend_from_slice(&spec.samples.to_be_bytes());
        stts.extend_from_slice(&1000u32.to_be_bytes());
        let stbl = [boxed(b"stsd", &stsd), boxed(b"stts", &stts)].concat();
        let minf = boxed(b"stbl", &stbl);
        let mdia = [
            boxed(b"mdhd", &mdhd),
            boxed(b"hdlr", &hdlr),
            boxed(b"minf", &minf),
        ]
        .concat();
        boxed(
            b"trak",
            &[boxed(b"tkhd", &tkhd), boxed(b"mdia", &mdia)].concat(),
        )
    }

    pub fn build(spec: &Spec) -> Vec<u8> {
        let mut mvhd = vec![0u8; 100];
        mvhd[12..16].copy_from_slice(&spec.timescale.to_be_bytes());
        mvhd[16..20].copy_from_slice(&spec.duration.to_be_bytes());
        let mut moov = boxed(b"mvhd", &mvhd);
        for _ in 0..spec.video_tracks {
            moov.extend(track(spec, b"vide"));
        }
        moov.extend(track(spec, b"soun"));
        if spec.fragmented {
            moov.extend(boxed(b"mvex", &[]));
        }
        [
            boxed(b"ftyp", b"isom\0\0\0\0isomavc1"),
            boxed(b"mdat", &[0u8; 64]),
            boxed(b"moov", &moov),
        ]
        .concat()
    }
}

#[cfg(test)]
mod tests {
    use super::fixture::*;
    use super::*;
    use std::io::Cursor;

    fn info(bytes: &[u8]) -> Outcome<ContainerInfo> {
        parse(&mut Cursor::new(bytes), bytes.len() as u64)
    }

    #[test]
    fn reads_canvas_dimensions_duration_and_nominal_fps() {
        let parsed = info(&build(&Spec::canvas())).unwrap();
        assert_eq!((parsed.width, parsed.height), (720, 1280));
        assert!((parsed.duration - 7.049).abs() < 0.001);
        assert!((parsed.frame_rate - 23.976).abs() < 0.01);
        assert!(valid_dimensions(720.0, 1280.0, parsed.frame_rate));
        assert!(valid_duration(parsed.duration));
    }

    #[test]
    fn rejects_other_codecs_extra_video_tracks_fragments_and_truncation() {
        assert_eq!(
            info(&build(&Spec {
                codec: b"hvc1",
                ..Spec::canvas()
            })),
            Err(Failure::Invalid)
        );
        assert_eq!(
            info(&build(&Spec {
                video_tracks: 2,
                ..Spec::canvas()
            })),
            Err(Failure::Invalid)
        );
        assert_eq!(
            info(&build(&Spec {
                fragmented: true,
                ..Spec::canvas()
            })),
            Err(Failure::Invalid)
        );
        assert_eq!(
            info(&build(&Spec {
                samples: 0,
                ..Spec::canvas()
            })),
            Err(Failure::Invalid)
        );
        let whole = build(&Spec::canvas());
        assert_eq!(info(&whole[..whole.len() - 30]), Err(Failure::Invalid));
        assert_eq!(info(b"definitely not an mp4 file"), Err(Failure::Invalid));
        assert_eq!(info(&[]), Err(Failure::Invalid));
        assert!(info(&build(&Spec {
            codec: b"avc3",
            ..Spec::canvas()
        }))
        .is_ok());
    }

    #[test]
    fn rejects_oversized_box_claims() {
        let mut bytes = build(&Spec::canvas());
        bytes[0..4].copy_from_slice(&u32::MAX.to_be_bytes()); // ftyp claims 4 GiB
        assert_eq!(info(&bytes), Err(Failure::Invalid));
    }

    #[test]
    fn envelope_matches_the_mac_host() {
        assert!(valid_dimensions(720.0, 1280.0, 23.976));
        assert!(valid_dimensions(1080.0, 1920.0, 60.1));
        assert!(!valid_dimensions(1080.0, 1921.0, 30.0));
        assert!(!valid_dimensions(360.0, 640.0, 30.0)); // below 720 high
        assert!(!valid_dimensions(1280.0, 720.0, 30.0)); // landscape
        assert!(!valid_dimensions(720.0, 1280.0, 60.2));
        assert!(!valid_dimensions(720.0, 1280.0, 0.0));
        assert!(!valid_dimensions(720.0, 1280.0, f64::NAN));
        assert!(valid_duration(2.5) && valid_duration(8.5));
        assert!(!valid_duration(2.4) && !valid_duration(8.6) && !valid_duration(f64::INFINITY));
    }

    fn temp_file(name: &str, bytes: &[u8]) -> std::path::PathBuf {
        let dir = std::env::temp_dir().join(format!("sideb-mp4-{}-{name}", std::process::id()));
        std::fs::create_dir_all(&dir).unwrap();
        let path = dir.join("visual.mp4");
        std::fs::write(&path, bytes).unwrap();
        path
    }

    #[test]
    fn validates_files_on_disk() {
        let path = temp_file("ok", &build(&Spec::canvas()));
        let asset = validate_file(&path).unwrap();
        assert_eq!(
            (asset.codec, asset.width, asset.height),
            ("h264", 720, 1280)
        );
        assert_eq!(asset.size_bytes, std::fs::metadata(&path).unwrap().len());
        let short = temp_file(
            "short",
            &build(&Spec {
                duration: 24_000,
                ..Spec::canvas()
            }),
        );
        assert_eq!(validate_file(&short), Err(Failure::Invalid)); // 1 s
        let empty = temp_file("empty", &[]);
        assert_eq!(validate_file(&empty), Err(Failure::Invalid));
        assert_eq!(
            validate_file(&path.with_file_name("missing.mp4")),
            Err(Failure::Invalid)
        );
    }

    #[cfg(unix)]
    #[test]
    fn symlinks_are_not_regular_files() {
        let real = temp_file("link-real", &build(&Spec::canvas()));
        let link = real.with_file_name("link.mp4");
        let _ = std::fs::remove_file(&link);
        std::os::unix::fs::symlink(&real, &link).unwrap();
        assert_eq!(validate_file(&link), Err(Failure::Invalid));
        assert!(validate_file(&real).is_ok());
    }
}
