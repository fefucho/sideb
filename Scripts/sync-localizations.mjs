#!/usr/bin/env node
// Fragments are the editorial source; catalog and native SwiftPM resources are derived.
import { spawnSync } from 'node:child_process';
import { existsSync, readFileSync, readdirSync, mkdirSync, mkdtempSync, rmSync, writeFileSync, copyFileSync } from 'node:fs';
import { dirname, join, relative } from 'node:path';
import { tmpdir } from 'node:os';
import { fileURLToPath } from 'node:url';

const root = dirname(dirname(fileURLToPath(import.meta.url)));
const check = process.argv.includes('--check');
if (process.argv.slice(2).some(arg => arg !== '--check')) throw new Error('Uso: node Scripts/sync-localizations.mjs [--check]');
const source = join(root, 'apple', 'Localization');
const resources = join(root, 'apple', 'Sources', 'SideB', 'Resources');
const entries = {};
const signature = value => [...value.matchAll(/%(?:\d+\$)?(?:@|lld|ld|d|f)/g)].map(match => match[0].replace(/^%\d+\$/, '%')).sort().join(',');
for (const file of readdirSync(join(source, 'fragments')).filter(file => file.endsWith('.json')).sort()) {
    const fragment = JSON.parse(readFileSync(join(source, 'fragments', file), 'utf8'));
    for (const [key, translations] of Object.entries(fragment)) {
        if (entries[key]) throw new Error(`Clave duplicada: ${key} (${file})`);
        if (!translations.es || !translations.en) throw new Error(`Falta idioma: ${key}`);
        const plural = typeof translations.es === 'object';
        if (plural !== (typeof translations.en === 'object')) throw new Error(`Plural incompatible: ${key}`);
        if (plural) {
            for (const lang of ['es', 'en']) for (const form of ['one', 'other']) {
                if (typeof translations[lang][form] !== 'string' || signature(translations[lang][form]) !== '%lld')
                    throw new Error(`Plural inválido: ${key}/${lang}/${form}`);
            }
        } else {
            if (typeof translations.es !== 'string' || typeof translations.en !== 'string'
                || signature(translations.es) !== signature(translations.en)) throw new Error(`Argumentos incompatibles: ${key}`);
            // All ordinary parameters are Strings; numerical plurals use the dedicated helper.
            if (signature(translations.es).split(',').some(part => part && part !== '%@')) throw new Error(`Usar %@ para argumentos: ${key}`);
        }
        const localizations = {};
        for (const lang of ['es', 'en']) {
            const unit = value => ({ stringUnit: { state: 'translated', value } });
            localizations[lang] = plural
                ? { variations: { plural: { one: unit(translations[lang].one), other: unit(translations[lang].other) } } }
                : unit(translations[lang]);
        }
        entries[key] = { extractionState: 'manual', localizations };
    }
}
const walk = folder => readdirSync(folder, { withFileTypes: true }).flatMap(entry => entry.isDirectory()
    ? walk(join(folder, entry.name)) : entry.name.endsWith('.swift') ? [join(folder, entry.name)] : []);
for (const file of walk(join(root, 'apple', 'Sources', 'SideB'))) {
    const swift = readFileSync(file, 'utf8');
    for (const match of swift.matchAll(/(?:L10n\.text\(\s*|AppMessage\(\s*key:\s*)"([^"\\]+)"/g)) {
        if (!entries[match[1]]) throw new Error(`Clave sin traducción: ${match[1]} en ${relative(root, file)}`);
    }
}
const catalog = JSON.stringify({ sourceLanguage: 'es', strings: Object.fromEntries(Object.entries(entries).sort()), version: '1.0' }, null, 2) + '\n';
const temporary = mkdtempSync(join(tmpdir(), 'sideb-localizations-'));
try {
    const catalogPath = join(temporary, 'Localizable.xcstrings');
    writeFileSync(catalogPath, catalog);
    const result = spawnSync('xcrun', ['xcstringstool', 'compile', catalogPath, '--output-directory', temporary, '--serialization-format', 'text'], { encoding: 'utf8' });
    if (result.status !== 0) throw new Error(result.stderr || result.stdout || 'Falló xcstringstool');
    const outputs = [[catalogPath, join(source, 'Localizable.xcstrings')]];
    for (const lang of ['es', 'en']) {
        const folder = join(temporary, `${lang}.lproj`);
        if (!existsSync(folder)) throw new Error(`No se generó ${lang}.lproj`);
        for (const file of readdirSync(folder).sort()) outputs.push([join(folder, file), join(resources, `${lang}.lproj`, file)]);
    }
    for (const [from, to] of outputs) {
        if (check) {
            if (!existsSync(to) || !readFileSync(from).equals(readFileSync(to))) throw new Error(`Recurso desactualizado: ${relative(root, to)}; ejecutar sin --check`);
        } else {
            mkdirSync(dirname(to), { recursive: true });
            copyFileSync(from, to);
        }
    }
    console.log(`${check ? 'Verificado' : 'Generado'}: ${Object.keys(entries).length} claves es/en, catálogo y recursos SwiftPM.`);
} finally { rmSync(temporary, { recursive: true, force: true }); }
