<script lang="ts">
  import { onMount } from 'svelte';
  import { t } from '$lib/i18n';
  import { appearance } from '$lib/appearance/preferences';
  import { clearAnimatedArtworkCacheSafely, getAnimatedArtworkCacheSize } from '$lib/artwork/animated';
  import ControlButton from '../common/ControlButton.svelte';
  import SettingsGroup from './SettingsGroup.svelte';
  import SettingsRow from './SettingsRow.svelte';
  import SettingsSelect from './SettingsSelect.svelte';
  import SettingsSwitch from './SettingsSwitch.svelte';
  let artworkCacheSize = $state<number | null>(null); let artworkCachePending = $state(false); let artworkCacheError = $state(false);
  const megabytes = $derived(artworkCacheSize === null ? '—' : (artworkCacheSize / (1024 * 1024)).toFixed(1));
  onMount(() => { void refreshArtworkCacheSize(); });
  async function refreshArtworkCacheSize() { try { artworkCacheSize = await getAnimatedArtworkCacheSize(); } catch { artworkCacheError = true; } }
  async function clearArtworkCache() {
    if (artworkCachePending) return;
    artworkCachePending = true; artworkCacheError = false;
    try { artworkCacheSize = await clearAnimatedArtworkCacheSafely(); artworkCacheError = artworkCacheSize > 0; }
    catch { artworkCacheError = true; }
    finally { artworkCachePending = false; }
  }
</script>
<div class="stack">
  <SettingsGroup title={$t('settings.appearance')}>
    <SettingsRow title={$t('settings.sidebarLayout')}>
      {#snippet children({ labelId })}
        <SettingsSelect id="sidebar-layout-picker" labelledby={labelId} value={$appearance.sidebarLayout}
          options={[{ value: 'list', label: $t('sidebar.layout.list') }, { value: 'grid', label: $t('sidebar.layout.grid') }]}
          onChange={value => appearance.setSidebarLayout(value === 'grid' ? 'grid' : 'list')} />
      {/snippet}
    </SettingsRow>
    <SettingsRow title={$t('windows.settings.sidebarStyle')} subtitle={$t('windows.settings.sidebarStyle.hint')}>
      {#snippet children({ labelId, hintId })}
        <SettingsSelect id="sidebar-style-picker" labelledby={labelId} describedby={hintId} value={$appearance.sidebarStyle}
          options={[{ value: 'solid', label: $t('windows.settings.sidebarStyle.solid') }, { value: 'floating', label: $t('windows.settings.sidebarStyle.floating') }]}
          onChange={value => appearance.setSidebarStyle(value === 'floating' ? 'floating' : 'solid')} />
      {/snippet}
    </SettingsRow>
    <SettingsRow title={$t('windows.settings.sidebarCollapse')} subtitle={$t('windows.settings.sidebarCollapse.hint')}>
      {#snippet children({ labelId, hintId })}
        <SettingsSelect id="sidebar-collapse-picker" labelledby={labelId} describedby={hintId} value={$appearance.sidebarCollapseMode}
          options={[{ value: 'icons', label: $t('windows.settings.sidebarCollapse.icons') }, { value: 'hidden', label: $t('windows.settings.sidebarCollapse.hidden') }]}
          onChange={value => appearance.setSidebarCollapseMode(value === 'hidden' ? 'hidden' : 'icons')} />
      {/snippet}
    </SettingsRow>
    <SettingsRow title={$t('settings.homeBackground')} subtitle={$t('settings.homeBackground.hint')}>
      {#snippet children({ labelId, hintId })}
        <SettingsSelect id="home-background-picker" labelledby={labelId} describedby={hintId} value={$appearance.homeBackground}
          options={[{ value: 'artwork', label: $t('settings.homeBackground.ambient') }, { value: 'solid', label: $t('settings.homeBackground.solid') }]}
          onChange={value => appearance.setHomeBackground(value === 'solid' ? 'solid' : 'artwork')} />
      {/snippet}
    </SettingsRow>
    <SettingsRow title={$t('windows.settings.albumCardStyle')} subtitle={$t('windows.settings.albumCardStyle.hint')}>
      {#snippet children({ labelId, hintId })}
        <SettingsSelect id="album-card-style-picker" labelledby={labelId} describedby={hintId} value={$appearance.albumCardStyle}
          options={[{ value: 'tinted', label: $t('windows.settings.albumCardStyle.tinted') }, { value: 'white', label: $t('windows.settings.albumCardStyle.white') }]}
          onChange={value => appearance.setAlbumCardStyle(value === 'white' ? 'white' : 'tinted')} />
      {/snippet}
    </SettingsRow>
  </SettingsGroup>
  <SettingsGroup title={$t('settings.animatedArtwork')}>
    <SettingsRow title={$t('settings.animatedArtwork')} subtitle={$t('settings.animatedArtwork.hint')}>
      {#snippet children({ labelId, hintId })}
        <SettingsSwitch id="animated-artwork-toggle" labelledby={labelId} describedby={hintId} checked={$appearance.animatedArtwork} onChange={enabled => appearance.setAnimatedArtwork(enabled)} />
      {/snippet}
    </SettingsRow>
    <SettingsRow title={$t('windows.settings.artworkCache')} subtitle={artworkCacheError ? null : `${megabytes} MB`}>
      {#snippet children()}
        <ControlButton size="utility" disabled={artworkCachePending || artworkCacheSize === null} onclick={clearArtworkCache}>
          {artworkCachePending ? $t('settings.animatedArtwork.cacheClearing') : $t('settings.animatedArtwork.clearCache', [megabytes])}
        </ControlButton>
      {/snippet}
    </SettingsRow>
    {#if artworkCacheError}<p class="error" role="status">{$t('settings.animatedArtwork.cacheFailure')}</p>{/if}
  </SettingsGroup>
</div>
<style>
  .stack { display:flex; flex-direction:column; gap:24px; min-width:0; }
  .error { margin:0; font-size:11.5px; line-height:16px; color:#ffb9c0; }
</style>
