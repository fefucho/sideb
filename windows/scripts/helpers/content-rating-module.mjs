import { readFileSync } from 'node:fs';
import ts from 'typescript';
const source = readFileSync(new URL('../../src/lib/contentRating.ts', import.meta.url), 'utf8');
const code = ts.transpileModule(source, { compilerOptions: { target: ts.ScriptTarget.ES2022, module: ts.ModuleKind.ESNext } }).outputText;
const url = `data:text/javascript;base64,${Buffer.from(code).toString('base64')}`;
/** Preserve the existing isolated controller harnesses while loading the real shared metadata policy. */
export const resolveContentRatingImport = code => code.replace(/(['"])(?:\.\.?\/)+contentRating\1/g, JSON.stringify(url));
