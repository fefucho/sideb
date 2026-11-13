import assert from 'node:assert/strict';
import {test} from 'node:test';
import {bootJam} from './helpers/jam-boot.mjs';
import {catalog, track} from './helpers/jam-harness.mjs';

const search = missing => query => {
  const n = /Title (\w+)/.exec(query)?.[1];
  return n && !missing.includes(n) ? [catalog(n)] : [];
};

test('outside a Jam the wrapper is the raw rpc', async () => {
  const jam = await bootJam();
  const state = await jam.jam.rpc('pause_playback');
  assert.equal(jam.app.callsOf('pause_playback').length, 1);
  assert.equal(state.isPlaying, false);
  await jam.jam.rpc('play_song', {videoId: 'x', queueItems: []});
  assert.equal(jam.app.callsOf('play_song').length, 1);
  assert.equal(jam.view.pendingExit, null);
  jam.app.on('set_shuffle', () => 'raw');
  assert.equal(await jam.jam.rpc('set_shuffle', {enabled: true}), 'raw');
  assert.equal(jam.app.callsOf('set_shuffle').length, 1);
});

test('transport commands go to the Jam and leave local audio untouched', async () => {
  const jam = await bootJam();
  await jam.start({state: {positionMs: 1000}});
  await jam.time.advance(500);
  const local = jam.app.calls.length;
  for (const command of ['pause_playback', 'resume_playback', 'next_track', 'previous_track']) {
    const state = await jam.jam.rpc(command);
    assert.equal(typeof state.isPlaying, 'boolean', `${command} answers with the playback state`);
  }
  await jam.jam.rpc('seek_playback_identified', {seconds: 42.5, expectedGeneration: 1, expectedAuthGeneration: 0, expectedEntryId: jam.native(1)});
  const sent = jam.app.sent().filter(message => message.type === 'command');
  assert.deepEqual(sent.map(message => message.action), ['pause', 'resume', 'next', 'previous', 'seek']);
  assert.equal(sent[4].positionMs, 42500);
  assert.ok(sent.every(message => typeof message.requestId === 'string'));
  const after = jam.app.calls.slice(local).map(call => call.command);
  for (const command of ['pause_playback', 'resume_playback', 'next_track', 'previous_track', 'seek_playback_identified']) assert.ok(!after.includes(command), command);
});

test('seek subtracts the manual offset so the Jam gets its own timeline', async () => {
  const jam = await bootJam();
  await jam.start();
  jam.jam.actions.setManualOffset(300);
  await jam.jam.rpc('seek_playback_identified', {seconds: 10, expectedGeneration: 1, expectedAuthGeneration: 0, expectedEntryId: 'x'});
  assert.equal(jam.app.sent().find(message => message.action === 'seek').positionMs, 9700);
});

test('without control, pause/resume/seek fall back to local behaviour with a toast; next and previous only explain', async () => {
  const jam = await bootJam();
  await jam.start({canControl: false});
  await jam.time.advance(500);
  await jam.jam.rpc('pause_playback');
  assert.equal(jam.app.callsOf('pause_playback').length >= 1, true);
  assert.ok(jam.toastKeys().includes('jam.notice.localOnly'));
  assert.equal(jam.app.sent().filter(m => m.type === 'command').length, 0);
  // The local pause sticks: sync does not resume it.
  await jam.time.advance(5000);
  assert.equal(jam.app.player.playing, false);
  await jam.jam.rpc('resume_playback');
  await jam.time.advance(500);
  assert.equal(jam.app.player.playing, true);
  await jam.jam.rpc('seek_playback_identified', {seconds: 100, expectedGeneration: jam.app.player.generation, expectedAuthGeneration: 0, expectedEntryId: jam.native(1)});
  assert.equal(jam.app.callsOf('seek_playback_identified').at(-1).args.seconds, 100);
  await jam.time.advance(8000);
  assert.ok(Math.abs(jam.app.position() - 108) < 1, 'a local seek is not fought by the sync');
  await jam.jam.rpc('next_track');
  assert.ok(jam.toastKeys().includes('jam.notice.noControl'));
  assert.equal(jam.app.callsOf('next_track').length, 0);
});

test('a rejected command falls back to local with a toast', async () => {
  const jam = await bootJam();
  await jam.start();
  await jam.jam.rpc('pause_playback');
  const message = jam.app.sent().find(m => m.action === 'pause');
  jam.app.emit({type: 'commandResult', action: 'pause', ok: false, detail: 'rejected', requestId: message.requestId});
  await jam.time.advance(100);
  assert.equal(jam.app.callsOf('pause_playback').length >= 1, true);
  assert.ok(jam.toastKeys().includes('jam.notice.localOnly'));
  // A rejected `next` has no local equivalent.
  await jam.jam.rpc('next_track');
  const next = jam.app.sent().find(m => m.action === 'next');
  jam.app.emit({type: 'commandResult', action: 'next', ok: false, detail: null, requestId: next.requestId});
  await jam.time.advance(100);
  assert.ok(jam.toastKeys().includes('jam.notice.rejected'));
  assert.equal(jam.app.callsOf('next_track').length, 0);
});

test('a runtime that refuses jam_send also falls back', async () => {
  const jam = await bootJam();
  await jam.start();
  jam.app.on('jam_send', () => { throw {code: 'JAM_NOT_RUNNING', message: 'x'}; });
  await jam.jam.rpc('pause_playback');
  await jam.time.advance(50);
  assert.equal(jam.app.callsOf('pause_playback').length >= 1, true);
  assert.ok(jam.toastKeys().includes('jam.notice.localOnly'));
});

test('queue edits map native entry ids to the plugin queue through unmatched tracks, with the revision', async () => {
  // Jam queue: 2 (matched), 3 (unmatched), 4 (matched), 5 (matched). Native rows: 2, 4, 5.
  const jam = await bootJam({app: {search: search(['3'])}});
  await jam.start({state: {queue: [track(2), track(3), track(4), track(5)], revision: 'rev-9'}});
  await jam.time.advance(1500);
  await jam.jam.rpc('remove_queue_entry', {entryId: jam.native(4)});
  const remove = jam.app.sent().find(m => m.action === 'remove');
  assert.equal(remove.index, 2);
  assert.equal(remove.revision, 'rev-9');
  // Not confirmed by a new state: reported as not applied after the timeout.
  await jam.time.advance(3100);
  assert.ok(jam.toastKeys().includes('jam.notice.notApplied'));

  await jam.jam.rpc('move_queue_entry', {entryId: jam.native(5), beforeEntryId: jam.native(2)});
  const move = jam.app.sent().find(m => m.action === 'move');
  assert.deepEqual([move.from, move.to, move.revision], [3, 0, 'rev-9']);
  await jam.time.advance(3100);
  // Moving to the end maps to the slot after the last matched row.
  await jam.jam.rpc('move_queue_entry', {entryId: jam.native(2), beforeEntryId: null});
  const toEnd = jam.app.sent().filter(m => m.action === 'move').at(-1);
  assert.deepEqual([toEnd.from, toEnd.to], [0, 3]);
});

test('a confirmed edit stays silent; a stale revision is explained', async () => {
  const jam = await bootJam();
  await jam.start();
  await jam.time.advance(1500);
  await jam.jam.rpc('remove_queue_entry', {entryId: jam.native(2)});
  await jam.push({track: track(1), queue: [track(3)], revision: 'r2'}, 10);
  await jam.time.advance(3500);
  assert.ok(!jam.toastKeys().includes('jam.notice.notApplied'));
  await jam.jam.rpc('remove_queue_entry', {entryId: jam.native(3)});
  const remove = jam.app.sent().filter(m => m.action === 'remove').at(-1);
  jam.app.emit({type: 'commandResult', action: 'remove', ok: false, detail: 'stale', requestId: remove.requestId});
  await jam.time.advance(50);
  assert.ok(jam.toastKeys().includes('jam.notice.stale'));
});

test('removing the current entry or an unknown one explains instead of sending', async () => {
  const jam = await bootJam();
  await jam.start();
  await jam.jam.rpc('remove_queue_entry', {entryId: jam.native(1)});
  assert.ok(jam.toastKeys().includes('jam.notice.removeCurrent'));
  await jam.jam.rpc('remove_queue_entry', {entryId: 'collection|nope'});
  assert.ok(jam.toastKeys().includes('jam.notice.notEditable'));
  assert.equal(jam.app.sent().filter(m => m.action === 'remove').length, 0);
});

test('enqueue_tracks resolves each song through the plugin, then adds (end) or inserts at 0 (next)', async () => {
  const jam = await bootJam();
  await jam.start();
  await jam.time.advance(1500);
  const items = [{videoId: 'v1', title: 'Hello', artists: 'Adele', album: '25', duration: null, entryId: 'e1'}];
  await jam.jam.rpc('enqueue_tracks', {items, position: 'end'});
  await jam.time.advance(10);
  const resolve = jam.app.sent().find(m => m.type === 'resolve');
  assert.deepEqual([resolve.title, resolve.artist, resolve.album, resolve.durationMs], ['Hello', 'Adele', '25', null]);
  jam.app.emit({type: 'resolved', requestId: resolve.requestId, uri: 'spotify:track:hello', title: 'Hello', artists: ['Adele'], durationMs: 295000});
  await jam.time.advance(10);
  const add = jam.app.sent().find(m => m.action === 'add');
  assert.equal(add.uri, 'spotify:track:hello');
  await jam.push({track: track(1), queue: [track(2), track(3), {...track('hello'), uri: 'spotify:track:hello'}], revision: 'r2'}, 10);
  await jam.time.advance(10);
  assert.ok(jam.toastKeys().includes('jam.notice.added'));

  await jam.jam.rpc('enqueue_tracks', {items: [{...items[0], title: 'Again', duration: 200}], position: 'next'});
  await jam.time.advance(10);
  const second = jam.app.sent().filter(m => m.type === 'resolve').at(-1);
  assert.equal(second.durationMs, 200000);
  jam.app.emit({type: 'resolved', requestId: second.requestId, uri: 'spotify:track:again', title: 'Again', artists: [], durationMs: null});
  await jam.time.advance(10);
  const insert = jam.app.sent().find(m => m.action === 'insert');
  assert.deepEqual([insert.uri, insert.index], ['spotify:track:again', 0]);
  assert.equal(jam.app.callsOf('enqueue_tracks').length, 0, 'never reaches the native queue directly');
});

test('enqueue without a confident Spotify equivalent shows a toast and sends nothing', async () => {
  const jam = await bootJam();
  await jam.start();
  await jam.jam.rpc('enqueue_tracks', {items: [{videoId: 'v', title: 'Obscure', artists: 'Nobody', duration: 100, entryId: 'e'}], position: 'end'});
  await jam.time.advance(10);
  const resolve = jam.app.sent().find(m => m.type === 'resolve');
  jam.app.emit({type: 'resolved', requestId: resolve.requestId, uri: null, title: null, artists: [], durationMs: null});
  await jam.time.advance(10);
  assert.deepEqual(jam.view.toasts.find(t => t.key === 'jam.notice.noSpotifyMatch').values, {title: 'Obscure'});
  assert.equal(jam.app.sent().filter(m => m.action === 'add').length, 0);
});

test('a song already matched from a Jam track resolves without asking the plugin', async () => {
  const jam = await bootJam();
  await jam.start();
  await jam.time.advance(1500);
  await jam.jam.rpc('enqueue_tracks', {items: [{videoId: 'yt-2', title: 'Title 2', artists: 'Artist 2', duration: 180, entryId: 'e'}], position: 'end'});
  await jam.time.advance(10);
  assert.equal(jam.app.sent().filter(m => m.type === 'resolve').length, 0);
  assert.equal(jam.app.sent().find(m => m.action === 'add').uri, 'spotify:track:2');
});

test('actions.addSong and moveQueue/removeQueue use indices of the plugin queue', async () => {
  const jam = await bootJam();
  await jam.start();
  await jam.time.advance(1500);
  void jam.jam.actions.moveQueue(1, 0);
  await jam.time.advance(10);
  const move = jam.app.sent().find(m => m.action === 'move');
  assert.deepEqual([move.from, move.to], [1, 0]);
  await jam.time.advance(3500);
  void jam.jam.actions.removeQueue(0);
  await jam.time.advance(10);
  assert.equal(jam.app.sent().find(m => m.action === 'remove').index, 0);
  await jam.time.advance(3500);
  const added = jam.jam.actions.addSong({title: 'Hello', artists: 'Adele'}, 1);
  await jam.time.advance(10);
  const resolve = jam.app.sent().find(m => m.type === 'resolve');
  jam.app.emit({type: 'resolved', requestId: resolve.requestId, uri: 'spotify:track:hello', title: 'Hello', artists: ['Adele'], durationMs: 1});
  await jam.time.advance(10);
  assert.deepEqual([jam.app.sent().find(m => m.action === 'insert').index], [1]);
  await jam.push({track: track(1), queue: [track(2), {...track('h'), uri: 'spotify:track:hello'}, track(3)], revision: 'r3'}, 10);
  assert.equal(await added, true);
});

test('play_song of the immediate next row becomes next; other rows are not available in a Jam', async () => {
  const jam = await bootJam({app: {search: search(['2'])}});
  await jam.start({state: {queue: [track(2), track(3), track(4)]}});
  await jam.time.advance(1500);
  // Native rows: yt-1 (current), yt-3, yt-4. Row yt-3 is the immediate next but skips the unmatched Jam track 2.
  const items = jam.app.player.items;
  await jam.jam.rpc('play_song', {videoId: 'yt-3', preserveQueue: true, queueCurrentIndex: 1, queueEntryId: items[1].entryId});
  assert.equal(jam.app.sent().filter(m => m.action === 'next').length, 2);
  await jam.jam.rpc('play_song', {videoId: 'yt-4', preserveQueue: true, queueCurrentIndex: 2, queueEntryId: items[2].entryId});
  assert.ok(jam.toastKeys().includes('jam.notice.notAvailable'));
  assert.equal(jam.app.sent().filter(m => m.action === 'next').length, 2);
  assert.equal(jam.view.pendingExit, null);
});

test('anything that would start other music is held: pendingExit, confirm leaves then performs, cancel drops', async () => {
  const cases = [
    ['play_song', {videoId: 'zzz', queueItems: [{videoId: 'zzz'}], queueCurrentIndex: 0}, 'jam.exit.playOther'],
    ['start_song_radio', {song: {videoId: 'zzz'}}, 'jam.exit.radio'],
    ['start_source_radio', {items: [], source: {kind: 'album'}, playlistId: 'p'}, 'jam.exit.source'],
    ['queue_recommendation_action', {entryId: 'r', placement: 'now', generation: 1}, 'jam.exit.recommendation']
  ];
  for (const [command, args, reasonKey] of cases) {
    const jam = await bootJam();
    await jam.start();
    await jam.time.advance(500);
    const before = jam.app.callsOf(command).length;
    const state = await jam.jam.rpc(command, args);
    assert.equal(typeof state.isPlaying, 'boolean');
    assert.deepEqual(jam.view.pendingExit, {reasonKey});
    assert.equal(jam.app.callsOf(command).length, before, 'not executed');
    assert.equal(jam.view.phase, 'active');
    jam.jam.actions.cancelExit();
    assert.equal(jam.view.pendingExit, null);
    await jam.jam.actions.confirmExit();
    assert.equal(jam.view.phase, 'active', 'a cancelled call is gone');
    assert.equal(jam.app.callsOf(command).length, before);

    await jam.jam.rpc(command, args);
    await jam.jam.actions.confirmExit();
    assert.equal(jam.view.phase, 'idle');
    assert.equal(jam.view.pendingExit, null);
    const order = jam.app.calls.map(call => call.command);
    assert.ok(order.lastIndexOf(command) > order.lastIndexOf('jam_leave'), `${command} runs after leaving`);
    assert.deepEqual(jam.app.callsOf(command).at(-1).args, args);
  }
});

test('the Jam itself bypasses the wrapper: its play_song never becomes a pendingExit', async () => {
  const jam = await bootJam();
  await jam.start();
  await jam.push({track: track(2), queue: []});
  assert.ok(jam.app.callsOf('play_song').length >= 2);
  assert.equal(jam.view.pendingExit, null);
  assert.equal(jam.app.sent().filter(m => m.action === 'next').length, 0);
});

test('shuffle and repeat are ignored with a toast', async () => {
  const jam = await bootJam();
  await jam.start();
  await jam.jam.rpc('set_shuffle', {enabled: true});
  await jam.jam.rpc('set_repeat', {enabled: true});
  assert.equal(jam.app.callsOf('set_shuffle').length, 0);
  assert.equal(jam.app.callsOf('set_repeat').length, 0);
  assert.ok(jam.toastKeys().includes('jam.notice.shuffleRepeat'));
});

test('unrelated commands pass through during a Jam', async () => {
  const jam = await bootJam();
  await jam.start();
  jam.app.on('set_playback_volume', () => 'ok');
  assert.equal(await jam.jam.rpc('set_playback_volume', {volume: 50}), 'ok');
  assert.equal(jam.app.callsOf('set_playback_volume').length, 1);
});

test('after the Jam ends the wrapper is raw again and a held call is dropped', async () => {
  const jam = await bootJam();
  await jam.start();
  await jam.jam.rpc('start_song_radio', {song: {videoId: 'a'}});
  assert.ok(jam.view.pendingExit);
  await jam.jam.actions.leave();
  assert.equal(jam.view.pendingExit, null);
  jam.app.on('start_song_radio', () => 'raw');
  await jam.jam.rpc('start_song_radio', {song: {videoId: 'a'}});
  assert.equal(jam.app.callsOf('start_song_radio').length, 1);
});
