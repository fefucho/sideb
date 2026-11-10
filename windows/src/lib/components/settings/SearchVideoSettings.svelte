<script lang="ts">
  import {t} from '$lib/i18n';
  import {searchPreferences} from '$lib/search/searchPreferences';
</script>

<!-- Installation preference; the owner section (HomeSettings) supplies the surrounding group/heading. -->
<div class="search-video-setting">
  <label for="search-show-videos">
    <input id="search-show-videos" type="checkbox" role="switch" checked={$searchPreferences} aria-describedby="search-show-videos-hint"
      onchange={event=>searchPreferences.setShowVideos(event.currentTarget.checked)} />
    <span>{$t('settings.search.showVideos')}</span>
  </label>
  <p id="search-show-videos-hint">{$t('settings.search.showVideos.hint')}</p>
</div>

<style>
  .search-video-setting { display:flex; flex-direction:column; gap:4px; min-width:0; }
  label { display:flex; align-items:center; gap:7px; min-width:0; font-size:12px; cursor:pointer; }
  input[type=checkbox] { accent-color:var(--sideb-accent); flex:none; }
  p { margin:0 0 0 22px; color:rgb(255 255 255 / 56%); font-size:11px; line-height:1.4; }
</style>
