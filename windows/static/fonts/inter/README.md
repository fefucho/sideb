# Inter 4.1

Unmodified variable WOFF2 fonts from the official release:
[Inter-4.1.zip](https://github.com/rsms/inter/releases/download/v4.1/Inter-4.1.zip).

Copyright (c) 2016 The Inter Project Authors. Distributed under the
[SIL Open Font License 1.1](LICENSE.txt), included with the app assets.

| Original archive path | Local file | SHA-256 |
|---|---|---|
| `web/InterVariable.woff2` | `InterVariable.woff2` | `693b77d4f32ee9b8bfc995589b5fad5e99adf2832738661f5402f9978429a8e3` |
| `web/InterVariable-Italic.woff2` | `InterVariable-Italic.woff2` | `e564f652916db6c139570fefb9524a77c4d48f30c92928de9db19b6b5c7a262a` |
| `LICENSE.txt` | `LICENSE.txt` | `262481e844521b326f5ecd053e59b98c8b2da78c8ee1bdbb6e8174305e54935a` |

Both faces provide weights 100–900. `src/lib/styles/fonts.css` loads these
files locally; the app does not download fonts from a CDN at runtime.
