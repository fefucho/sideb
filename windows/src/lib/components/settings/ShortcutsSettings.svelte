<script lang="ts">
  import { t } from '$lib/i18n';
  import SettingsGroup from './SettingsGroup.svelte';
  import SettingsRow from './SettingsRow.svelte';
  /** Only shortcuts the Windows shell actually handles (+page keydown, playback-shortcut, UpdateModal/dialog Escape). */
  const playback = $derived([{ label: $t('windows.settings.shortcut.playPause'), keys: [$t('windows.settings.key.space')] }]);
  const navigation = $derived([
    { label: $t('windows.settings.shortcut.search'), keys: ['Ctrl', 'K'] },
    { label: $t('windows.settings.shortcut.newPlaylist'), keys: ['Ctrl', 'N'] },
    { label: $t('windows.settings.shortcut.back'), keys: ['Alt', '←'] },
    { label: $t('windows.settings.shortcut.forward'), keys: ['Alt', '→'] },
    { label: $t('windows.settings.shortcut.windowFullscreen'), keys: ['F11'] },
    { label: $t('windows.settings.shortcut.dismiss'), keys: ['Esc'] },
  ]);
</script>
<div class="stack">
  {#each [{ title: $t('settings.category.playback'), rows: playback }, { title: $t('windows.settings.group.navigation'), rows: navigation }] as group (group.title)}
    <SettingsGroup title={group.title}>
      {#each group.rows as row (row.label)}
        <SettingsRow title={row.label}>
          {#snippet children()}
            <span class="keys">{#each row.keys as key, index (index)}<kbd>{key}</kbd>{/each}</span>
          {/snippet}
        </SettingsRow>
      {/each}
    </SettingsGroup>
  {/each}
</div>
<style>
  .stack { display:flex; flex-direction:column; gap:24px; min-width:0; }
  .keys { display:inline-flex; gap:4px; }
  kbd { box-sizing:border-box; min-width:24px; height:22px; padding:0 7px; display:inline-flex; align-items:center; justify-content:center; border-radius:5px; background:rgb(255 255 255 / 9%); color:var(--control-muted, #c3c3cb); font:inherit; font-size:12px; font-weight:500; }
</style>
