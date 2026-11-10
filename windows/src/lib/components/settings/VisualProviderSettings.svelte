<script lang="ts">
  import { onMount } from 'svelte';
  import { t } from '$lib/i18n';
  import { createVisualProviderSettings, settingsStatusKey } from '$lib/visualProvider';
  import ControlButton from '../common/ControlButton.svelte';
  import SettingsSwitch from './SettingsSwitch.svelte';
  import VisualProviderLoginDialog from './VisualProviderLoginDialog.svelte';

  // Self-contained section (no props): HomeSettings supplies the surrounding group and heading.
  // The generic provider contract only: the executable owns every Spotify detail.
  const settings = createVisualProviderSettings();
  const id = $props.id();
  const view = $derived($settings);
  const current = $derived(view.state);
  const provider = $derived(current?.provider ?? null);
  let token = $state('');
  let folder = $state('');
  let showManualToken = $state(false);
  let showFolder = $state(false);

  onMount(() => {
    const stop = settings.start();
    return () => { token = ''; stop(); };
  });

  async function saveToken() {
    const value = token;
    token = ''; // never keep a typed secret in the view
    await settings.saveToken(value);
  }
  async function installFolder() {
    if (await settings.installFromFolder(folder)) { folder = ''; showFolder = false; }
  }
  const signIn = () => settings.signIn(provider?.name ? $t('visualProvider.loginSheetTitle', [provider.name]) : null);
</script>

<div class="provider">
  <p class="hint">{$t('visualProvider.hint')}</p>

  {#if current?.installed && provider}
    <div class="row name">{provider.name} · {provider.version}</div>

    <div class="row switch">
      <span id={`${id}-enable`}>{$t('visualProvider.enable')}</span>
      <SettingsSwitch checked={current.enabled} labelledby={`${id}-enable`} disabled={!current.hasCredential || view.pending}
        onChange={settings.setEnabled} />
    </div>

    {#if provider.webLogin}
      <div class="row account">
        {#if current.hasCredential}
          <span class="connected"><svg viewBox="0 0 16 16" aria-hidden="true"><circle cx="8" cy="8" r="6.5" /><path d="m5.2 8.2 2 2 3.6-4" /></svg>{$t('visualProvider.accountConnected')}</span>
          <ControlButton size="utility" disabled={view.pending} onclick={signIn}>{$t('visualProvider.reconnect')}</ControlButton>
        {:else}
          <span></span>
          <ControlButton size="utility" emphasis="prominent" disabled={view.pending} onclick={signIn}>{$t('visualProvider.signIn')}</ControlButton>
        {/if}
      </div>
    {/if}

    {#snippet tokenEntry()}
      <div class="entry">
        <label for={`${id}-token`}>{$t('visualProvider.token')}</label>
        <input id={`${id}-token`} type="password" autocomplete="off" spellcheck="false" bind:value={token} />
        <ControlButton size="utility" disabled={!token.trim() || view.pending} onclick={saveToken}>{$t('windows.visualProvider.saveToken')}</ControlButton>
        <p>{$t('windows.visualProvider.tokenHint')}</p>
      </div>
    {/snippet}
    <div class="row manual">
      {#if provider.webLogin}
        <details bind:open={showManualToken}>
          <summary>{$t('visualProvider.manualToken')}</summary>
          {@render tokenEntry()}
        </details>
      {:else}
        {@render tokenEntry()}
      {/if}
    </div>

    <div class="row footer">
      <span class="status" role="status" data-status={current.statusKey}>{$t(settingsStatusKey(current.statusKey))}</span>
      <ControlButton size="utility" disabled={view.pending} onclick={() => settings.uninstall()}>{$t('visualProvider.remove')}</ControlButton>
    </div>
  {:else if current}
    <div class="row empty">
      <span>{$t('windows.visualProvider.notInstalled')}</span>
      {#if current.bundledAvailable}
        <ControlButton size="utility" emphasis="prominent" disabled={view.pending} onclick={() => settings.installBundled()}>{$t('windows.visualProvider.installBundled')}</ControlButton>
      {/if}
    </div>
  {/if}

  {#if current}
    <div class="row install">
      <details bind:open={showFolder}>
        <summary>{$t('visualProvider.install')}</summary>
        <div class="entry">
          <label for={`${id}-folder`}>{$t('windows.visualProvider.folderLabel')}</label>
          <input id={`${id}-folder`} type="text" autocomplete="off" spellcheck="false" placeholder="C:\Proveedores\spotify-canvas" bind:value={folder} />
          <ControlButton size="utility" disabled={!folder.trim() || view.pending} onclick={installFolder}>{$t('windows.visualProvider.folderInstall')}</ControlButton>
        </div>
      </details>
    </div>
  {/if}

  {#if view.failed}<p class="error" role="alert">{$t('windows.visualProvider.error')}</p>{/if}
</div>

{#if view.login}
  <VisualProviderLoginDialog providerName={provider?.name ?? ''} progress={view.login} onClose={() => settings.closeLogin()} />
{/if}

<style>
  .provider { display:flex; flex-direction:column; gap:10px; min-width:0; font-size:12.5px; color:var(--control-foreground,#f3f3f6); }
  .hint { margin:0; font-size:11.5px; line-height:16px; color:var(--control-muted,#c3c3cb); }
  .row { display:flex; align-items:center; justify-content:space-between; gap:12px; min-width:0; }
  .row + .row { padding-top:10px; border-top:1px solid rgb(255 255 255 / 8%); }
  .name { justify-content:flex-start; font-weight:500; overflow-wrap:anywhere; }
  .connected { display:inline-flex; align-items:center; gap:6px; font-weight:500; }
  .connected svg { width:15px; height:15px; fill:none; stroke:#7fe3a2; stroke-width:1.5; stroke-linecap:round; stroke-linejoin:round; }
  .manual, .install { display:block; }
  details summary { cursor:pointer; font-size:11.5px; color:var(--control-muted,#c3c3cb); }
  details summary:focus-visible { outline:2px solid var(--sideb-highlight,#d06c70); outline-offset:2px; border-radius:4px; }
  .entry { display:flex; flex-direction:column; align-items:flex-start; gap:8px; padding-top:8px; }
  .entry label { font-size:11.5px; color:var(--control-muted,#c3c3cb); }
  .entry input { box-sizing:border-box; width:100%; height:28px; padding:0 9px; border:1px solid rgb(255 255 255 / 12%); border-radius:8px; background:rgb(255 255 255 / 7%); color:inherit; font:inherit; }
  .entry input:focus-visible { outline:2px solid var(--sideb-highlight,#d06c70); outline-offset:1px; }
  .entry p { margin:0; font-size:11px; line-height:15px; color:var(--control-muted,#c3c3cb); }
  .status { font-size:11.5px; line-height:16px; color:var(--control-muted,#c3c3cb); }
  .error { margin:0; font-size:11.5px; color:#ffb9c0; }
  .empty span { color:var(--control-muted,#c3c3cb); }
</style>
