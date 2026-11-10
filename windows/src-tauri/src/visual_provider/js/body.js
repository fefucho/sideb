// For a page that is itself the token endpoint: its body is the JSON document.
(function () {
  try {
    var data = JSON.parse(document.body.innerText);
    if (data && data.isAnonymous !== true) return data.accessToken || data.access_token || data.token || null;
  } catch (e) {}
  return null;
})()
