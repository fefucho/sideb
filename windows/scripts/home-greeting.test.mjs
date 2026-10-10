import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { test } from 'node:test';
import ts from 'typescript';

const source = await readFile(new URL('../src/lib/home/greeting.ts', import.meta.url), 'utf8');
const compiled = ts.transpileModule(source, { compilerOptions: { target: ts.ScriptTarget.ES2022, module: ts.ModuleKind.ESNext } }).outputText;
const { homeGreetingKey } = await import(`data:text/javascript;base64,${Buffer.from(compiled).toString('base64')}`);

test('local greetings change at 06:00, 12:00 and 20:00, including midnight', () => {
  for (const [hour, minute, expected] of [[0,0,'evening'],[5,59,'evening'],[6,0,'morning'],[11,59,'morning'],[12,0,'afternoon'],[19,59,'afternoon'],[20,0,'evening'],[23,59,'evening']]) {
    assert.equal(homeGreetingKey(new Date(2026,9,10,hour,minute)), `app.home.${expected}`);
  }
});

test('the same instant uses the system timezone, and picks up timezone changes', () => {
  const previous = process.env.TZ;
  try {
    const instant = new Date('2026-10-10T14:30:00Z');
    process.env.TZ = 'America/Montevideo';
    assert.equal(homeGreetingKey(instant), 'app.home.morning');
    process.env.TZ = 'Europe/Madrid';
    assert.equal(homeGreetingKey(instant), 'app.home.afternoon');
    process.env.TZ = 'Asia/Tokyo';
    assert.equal(homeGreetingKey(instant), 'app.home.evening');
  } finally {
    if (previous === undefined) delete process.env.TZ;
    else process.env.TZ = previous;
  }
});
