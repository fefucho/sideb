// Loads src/lib/jam/*.ts for node tests: transpiles each module once into .cache and rewrites its
// relative imports, so the real modules run unchanged without a bundler.
import {readFile, writeFile, mkdir} from 'node:fs/promises';
import {fileURLToPath, pathToFileURL} from 'node:url';
import {createHash} from 'node:crypto';
import path from 'node:path';
import ts from 'typescript';

const root = fileURLToPath(new URL('../../', import.meta.url));
const cache = path.join(root, '.cache', 'jam-tests');
const modules = new Map();

async function moduleFor(filename) {
  if (modules.has(filename)) return modules.get(filename);
  await mkdir(cache, {recursive: true});
  const destination = path.join(cache, createHash('sha256').update(filename).digest('hex') + '.mjs');
  const url = pathToFileURL(destination).href;
  modules.set(filename, url);
  let code = ts.transpileModule(await readFile(filename, 'utf8'), {compilerOptions: {target: ts.ScriptTarget.ES2022, module: ts.ModuleKind.ESNext}}).outputText;
  for (const match of [...code.matchAll(/(?:from\s+|import\s*\()(['"])(\.{1,2}\/[^'"]+)\1/g)]) {
    let target = path.resolve(path.dirname(filename), match[2]);
    if (!path.extname(target)) {
      try { await readFile(target + '.ts'); target += '.ts'; } catch { target = path.join(target, 'index.ts'); }
    }
    code = code.replaceAll(match[0], match[0].replace(match[2], await moduleFor(target)));
  }
  await writeFile(destination, code);
  return url;
}

/** Imports `src/lib/jam/<name>.ts` (default `index`). */
export async function loadJam(name = 'index') {
  return import(await moduleFor(path.join(root, 'src/lib/jam', `${name}.ts`)));
}
