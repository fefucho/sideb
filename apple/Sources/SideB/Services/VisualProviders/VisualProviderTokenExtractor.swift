import Foundation

enum VisualProviderTokenExtractor {
    static func scriptSource(handlerName: String) -> String {
        """
        (function() {
            function notify(token) {
                if (!token || typeof token !== 'string') return;
                token = token.trim();
                if (token.startsWith('Bearer ')) token = token.slice(7).trim();
                if (token.length > 20 && window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.\(handlerName)) {
                    window.webkit.messageHandlers.\(handlerName).postMessage(token);
                }
            }

            function scanDOM() {
                try {
                    const el = document.getElementById('session');
                    if (el && el.textContent) {
                        const data = JSON.parse(el.textContent);
                        if (data && data.accessToken && data.isAnonymous !== true) notify(data.accessToken);
                    }
                } catch (e) {}
            }

            if (document.readyState === 'loading') {
                document.addEventListener('DOMContentLoaded', scanDOM);
            } else {
                scanDOM();
            }

            const origFetch = window.fetch;
            window.fetch = async function(...args) {
                try {
                    const input = args[0];
                    const init = args[1];

                    if (init && init.headers) {
                        let h = init.headers;
                        let auth = null;
                        if (typeof h.get === 'function') {
                            auth = h.get('Authorization') || h.get('authorization');
                        } else if (Array.isArray(h)) {
                            for (let i = 0; i < h.length; i++) {
                                if (h[i] && typeof h[i][0] === 'string' && h[i][0].toLowerCase() === 'authorization') {
                                    auth = h[i][1];
                                    break;
                                }
                            }
                        } else if (typeof h === 'object') {
                            auth = h['Authorization'] || h['authorization'];
                        }
                        if (auth) notify(auth);
                    }

                    if (input && typeof input === 'object' && input.headers && typeof input.headers.get === 'function') {
                        const auth = input.headers.get('Authorization') || input.headers.get('authorization');
                        if (auth) notify(auth);
                    }
                } catch (e) {}

                const res = await origFetch.apply(this, args);

                try {
                    const url = (args[0] && typeof args[0] === 'string') ? args[0] : (args[0] && args[0].url) ? args[0].url : '';
                    if (url.includes('token') || url.includes('session') || url.includes('auth')) {
                        res.clone().json().then(data => {
                            if (data && typeof data === 'object' && data.isAnonymous !== true) {
                                const token = data.accessToken || data.access_token || data.token;
                                if (token) notify(token);
                            }
                        }).catch(() => {});
                    }
                } catch (e) {}

                return res;
            };

            try {
                const origSetHeader = XMLHttpRequest.prototype.setRequestHeader;
                XMLHttpRequest.prototype.setRequestHeader = function(header, value) {
                    try {
                        if (header && typeof header === 'string' && header.toLowerCase() === 'authorization') {
                            notify(value);
                        }
                    } catch (e) {}
                    return origSetHeader.apply(this, arguments);
                };
            } catch (e) {}
        })();
        """
    }

    /// For a page that is itself the token endpoint: its body is the JSON document.
    static let documentBodyScript = """
        try {
            const data = JSON.parse(document.body.innerText);
            if (data && data.isAnonymous !== true) {
                return data.accessToken || data.access_token || data.token || null;
            }
        } catch (e) {}
        return null;
        """

    static func pageExtractionScript(tokenUrl: String, handlerName: String) -> String {
        """
        try {
            const el = document.getElementById('session');
            if (el && el.textContent) {
                const data = JSON.parse(el.textContent);
                if (data && data.accessToken && data.isAnonymous !== true) {
                    if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.\(handlerName)) {
                        window.webkit.messageHandlers.\(handlerName).postMessage(data.accessToken);
                    }
                    return data.accessToken;
                }
            }
        } catch (e) {}
        try {
            const res = await fetch(tokenUrl, { credentials: 'include', headers: { 'Accept': 'application/json' } });
            if (res.ok) {
                const data = await res.json();
                const token = data.isAnonymous === true ? null : (data.accessToken || data.access_token || data.token);
                if (token) {
                    if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.\(handlerName)) {
                        window.webkit.messageHandlers.\(handlerName).postMessage(token);
                    }
                    return token;
                }
            }
        } catch (e) {}
        return null;
        """
    }
}
