Anonymous YTM internal endpoint captures, 2026-10-12; WEB_REMIX bundled version,
hl=en/gl=US, no Cookie, Authorization, onBehalfOfUser or account data.

- search-suggestions-anonymous.json: music/get_search_suggestions, input=kanye.
- search-correction-anonymous.json: search, query=kany west runaway; only the
  showingResultsForRenderer display fragment is retained.

Removed responseContext, visitor data, response IDs, tracking/click tracking,
accessibility logging and feedback tokens. Media IDs, public thumbnails,
provider display order and navigation metadata retained. These fixtures record
one provider response; they do not assert future live rankings.

Reference for request and spelling parameter:
https://github.com/sigma67/ytmusicapi/blob/main/ytmusicapi/mixins/search.py
https://github.com/sigma67/ytmusicapi/blob/main/ytmusicapi/parsers/search.py
