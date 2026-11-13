import assert from 'node:assert/strict';
import {test} from 'node:test';
import {loadJam} from './helpers/jam-modules.mjs';

const {JamSyncEngine} = await loadJam('syncEngine');

/** Simulated player: position advances at `rate`; the Jam target advances at 1x. */
class Sim {
  engine = new JamSyncEngine();
  rate = 1; rateWorks = true; seekLanding = -0.12; noise = 0; now = 1000;
  adjustingTime = 0; maxAdjustingTime = 0; seeks = 0; bursts = 0; reopened = false; tickIndex = 0;
  constructor(drift) { this.drift = drift; }
  step(advancing = true) {
    this.tickIndex += 1;
    const jitter = this.noise === 0 ? 0 : this.noise * (this.tickIndex % 2 === 0 ? 1 : -1);
    const wasAdjusting = this.engine.isAdjusting;
    const action = this.engine.tick(this.drift + jitter, this.now, advancing);
    if (this.engine.didReopen) this.reopened = true;
    if (action.kind === 'seek') { this.seeks += 1; this.drift = action.compensation + this.seekLanding; }
    else if (action.kind === 'setRate') { if (action.rate !== 1) this.bursts += 1; this.rate = action.rate; }
    else if (action.kind === 'lock') this.rate = 1;
    if (advancing) {
      if (this.rateWorks) this.drift += (this.rate - 1) * 0.1;
      if (wasAdjusting || this.engine.isAdjusting) this.adjustingTime += 0.1;
      if (!this.engine.isAdjusting) { this.maxAdjustingTime = Math.max(this.maxAdjustingTime, this.adjustingTime); this.adjustingTime = 0; }
    }
    this.now += 0.1;
    return action;
  }
}

test('converges with a player where rate works', () => {
  for (const start of [0.12, -0.12, 0.2, -0.3, 0.9]) {
    const sim = new Sim(start);
    sim.engine.begin();
    for (let i = 0; i < 120; i += 1) sim.step();
    assert.equal(sim.engine.isAdjusting, false);
    assert.ok(Math.abs(sim.drift) <= 0.05, `start ${start} ended at ${sim.drift}`);
    assert.equal(sim.rate, 1);
    assert.ok(sim.engine.lastSummary);
  }
});

test('gives up and locks when rate has no effect', () => {
  const sim = new Sim(0.15);
  sim.rateWorks = false;
  sim.engine.begin();
  let ticks = 0;
  while (sim.engine.isAdjusting && ticks < 200) { sim.step(); ticks += 1; }
  assert.equal(sim.engine.isAdjusting, false);
  assert.ok(ticks * 0.1 <= 8);
  assert.equal(sim.engine.rateIneffective, true);
  assert.ok(['accepted', 'finalSeek'].includes(sim.engine.lastSummary.reason));
  assert.ok(Math.abs(sim.engine.lastSummary.residualMs) <= 200);
  assert.equal(sim.rate, 1);
  for (let i = 0; i < 100; i += 1) assert.equal(sim.step().kind, 'none');
});

test('a window never exceeds 8 s for a range of initial drifts, even if nothing works', () => {
  for (let start = -2; start <= 2.0001; start += 0.05) {
    for (const worksRate of [true, false]) {
      const sim = new Sim(start);
      sim.rateWorks = worksRate;
      sim.seekLanding = 0.4;
      sim.engine.begin();
      for (let i = 0; i < 150; i += 1) sim.step();
      assert.ok(sim.maxAdjustingTime <= 8 + 1e-6, `start ${start} rateWorks ${worksRate}: ${sim.maxAdjustingTime}`);
      assert.equal(sim.engine.isAdjusting, false);
    }
  }
});

test('noise of 30 ms while locked never reopens a window', () => {
  const sim = new Sim(0.01);
  sim.engine.begin();
  for (let i = 0; i < 30; i += 1) sim.step();
  assert.equal(sim.engine.isAdjusting, false);
  sim.noise = 0.03; sim.drift = 0.02;
  for (let i = 0; i < 2000; i += 1) sim.step();
  assert.equal(sim.reopened, false);
  assert.equal(sim.engine.isAdjusting, false);
});

test('a sustained large drift reopens a window, at most once every 20 s', () => {
  const sim = new Sim(0);
  sim.engine.begin();
  for (let i = 0; i < 30; i += 1) sim.step();
  sim.rateWorks = false; sim.drift = 0.6;
  let reopens = 0;
  for (let i = 0; i < 400; i += 1) { sim.step(); if (sim.engine.didReopen) reopens += 1; }
  assert.ok(reopens >= 1);
  assert.ok(reopens <= 2);
});

test('buffering time is not counted and produces no actions', () => {
  const sim = new Sim(0.15);
  sim.engine.begin();
  sim.step();
  for (let i = 0; i < 600; i += 1) assert.equal(sim.step(false).kind, 'none');
  assert.equal(sim.engine.isAdjusting, true);
  for (let i = 0; i < 120; i += 1) sim.step();
  assert.equal(sim.engine.isAdjusting, false);
  assert.ok(sim.engine.lastSummary.duration < 8);
});

test('seek landing bias is learned and kept across windows', () => {
  const sim = new Sim(1.0);
  sim.seekLanding = -0.2;
  sim.engine.begin();
  for (let i = 0; i < 80; i += 1) sim.step();
  assert.ok(Math.abs(sim.engine.seekBias + 0.2) < 0.05);
  const learned = sim.engine.seekBias;
  sim.drift = 1.0;
  sim.engine.begin();
  let first = {kind: 'none'};
  for (let i = 0; i < 10; i += 1) { const action = sim.step(); if (action.kind === 'seek') { first = action; break; } }
  assert.equal(first.kind, 'seek');
  assert.ok(Math.abs(first.compensation + learned) < 1e-9);
});

test('small drifts use a fixed 0.95x/1.05x burst, big ones a seek', () => {
  const slow = new Sim(0.1);
  slow.engine.begin();
  const actions = [];
  for (let i = 0; i < 6; i += 1) actions.push(slow.step());
  assert.deepEqual(actions.find(a => a.kind === 'setRate'), {kind: 'setRate', rate: 0.95});
  const behind = new Sim(-0.1);
  behind.engine.begin();
  const rates = [];
  for (let i = 0; i < 6; i += 1) rates.push(behind.step());
  assert.equal(rates.find(a => a.kind === 'setRate').rate, 1.05);
  const far = new Sim(1.5);
  far.engine.begin();
  const first = [];
  for (let i = 0; i < 6; i += 1) first.push(far.step());
  assert.equal(first.find(a => a.kind !== 'none').kind, 'seek');
});
