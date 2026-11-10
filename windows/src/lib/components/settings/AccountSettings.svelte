<script lang="ts">
  import { getContext } from 'svelte';
  import { t, language, resolveMessage } from '$lib/i18n';
  import ControlButton from '../common/ControlButton.svelte';
  import SettingsGroup from './SettingsGroup.svelte';
  import SettingsRow from './SettingsRow.svelte';
  import { SETTINGS_HOST_CONTEXT, type SettingsHost } from './settingsCategories';
  const host = getContext<SettingsHost | undefined>(SETTINGS_HOST_CONTEXT);
  const auth = $derived(host?.auth);
</script>
<div class="stack">
  {#if host && auth}
    <SettingsGroup>
      <div class="account">
        {#if auth.state === 'ready'}
          {#if auth.thumbnail}<img class="avatar" src={auth.thumbnail} alt="" />{:else}<span class="avatar fallback" aria-hidden="true"></span>{/if}
          <div class="who">
            <strong>{auth.name ?? $t('account.user')}</strong>
            {#if auth.handle}<span>{auth.handle}</span>{/if}
            {#if auth.email}<small>{auth.email}</small>{/if}
          </div>
          <ControlButton size="utility" onclick={() => host.logout()}>{$t('account.sign_out')}</ControlButton>
        {:else}
          <span class="avatar fallback" aria-hidden="true"></span>
          <div class="who">
            <strong>{$t('account.guest_mode')}</strong>
            <span>{$t('windows.settings.guestHint')}</span>
            {#if auth.message}<small class="error" role="alert">{resolveMessage(auth.message, $language)}</small>{/if}
          </div>
          {#if auth.state === 'authorizing'}
            <ControlButton size="utility" onclick={() => host.cancelLogin()}>{$t('windows.ui.cancelSignIn')}</ControlButton>
          {:else}
            <ControlButton size="utility" emphasis="prominent" onclick={() => host.login()}>{$t('account.sign_in_ellipsis')}</ControlButton>
          {/if}
        {/if}
      </div>
    </SettingsGroup>
  {/if}
  <SettingsGroup title={$t('windows.settings.group.privacy')} footer={$t('windows.settings.privacyFooter')}>
    <SettingsRow title={$t('windows.settings.sessionStorage')}>
      {#snippet children()}<span class="value">{$t('windows.settings.sessionStorageValue')}</span>{/snippet}
    </SettingsRow>
  </SettingsGroup>
</div>
<style>
  .stack { display:flex; flex-direction:column; gap:24px; min-width:0; }
  .account { display:flex; align-items:center; gap:14px; min-width:0; }
  .avatar { flex:none; width:52px; height:52px; border-radius:50%; object-fit:cover; }
  .avatar.fallback { background:rgb(255 255 255 / 12%); }
  .who { display:flex; flex-direction:column; gap:2px; flex:1 1 auto; min-width:0; overflow-wrap:anywhere; }
  .who strong { font-size:15px; font-weight:600; line-height:20px; }
  .who span { font-size:12px; line-height:17px; color:var(--control-muted, #c3c3cb); }
  .who small { font-size:11.5px; line-height:16px; color:var(--control-muted, #c3c3cb); }
  .who .error { color:#ffb9c0; }
  .value { font-size:12.5px; color:var(--control-muted, #c3c3cb); }
</style>
