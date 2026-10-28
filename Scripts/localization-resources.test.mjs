import assert from 'node:assert/strict';
import { test } from 'node:test';
import { nativeLocalizationResources } from './localization-resources.mjs';

test('native resources preserve Unicode, arguments and XML-sensitive catalog text', () => {
    const unit = value => ({ stringUnit: { value } });
    const resources = nativeLocalizationResources({
        'z.name': { localizations: { es: unit('Elegí %@: R&B <álbum>\n"Edición"') } },
        'a.name': { localizations: { es: unit('Explícito') } },
    }, 'es');
    assert.ok(resources['Localizable.strings'].includes('<string>Elegí %@: R&amp;B &lt;álbum&gt;\n"Edición"</string>'));
    assert.ok(resources['Localizable.strings'].indexOf('a.name') < resources['Localizable.strings'].indexOf('z.name'));
    assert.ok(!resources['Localizable.stringsdict'].includes('z.name'));
});

test('quantity resources keep native plural indirection separate from ordinary strings', () => {
    const resources = nativeLocalizationResources({
        count: { localizations: { en: { variations: { plural: {
            one: { stringUnit: { value: '%lld song' } }, other: { stringUnit: { value: '%lld songs' } },
        } } } } },
    }, 'en');
    const dictionary = resources['Localizable.stringsdict'];
    assert.ok(dictionary.includes('<key>NSStringLocalizedFormatKey</key>\n\t\t<string>%#@value@</string>'));
    assert.ok(dictionary.includes('<key>NSStringFormatValueTypeKey</key>\n\t\t\t<string>lld</string>'));
    assert.ok(dictionary.includes('<key>one</key>\n\t\t\t<string>%lld song</string>'));
    assert.ok(dictionary.includes('<key>other</key>\n\t\t\t<string>%lld songs</string>'));
    assert.ok(!resources['Localizable.strings'].includes('<key>count</key>'));
});

test('unsupported plural schemas fail instead of silently discarding a form', () => {
    assert.throws(() => nativeLocalizationResources({ count: { localizations: { es: { variations: {
        plural: { one: { stringUnit: { value: '%lld' } } },
    } } } } }, 'es'), /Plural no soportado/);
});
