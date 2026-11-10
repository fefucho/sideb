<script lang="ts">
  import { t } from '$lib/i18n';
  import { queuePreferences } from '$lib/player/queuePreferences';
  import SidebarLyricsSettings from './SidebarLyricsSettings.svelte';
  import SettingsGroup from './SettingsGroup.svelte';
  import SettingsRow from './SettingsRow.svelte';
  import SettingsSelect from './SettingsSelect.svelte';
  import SettingsSwitch from './SettingsSwitch.svelte';
  interface Props { exponentialVolume: boolean; volumeModePending: boolean; onExponentialVolume?: (enabled: boolean) => void }
  let { exponentialVolume, volumeModePending, onExponentialVolume }: Props = $props();
</script>
<div class="stack">
  <SettingsGroup title={$t('queue.settings.title')} footer={$t('queue.selection.hint')}>
    <SettingsRow title={$t('queue.selection.label')}>
      {#snippet children({ labelId })}
        <SettingsSelect id="queue-recommendation-selection" labelledby={labelId} value={$queuePreferences}
          options={[{ value: 'advance', label: $t('queue.selection.advance') }, { value: 'play-only', label: $t('queue.selection.playOnly') }]}
          onChange={value => queuePreferences.setSelection(value)} />
      {/snippet}
    </SettingsRow>
  </SettingsGroup>
  <SettingsGroup title={$t('settings.sidebarBottomContent.cardTitle')}>
    <div class="slot"><SidebarLyricsSettings /></div>
  </SettingsGroup>
  {#if onExponentialVolume}
    <SettingsGroup title={$t('windows.settings.audio')} footer={$t('windows.settings.exponentialVolumeHint')}>
      <SettingsRow title={$t('windows.settings.exponentialVolume')}>
        {#snippet children({ labelId })}
          <SettingsSwitch id="exponential-volume-toggle" labelledby={labelId} checked={exponentialVolume} disabled={volumeModePending} onChange={enabled => onExponentialVolume?.(enabled)} />
        {/snippet}
      </SettingsRow>
    </SettingsGroup>
  {/if}
</div>
<style>
  .stack { display:flex; flex-direction:column; gap:24px; min-width:0; }
</style>
