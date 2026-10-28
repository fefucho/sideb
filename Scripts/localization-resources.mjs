// Portable serialization of the deliberately small editorial fragment schema.
// macOS continues to use xcstringstool as the native compiler.
const xml = value => value.replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;');
const header = '<?xml version="1.0" encoding="UTF-8"?>\n<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">\n<plist version="1.0">\n<dict>\n';

export function nativeLocalizationResources(entries, language) {
    let strings = header;
    let plurals = header;
    for (const [key, entry] of Object.entries(entries).sort()) {
        const translation = entry.localizations[language];
        if (translation.stringUnit) {
            strings += `\t<key>${xml(key)}</key>\n\t<string>${xml(translation.stringUnit.value)}</string>\n`;
        } else {
            const forms = translation.variations?.plural;
            if (!forms?.one?.stringUnit || !forms?.other?.stringUnit || Object.keys(forms).length !== 2) {
                throw new Error(`Plural no soportado: ${key}/${language}`);
            }
            plurals += `\t<key>${xml(key)}</key>\n\t<dict>\n\t\t<key>NSStringLocalizedFormatKey</key>\n\t\t<string>%#@value@</string>\n\t\t<key>value</key>\n\t\t<dict>\n\t\t\t<key>NSStringFormatSpecTypeKey</key>\n\t\t\t<string>NSStringPluralRuleType</string>\n\t\t\t<key>NSStringFormatValueTypeKey</key>\n\t\t\t<string>lld</string>\n\t\t\t<key>one</key>\n\t\t\t<string>${xml(forms.one.stringUnit.value)}</string>\n\t\t\t<key>other</key>\n\t\t\t<string>${xml(forms.other.stringUnit.value)}</string>\n\t\t</dict>\n\t</dict>\n`;
        }
    }
    return { 'Localizable.strings': strings + '</dict>\n</plist>\n', 'Localizable.stringsdict': plurals + '</dict>\n</plist>\n' };
}
