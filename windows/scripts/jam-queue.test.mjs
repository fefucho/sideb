import assert from 'node:assert/strict';
import {test} from 'node:test';
import {loadJam} from './helpers/jam-modules.mjs';

const {JamQueueMapping, identities, editCommand, editIsValid, editIsSatisfied, uriOfEntryId, isJamEntryId} = await loadJam('queueMapping');
const {planMatches, backoffMs, PLANNER} = await loadJam('planner');

test('rows map to the Jam indices of the matched tracks only', () => {
  const map = new JamQueueMapping([true, false, true, true, false]);
  assert.equal(map.rowCount, 3);
  assert.deepEqual([0, 1, 2, 3].map(row => map.jamIndexForRow(row)), [0, 2, 3, null]);
  assert.equal(map.rowForJamIndex(3), 2);
  assert.equal(map.rowForJamIndex(1), null);
});

test('insertion lands before the Jam track of that row, or at the end', () => {
  const map = new JamQueueMapping([false, true, false, true, false]);
  assert.deepEqual([0, 1, 2, 9].map(row => map.insertionJamIndex(row)), [1, 3, 5, 5]);
  assert.equal(new JamQueueMapping([]).insertionJamIndex(0), 0);
});

test('moving a row takes the Jam slot of the row it displaces', () => {
  const map = new JamQueueMapping([true, false, true, false, true]);
  assert.deepEqual(map.move(0, 2), {from: 0, to: 4});
  assert.deepEqual(map.move(2, 1), {from: 4, to: 2});
  assert.equal(map.move(1, 1), null);
  assert.equal(map.move(0, 7), null);
});

test('moving before a track or to the end maps through unmatched tracks', () => {
  const map = new JamQueueMapping([true, false, true, true, false]);
  assert.deepEqual(map.moveBefore(0, 3), {from: 0, to: 2});   // forward: lands right before index 3
  assert.deepEqual(map.moveBefore(3, 0), {from: 3, to: 0});   // backward
  assert.deepEqual(map.moveBefore(0, null), {from: 0, to: 3}); // after the last matched row
  assert.equal(map.moveBefore(3, null), null);                // already last
  assert.equal(map.moveBefore(2, 3), null);                   // already right before it
});

test('entry ids and keys stay distinct for repeated tracks and count the current track', () => {
  const ids = identities('a', ['b', 'a', 'a']);
  assert.deepEqual(ids.current, {key: 'a#0', entryId: 'jam|a|0'});
  assert.deepEqual(ids.queue.map(item => item.entryId), ['jam|b|0', 'jam|a|1', 'jam|a|2']);
  assert.equal(new Set(ids.queue.map(item => item.key)).size, 3);
  assert.equal(identities(null, ['a']).current, null);
  assert.equal(uriOfEntryId('jam|spotify:track:1|2'), 'spotify:track:1');
  assert.equal(isJamEntryId('collection|x'), false);
});

test('edits are applied only when the next state shows them', () => {
  const old = ['a', 'b', 'c', 'd'];
  assert.ok(editIsSatisfied({action: 'move', from: 0, to: 2}, old, ['b', 'c', 'a', 'd']));
  assert.ok(!editIsSatisfied({action: 'move', from: 0, to: 2}, old, old));
  assert.ok(editIsSatisfied({action: 'remove', index: 1}, old, ['a', 'c', 'd']));
  assert.ok(!editIsSatisfied({action: 'remove', index: 1}, old, old));
  assert.ok(editIsSatisfied({action: 'insert', uri: 'x', index: 1}, old, ['a', 'x', 'b', 'c', 'd']));
  assert.ok(!editIsSatisfied({action: 'insert', uri: 'x', index: 1}, old, ['a', 'b', 'x', 'c', 'd']));
  assert.ok(editIsSatisfied({action: 'insert', uri: 'x', index: 4}, old, [...old, 'x']));
  assert.ok(editIsSatisfied({action: 'add', uri: 'x'}, old, ['a', 'x', 'b', 'c', 'd']));
  assert.ok(!editIsSatisfied({action: 'add', uri: 'x'}, old, old));
});

test('edits outside the queue are not sent; commands carry revision and request id', () => {
  const queue = ['a', 'b'];
  assert.ok(!editIsValid({action: 'remove', index: 2}, queue));
  assert.ok(!editIsValid({action: 'move', from: 0, to: 2}, queue));
  assert.ok(editIsValid({action: 'insert', uri: 'x', index: 2}, queue));
  assert.deepEqual(editCommand({action: 'move', from: 0, to: 1}, 'r7', 'q1'), {type: 'command', action: 'move', from: 0, to: 1, requestId: 'q1', revision: 'r7'});
  const add = editCommand({action: 'add', uri: 'spotify:track:1'}, null, 'q2');
  assert.equal(add.uri, 'spotify:track:1');
  assert.ok(!('revision' in add));
});

// MARK: planner

const now = 1_000_000;
const uris = n => Array.from({length: n}, (_, i) => `u${i}`);
const plan = (queue, o = {}) => planMatches({queue, settled: new Set(o.settled ?? []), inFlight: new Set(o.inFlight ?? []),
  attempts: new Map(Object.entries(o.attempts ?? {})), retryAt: new Map(Object.entries(o.retryAt ?? {})), lastBackgroundStart: o.last ?? -Infinity, now});

test('planner: nearest first, bounded by the concurrency limit', () => {
  assert.deepEqual(plan(uris(200)).start, ['u0', 'u1', 'u2']);
  assert.deepEqual(plan(uris(200), {inFlight: ['u0', 'u1']}).start, ['u2']);
  assert.deepEqual(plan(uris(200), {inFlight: ['u0', 'u1', 'u2']}).start, []);
});

test('planner: settled results are skipped, so a reordered queue redoes nothing', () => {
  const queue = ['c', 'a', 'b', 'd'];
  assert.deepEqual(plan(queue, {settled: ['a', 'b', 'c']}).start, ['d']);
  assert.deepEqual(plan([...queue].reverse(), {settled: ['a', 'b', 'c'], inFlight: ['d']}).start, []);
  assert.deepEqual(plan(['a', 'a', 'b']).start, ['a', 'b']);
});

test('planner: beyond the eager window one lookup starts at the background pace', () => {
  const queue = uris(40);
  const settled = queue.slice(0, PLANNER.eagerCount);
  const first = plan(queue, {settled});
  assert.deepEqual(first.start, ['u15']);
  assert.equal(first.startsBackground, true);
  const tooSoon = plan(queue, {settled, last: now - 500});
  assert.deepEqual(tooSoon.start, []);
  assert.equal(tooSoon.wakeAfterMs, 1000);
});

test('planner: a failed lookup waits for its backoff, then retries; attempts are bounded', () => {
  const queue = ['a', 'b'];
  const waiting = plan(queue, {retryAt: {a: now + 5000}});
  assert.deepEqual(waiting.start, ['b']);
  assert.equal(waiting.wakeAfterMs, 5000);
  assert.deepEqual(plan(queue, {retryAt: {a: now - 1}}).start, ['a', 'b']);
  assert.deepEqual(plan(queue, {attempts: {a: PLANNER.maxAttempts}}).start, ['b']);
  assert.deepEqual([1, 2, 3, 4, 5, 6].map(backoffMs), [2000, 5000, 15000, 30000, 60000, 60000]);
  assert.equal(PLANNER.maxAttempts, 6);
});
