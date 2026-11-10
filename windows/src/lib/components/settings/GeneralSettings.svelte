<script lang="ts">
  import { getContext } from 'svelte';
  import { t, language, setLanguage } from '$lib/i18n';
  import type { UpdaterSnapshot } from '$lib/updater/controller';
  import ControlButton from '../common/ControlButton.svelte';
  import SearchVideoSettings from './SearchVideoSettings.svelte';
  import SettingsGroup from './SettingsGroup.svelte';
  import SettingsRow from './SettingsRow.svelte';
  import SettingsSelect from './SettingsSelect.svelte';
  import { SETTINGS_HOST_CONTEXT, type SettingsHost } from './settingsCategories';
  const host = getContext<SettingsHost | undefined>(SETTINGS_HOST_CONTEXT);
  let snapshot = $state<UpdaterSnapshot | null>(null);
  $effect(() => host?.updater.subscribe(next => { snapshot = next; }));
  const updateState = $derived(snapshot?.state);
  const summary = $derived.by(() => {
    const state = updateState;
    if (!state) return '';
    switch (state.type) {
      case 'checking': return $t('update.checking');
      case 'available': return $t('update.available_title', [state.info.version]);
      case 'downloading': return $t('update.downloading');
      case 'installing': return $t('update.installing');
      case 'failed': return state.message;
      default: return $t('update.latest_detail');
    }
  });
</script>
<div class="stack">
  <SettingsGroup title={$t('windows.settings.group.language')}>
    <SettingsRow title={$t('settings.language')}>
      {#snippet children({ labelId })}
        <SettingsSelect labelledby={labelId} value={$language} options={[{ value: 'es', label: 'Español' }, { value: 'en', label: 'English' }]}
          onChange={value => setLanguage(value === 'en' ? 'en' : 'es')} />
      {/snippet}
    </SettingsRow>
  </SettingsGroup>
  <SettingsGroup title={$t('menu.search')}>
    <div class="slot"><SearchVideoSettings /></div>
  </SettingsGroup>
  {#if host && snapshot}
    <SettingsGroup title={$t('windows.settings.group.updates')}>
      <SettingsRow title={`${$t('update.installed')}: Side B ${snapshot.currentVersion}`} subtitle={summary}>
        {#snippet children()}
          <ControlButton size="utility" loading={updateState?.type === 'checking'} onclick={() => { void host.updater.checkForUpdates(true); }}>{$t('menu.check_updates')}</ControlButton>
        {/snippet}
      </SettingsRow>
    </SettingsGroup>
  {/if}
</div>
<style>
  .stack { display:flex; flex-direction:column; gap:24px; min-width:0; }
</style>
