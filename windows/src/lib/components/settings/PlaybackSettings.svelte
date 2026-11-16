<script lang="ts">
  import { t } from '$lib/i18n';
  import { queuePreferences } from '$lib/player/queuePreferences';
  import SidebarLyricsSettings from './SidebarLyricsSettings.svelte';
  import SettingsGroup from './SettingsGroup.svelte';
  import SettingsRow from './SettingsRow.svelte';
  import SettingsSelect from './SettingsSelect.svelte';
  import SettingsSwitch from './SettingsSwitch.svelte';
  import { automixBlockedByJam, automixPresentation, type AutomixStatus } from '$lib/player/automix';
  interface Props { exponentialVolume: boolean; volumeModePending: boolean; onExponentialVolume?: (enabled: boolean) => void;
    automix?: AutomixStatus; automixPending?: boolean; automixError?: string | null; onAutomix?: (enabled: boolean) => void }
  let { exponentialVolume, volumeModePending, onExponentialVolume, automix, automixPending = false, automixError = null, onAutomix }: Props = $props();
  const automixState = $derived(automix ? automixPresentation(automix, $t) : null);
  const automixJam = $derived(automix ? automixBlockedByJam(automix) : false);
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
  {#if automix && onAutomix}
    <SettingsGroup title={$t('settings.automix')} footer={automixError ? `${$t('windows.automix.error')}\n${$t('settings.automix.hint')}` : $t('settings.automix.hint')}>
      <SettingsRow title={$t('settings.automix')}>
        {#snippet children({ labelId })}
          <!-- The saved preference stays visible; a Jam only disables the control (and says why). -->
          {#if automixState && (automix.enabled || automixJam)}<span class="automix-state" data-tone={automixState.tone}>{automixState.text}</span>{/if}
          <SettingsSwitch id="automix-toggle" labelledby={labelId} checked={automix.enabled} disabled={automixPending || automixJam} onChange={enabled => onAutomix?.(enabled)} />
        {/snippet}
      </SettingsRow>
    </SettingsGroup>
  {/if}
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
  .automix-state { margin-right:10px; font-size:12px; color:var(--control-muted, #c3c3cb); }
  .automix-state[data-tone='warning'] { color:#ffd9a8; }
</style>
