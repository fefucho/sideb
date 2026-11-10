// Injected at document start, main frame only, into the provider's own (throw-away or login) web
// view. It never sends anything anywhere: it only remembers the Bearer tokens the page itself
// uses, in a non-enumerable page-world slot that the host polls with `eval_with_callback`.
// Anonymous sessions (`isAnonymous: true`) are ignored.
(function () {
  if (window.__sidebVp) return;
  var slot = { tokens: [], pulling: false };
  try {
    Object.defineProperty(window, '__sidebVp', { value: slot, enumerable: false });
  } catch (e) {
    return;
  }

  function remember(token) {
    if (!token || typeof token !== 'string') return;
    token = token.trim();
    if (token.slice(0, 7).toLowerCase() === 'bearer ') token = token.slice(7).trim();
    if (token.length <= 20) return;
    var at = slot.tokens.indexOf(token);
    if (at >= 0) slot.tokens.splice(at, 1);
    slot.tokens.push(token);
    if (slot.tokens.length > 8) slot.tokens.shift();
  }

  function fromDocument() {
    try {
      var el = document.getElementById('session');
      if (el && el.textContent) {
        var data = JSON.parse(el.textContent);
        if (data && data.accessToken && data.isAnonymous !== true) remember(data.accessToken);
      }
    } catch (e) {}
  }
  slot.scan = fromDocument;

  // Ask the token endpoint with the signed-in session (fire and forget; the host polls the slot).
  slot.pull = function (tokenUrl) {
    fromDocument();
    if (slot.pulling) return;
    slot.pulling = true;
    try {
      fetch(tokenUrl, { credentials: 'include', headers: { Accept: 'application/json' } })
        .then(function (res) { return res.ok ? res.json() : null; })
        .then(function (data) {
          if (data && data.isAnonymous !== true) remember(data.accessToken || data.access_token || data.token);
        })
        .catch(function () {})
        .then(function () { slot.pulling = false; });
    } catch (e) {
      slot.pulling = false;
    }
  };

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', fromDocument);
  } else {
    fromDocument();
  }

  var originalFetch = window.fetch;
  if (typeof originalFetch === 'function') {
    window.fetch = async function () {
      var args = arguments;
      try {
        var input = args[0];
        var init = args[1];
        if (init && init.headers) {
          var h = init.headers;
          var auth = null;
          if (typeof h.get === 'function') {
            auth = h.get('Authorization') || h.get('authorization');
          } else if (Array.isArray(h)) {
            for (var i = 0; i < h.length; i++) {
              if (h[i] && typeof h[i][0] === 'string' && h[i][0].toLowerCase() === 'authorization') {
                auth = h[i][1];
                break;
              }
            }
          } else if (typeof h === 'object') {
            auth = h['Authorization'] || h['authorization'];
          }
          if (auth) remember(auth);
        }
        if (input && typeof input === 'object' && input.headers && typeof input.headers.get === 'function') {
          var inherited = input.headers.get('Authorization') || input.headers.get('authorization');
          if (inherited) remember(inherited);
        }
      } catch (e) {}

      var res = await originalFetch.apply(this, args);

      try {
        var url = typeof args[0] === 'string' ? args[0] : args[0] && args[0].url ? args[0].url : '';
        if (url.indexOf('token') >= 0 || url.indexOf('session') >= 0 || url.indexOf('auth') >= 0) {
          res.clone().json().then(function (data) {
            if (data && typeof data === 'object' && data.isAnonymous !== true) {
              remember(data.accessToken || data.access_token || data.token);
            }
          }).catch(function () {});
        }
      } catch (e) {}

      return res;
    };
  }

  try {
    var originalSetHeader = XMLHttpRequest.prototype.setRequestHeader;
    XMLHttpRequest.prototype.setRequestHeader = function (header, value) {
      try {
        if (header && typeof header === 'string' && header.toLowerCase() === 'authorization') remember(value);
      } catch (e) {}
      return originalSetHeader.apply(this, arguments);
    };
  } catch (e) {}
})();
