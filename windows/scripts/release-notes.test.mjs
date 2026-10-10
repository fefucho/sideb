import { readFile } from 'node:fs/promises';
import assert from 'node:assert/strict';
import { test } from 'node:test';
import ts from 'typescript';
const source = await readFile(new URL('../src/lib/updater/markdown.ts', import.meta.url), 'utf8');
const output = ts.transpileModule(source, { compilerOptions: { target: ts.ScriptTarget.ES2022, module: ts.ModuleKind.ESNext } }).outputText;
const { markdownBlocks, inlineMarkdown } = await import(`data:text/javascript;base64,${Buffer.from(output).toString('base64')}`);
test('release Markdown supports headings, paragraphs, lists, quotes and fenced code without changing external content', () => {
  const source = '# Notes\n\n**Fixed** original text\n\n- first\n- second\n\n1. one\n2. two\n\n> quote\n\n```js\nconst x = 1;\n```';
  const blocks = markdownBlocks(source);
  assert.deepEqual(blocks.map(x => x.kind), ['heading', 'paragraph', 'list', 'list', 'quote', 'code']);
  assert.deepEqual(blocks[2].items, ['first', 'second']); assert.equal(blocks[3].ordered, true);
  assert.equal(blocks[5].text, 'const x = 1;');
});
test('inline Markdown accepts ordinary external links and treats script/HTML as literal text', () => {
  const tokens = inlineMarkdown('**strong** *emphasis* `code` [Genius](https://genius.com/a) <script>alert(1)</script> [bad](javascript:evil)');
  assert.ok(tokens.some(x => x.kind === 'strong' && x.text === 'strong'));
  assert.equal(tokens.find(x => x.kind === 'link').url, 'https://genius.com/a');
  assert.equal(tokens.filter(x => x.kind === 'link').length, 1);
  assert.ok(tokens.some(x => x.kind === 'text' && x.text.includes('<script>')));
});
