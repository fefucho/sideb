import {loadJam} from './jam-modules.mjs';
import {fakeApp, fakeTime, flush, joined, track} from './jam-harness.mjs';

const {createJam} = await loadJam('index');

/** A Jam object over the fake app; `join` runs the whole handshake when `joinTo` is given. */
export async function bootJam(options = {}) {
  const time = fakeTime();
  const app = fakeApp({time, ...(options.app ?? {})});
  const jam = createJam({rpc: app.rpc, listen: app.listen, now: time.now, schedule: time.schedule});
  await flush();
  const box = {view: null};
  jam.state.subscribe(view => { box.view = view; });
  const ctx = {time, app, jam, box, get view() { return box.view; }};
  /** Joins and lets the plugin report its first state. */
  ctx.start = async ({canControl = true, state = {}, ms = 50} = {}) => {
    await jam.actions.join('https://open.spotify.com/socialsession/SECRETTOKEN123');
    app.emit(joined({canControl}));
    app.emit(app.jamState({track: track(1), queue: [track(2), track(3)], ...state}));
    await time.advance(ms);
    jam.onPlaybackState(app.state());
  };
  /** Pushes a plugin state and mirrors the app's playback snapshot, as the shell would. */
  ctx.push = async (state, ms = 50) => {
    app.emit(app.jamState(state));
    await time.advance(ms);
    jam.onPlaybackState(app.state());
  };
  /** Native (opaque) entry id of the queue entry that carries the Jam occurrence `spotify:track:<n>` number `occurrence`. */
  ctx.native = (n, occurrence = 0) => app.player.items.find(item => item.sourceOccurrenceId === `jam|spotify:track:${n}|${occurrence}`)?.entryId;
  ctx.toastKeys = () => box.view.toasts.map(toast => toast.key);
  return ctx;
}
