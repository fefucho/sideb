import { readdir, readFile, writeFile } from 'node:fs/promises';
const source = new URL('../../apple/Localization/fragments/', import.meta.url);
const output = new URL('../src/lib/i18n/catalog.json', import.meta.url);
const entries = {};
const signature = text => [...text.matchAll(/%(?:\d+\$)?(@|lld|%)/g)].filter(x => x[1] !== '%').map(x => x[1]).join(',');
for (const file of (await readdir(source)).filter(x => x.endsWith('.json')).sort()) {
  const fragment = JSON.parse(await readFile(new URL(file, source), 'utf8'));
  for (const [key, value] of Object.entries(fragment)) {
    if (key in entries) throw new Error(`Duplicate key ${key}`);
    if (!value.es || !value.en) throw new Error(`Missing language ${key}`);
    const forms = typeof value.es === 'string' ? [''] : ['one', 'other'];
    for (const form of forms) {
      const es = form ? value.es[form] : value.es;
      const en = form ? value.en[form] : value.en;
      if (typeof es !== 'string' || typeof en !== 'string' || signature(es) !== signature(en)) throw new Error(`Invalid arguments/plurals ${key}`);
    }
    entries[key] = value;
  }
}
const generated = JSON.stringify(Object.fromEntries(Object.entries(entries).sort(([a], [b]) => a.localeCompare(b))), null, 2) + '\n';
const platform = JSON.parse(await readFile(new URL('../src/lib/i18n/windows.json', import.meta.url), 'utf8'));
for (const [key, value] of Object.entries(platform)) {
  if (!key.startsWith('windows.') || key in entries || typeof value.es !== 'string' || typeof value.en !== 'string' || signature(value.es) !== signature(value.en)) throw new Error(`Invalid Windows entry ${key}`);
}
async function verifyReferences(directory) {
  for (const entry of await readdir(directory, { withFileTypes: true })) {
    const url = new URL(entry.name + (entry.isDirectory() ? '/' : ''), directory);
    if (entry.isDirectory()) await verifyReferences(url);
    else if (/\.(?:ts|svelte)$/.test(entry.name)) {
      const source = await readFile(url, 'utf8');
      for (const match of source.matchAll(/(?:\$t|\b(?:text|message|count))\(\s*(['"])([^'"]+)\1\s*(?=[,)])/g)) {
        if (!(match[2] in entries) && !(match[2] in platform)) throw new Error(`Unknown localization key ${match[2]} in ${entry.name}`);
      }
    }
  }
}
await verifyReferences(new URL('../src/', import.meta.url));
if (process.argv.includes('--check')) {
  if (await readFile(output, 'utf8') !== generated) throw new Error('Windows translations are stale; run node windows/scripts/sync-localizations.mjs');
} else await writeFile(output, generated);
console.log(`${Object.keys(entries).length} shared ES/EN keys verified`);
