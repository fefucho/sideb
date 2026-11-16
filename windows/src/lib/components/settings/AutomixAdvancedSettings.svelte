<script lang="ts">
  import { getContext, onMount } from 'svelte';
  import { t } from '$lib/i18n';
  import { describeCapability, formatBytes, type AutomixSettings } from '$lib/player/automix';
  import ControlButton from '$lib/components/common/ControlButton.svelte';
  import SettingsGroup from './SettingsGroup.svelte';
  import SettingsRow from './SettingsRow.svelte';
  import SettingsSelect from './SettingsSelect.svelte';
  import SettingsSwitch from './SettingsSwitch.svelte';
  import { AUTOMIX_HOST_CONTEXT, type AutomixHost } from './automixHost';

  /** Quality, battery and album rules, plus the advanced block, from the core's shared Automix settings. */
  const host = getContext<AutomixHost | undefined>(AUTOMIX_HOST_CONTEXT);
  const options = $derived(host?.snapshot.options ?? null);
  const busy = $derived(host?.snapshot.optionsPending ?? false);
  const capability = $derived(options ? describeCapability(options.capability) : null);
  let confirming = $state<'cache' | 'model' | null>(null);

  onMount(() => { void host?.controller.refreshOptions(); });
  // While the model downloads, keep the capability line fresh.
  $effect(() => {
    if (!options?.capability.modelDownloading) return;
    const timer = setInterval(() => { void host?.controller.refreshOptions(); }, 2000);
    return () => clearInterval(timer);
  });

  const cacheBytes = $derived(options ? options.cache.audioBytes + options.cache.stemsBytes + options.cache.transitionsBytes : 0);
  const qualityOptions = $derived([
    { value: 'auto', label: $t('windows.automix.quality.auto') },
    { value: 'fast', label: $t('windows.automix.quality.fast') },
    { value: 'stems', label: $t('windows.automix.quality.stems') },
  ]);
  const computeOptions = $derived([
    { value: 'auto', label: $t('windows.automix.compute.auto') },
    { value: 'gpu', label: $t('windows.automix.compute.gpu') },
    { value: 'cpu', label: $t('windows.automix.compute.cpu') },
  ]);
  const lookaheadOptions = $derived([
    { value: '1', label: $t('windows.automix.lookahead.one') },
    { value: '2', label: $t('windows.automix.lookahead.two') },
    { value: '3', label: $t('windows.automix.lookahead.three') },
  ]);
  const capabilityLine = $derived(capability ? [
    $t(`windows.automix.capability.model.${capability.model}`),
    capability.provider ? $t('windows.automix.capability.provider', [capability.provider]) : $t('windows.automix.capability.providerUnknown'),
    capability.speed ? $t('windows.automix.capability.speed', [capability.speed]) : $t('windows.automix.capability.speedUnknown'),
    $t(capability.recommended ? 'windows.automix.capability.recommended' : 'windows.automix.capability.notRecommended'),
  ].join(' · ') : '');
  const usageLine = $derived(options ? $t('windows.automix.cache.usage', [
    formatBytes(options.cache.audioBytes), formatBytes(options.cache.stemsBytes),
    formatBytes(options.cache.transitionsBytes), formatBytes(options.cache.modelBytes),
  ]) : '');

  /**
   * Sends one change. A native <select> keeps showing what the user picked even when saving fails (the
   * confirmed value did not change, so nothing re-renders): put the confirmed value back.
   */
  async function choose<K extends 'quality' | 'compute' | 'lookahead'>(id: string, key: K, value: AutomixSettings[K]) {
    await host?.controller.updateSettings({ [key]: value });
    const confirmed = host?.snapshot.options?.settings[key];
    const element = document.getElementById(id) as HTMLSelectElement | null;
    if (element && element.tagName === 'SELECT' && confirmed !== undefined) element.value = String(confirmed);
  }

  async function confirmDelete() {
    const target = confirming;
    confirming = null;
    if (target === 'cache') await host?.controller.clearCache();
    else if (target === 'model') await host?.controller.deleteModel();
  }
</script>
{#if host && options}
  <SettingsGroup title={$t('windows.automix.options.title')} footer={host.snapshot.optionsError ? $t('windows.automix.options.error') : undefined}>
    <SettingsRow title={$t('windows.automix.quality.label')} subtitle={$t('windows.automix.quality.hint')}>
      {#snippet children({ labelId })}
        <SettingsSelect id="automix-quality" labelledby={labelId} value={options.settings.quality} options={qualityOptions} disabled={busy}
          onChange={value => void choose('automix-quality', 'quality', value as AutomixSettings['quality'])} />
      {/snippet}
    </SettingsRow>
    <SettingsRow title={$t('windows.automix.fastOnBattery')}>
      {#snippet children({ labelId })}
        <SettingsSwitch id="automix-fast-on-battery" labelledby={labelId} checked={options.settings.fastOnBattery} disabled={busy}
          onChange={checked => void host.controller.updateSettings({ fastOnBattery: checked })} />
      {/snippet}
    </SettingsRow>
    <SettingsRow title={$t('windows.automix.skipSameAlbum')}>
      {#snippet children({ labelId })}
        <SettingsSwitch id="automix-skip-same-album" labelledby={labelId} checked={options.settings.skipSameAlbum} disabled={busy}
          onChange={checked => void host.controller.updateSettings({ skipSameAlbum: checked })} />
      {/snippet}
    </SettingsRow>
  </SettingsGroup>
  <details class="advanced">
    <summary>{$t('windows.automix.advanced')}</summary>
    <SettingsGroup>
      <SettingsRow title={$t('windows.automix.compute.label')}>
        {#snippet children({ labelId })}
          <SettingsSelect id="automix-compute" labelledby={labelId} value={options.settings.compute} options={computeOptions} disabled={busy}
            onChange={value => void choose('automix-compute', 'compute', value as AutomixSettings['compute'])} />
        {/snippet}
      </SettingsRow>
      <SettingsRow title={$t('windows.automix.lookahead.label')}>
        {#snippet children({ labelId })}
          <SettingsSelect id="automix-lookahead" labelledby={labelId} value={String(options.settings.lookahead)} options={lookaheadOptions} disabled={busy}
            onChange={value => void choose('automix-lookahead', 'lookahead', Number(value) as AutomixSettings['lookahead'])} />
        {/snippet}
      </SettingsRow>
      <SettingsRow title={$t('windows.automix.keepModel.label')} subtitle={$t('windows.automix.keepModel.hint')}>
        {#snippet children({ labelId })}
          <SettingsSwitch id="automix-keep-model" labelledby={labelId} checked={options.settings.keepModelLoaded} disabled={busy}
            onChange={checked => void host.controller.updateSettings({ keepModelLoaded: checked })} />
        {/snippet}
      </SettingsRow>
      <SettingsRow title={$t('windows.automix.capability.title')} subtitle={capabilityLine} />
      <SettingsRow title={$t('windows.automix.cache.title')} subtitle={usageLine}>
        {#snippet children()}
          {#if confirming}
            <span class="confirm" role="alertdialog" aria-label={$t(confirming === 'cache' ? 'windows.automix.cache.clearConfirm' : 'windows.automix.cache.deleteModelConfirm')}>
              <span class="question">{$t(confirming === 'cache' ? 'windows.automix.cache.clearConfirm' : 'windows.automix.cache.deleteModelConfirm')}</span>
              <ControlButton size="utility" emphasis="prominent" disabled={busy} onclick={confirmDelete}>{$t('windows.automix.cache.delete')}</ControlButton>
              <ControlButton size="utility" onclick={() => { confirming = null; }}>{$t('common.cancel')}</ControlButton>
            </span>
          {:else}
            <ControlButton size="utility" id="automix-clear-cache" disabled={busy || cacheBytes === 0} onclick={() => { confirming = 'cache'; }}>{$t('windows.automix.cache.clear')}</ControlButton>
            <ControlButton size="utility" id="automix-delete-model" disabled={busy || !options.capability.modelReady} onclick={() => { confirming = 'model'; }}>{$t('windows.automix.cache.deleteModel')}</ControlButton>
          {/if}
        {/snippet}
      </SettingsRow>
    </SettingsGroup>
  </details>
{/if}
<style>
  .advanced { min-width:0; }
  .advanced > summary { cursor:pointer; padding:2px 4px 8px; font-size:12px; font-weight:500; line-height:16px; color:var(--control-muted, #c3c3cb); }
  .advanced > summary:focus-visible { outline:2px solid var(--sideb-highlight, #d06c70); outline-offset:2px; border-radius:6px; }
  .confirm { display:flex; flex-wrap:wrap; align-items:center; justify-content:flex-end; gap:8px; }
  .question { max-width:240px; font-size:12px; line-height:16px; color:var(--control-foreground, #f3f3f6); }
</style>
