<script lang="ts">
  /**
   * "Panel inferior del reproductor" (macOS Settings → Reproductor lateral): choose what the side player shows under
   * its transport controls, the upcoming queue or a live lyrics sample. No props; the installation preference lives in
   * `sidebarPreferences`. The owner section (HomeSettings) supplies the surrounding group and its heading
   * (`settings.sidebarBottomContent.cardTitle`).
   */
  import { t } from '$lib/i18n';
  import { resolveSidebarBottomContent, sidebarBottomContents, sidebarPreferences } from '$lib/player/sidebarPreferences';
</script>

<div class="sidebar-lyrics-setting">
  <label for="sidebar-bottom-content">{$t('settings.sidebarBottomContent.label')}</label>
  <select id="sidebar-bottom-content" aria-describedby="sidebar-bottom-content-hint" value={$sidebarPreferences}
    onchange={event => sidebarPreferences.setBottomContent(resolveSidebarBottomContent(event.currentTarget.value))}>
    {#each sidebarBottomContents as option (option)}
      <option value={option}>{$t(`settings.sidebarBottomContent.${option}`)}</option>
    {/each}
  </select>
  <p id="sidebar-bottom-content-hint">{$t('settings.sidebarBottomContent.hint')}</p>
</div>

<style>
  .sidebar-lyrics-setting { display:flex; flex-direction:column; align-items:flex-start; gap:6px; min-width:0; }
  label { font-size:12px; }
  select { max-width:100%; padding:7px 8px; border:1px solid #ffffff33; border-radius:6px; background:#29262b; color:white; font:inherit; font-size:12px; }
  select:focus-visible { outline:2px solid var(--sideb-highlight); outline-offset:2px; }
  p { margin:0; color:rgb(255 255 255 / 56%); font-size:11px; line-height:1.4; }
</style>
