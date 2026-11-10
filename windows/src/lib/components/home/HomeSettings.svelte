<script lang="ts">
  import { onMount, untrack } from 'svelte';
  import { t } from '$lib/i18n';
  import type { CollectionKind, HomeSettings } from '$lib/home/settings';
  import AccountSettings from '../settings/AccountSettings.svelte';
  import AppearanceSettings from '../settings/AppearanceSettings.svelte';
  import GeneralSettings from '../settings/GeneralSettings.svelte';
  import HomeFeedSettings from '../settings/HomeFeedSettings.svelte';
  import PlaybackSettings from '../settings/PlaybackSettings.svelte';
  import SettingsIcon from '../settings/SettingsIcon.svelte';
  import ShortcutsSettings from '../settings/ShortcutsSettings.svelte';
  import VisualProviderSettings from '../settings/VisualProviderSettings.svelte';
  import SettingsGroup from '../settings/SettingsGroup.svelte';
  import { matchingCategories, settingsCategories, settingsSectionKey, settingsSections, type SettingsCategoryId } from '../settings/settingsCategories';
  interface Category { key:string; title:string }
  interface Props { settings:HomeSettings; kind:CollectionKind; categories:Category[]; libraryError:string|null; onChange:(settings:HomeSettings)=>void; onKind:(kind:CollectionKind)=>void; onRetryLibrary:()=>void; onClose:()=>void; exponentialVolume?:boolean; volumeModePending?:boolean; onExponentialVolume?:(enabled:boolean)=>void; initialCategory?:SettingsCategoryId }
  let { settings, kind, categories, libraryError, onChange, onKind, onRetryLibrary, onClose, exponentialVolume=false, volumeModePending=false, onExponentialVolume, initialCategory='general' }:Props=$props();
  const detailSelector='.settings-detail';
  const focusable='button:not(:disabled), a[href], input:not(:disabled), select:not(:disabled), textarea:not(:disabled), [tabindex]:not([tabindex="-1"])';
  let selected=$state<SettingsCategoryId>(untrack(()=>initialCategory));
  let query=$state(''); let close:HTMLButtonElement; let dialog:HTMLElement; let search:HTMLInputElement; let nav:HTMLElement; let pressedScrim=false;
  const matches=$derived(matchingCategories(query,key=>$t(key)));
  const current=$derived(settingsCategories.find(category=>category.id===selected)??settingsCategories[0]);
  onMount(()=>{ close.focus(); });
  function onWindowKey(event:KeyboardEvent) {
    if(event.key!=='Escape'||event.defaultPrevented) return;
    event.preventDefault(); event.stopPropagation();
    if(event.target===search&&query){ query=''; return; }
    onClose();
  }
  /** Modal focus trap: Tab cycles inside the panel; focus never reaches the page behind. */
  function trapFocus(event:KeyboardEvent) {
    if(event.key!=='Tab'||event.defaultPrevented||event.isComposing) return;
    const items=[...dialog.querySelectorAll<HTMLElement>(focusable)].filter(element=>!element.closest('[hidden], [inert]')&&getComputedStyle(element).display!=='none');
    const first=items[0],last=items.at(-1);
    if(!first||!last){ event.preventDefault(); dialog.focus(); }
    else if(event.shiftKey&&(document.activeElement===first||!dialog.contains(document.activeElement))){ event.preventDefault(); last.focus(); }
    else if(!event.shiftKey&&(document.activeElement===last||!dialog.contains(document.activeElement))){ event.preventDefault(); first.focus(); }
  }
  function navigate(event:KeyboardEvent) {
    if(event.altKey||event.ctrlKey||event.metaKey||!['ArrowUp','ArrowDown','Home','End'].includes(event.key)) return;
    const items=[...nav.querySelectorAll<HTMLButtonElement>('button.item')]; if(!items.length) return;
    const index=items.indexOf(document.activeElement as HTMLButtonElement);
    const next=event.key==='Home'?0:event.key==='End'?items.length-1:Math.max(0,Math.min(items.length-1,(index<0?0:index)+(event.key==='ArrowDown'?1:-1)));
    event.preventDefault(); items[next].focus();
  }
</script>
<svelte:window onkeydown={onWindowKey} />
<!-- svelte-ignore a11y_click_events_have_key_events, a11y_no_static_element_interactions -->
<div class="scrim" onpointerdown={event=>{pressedScrim=event.target===event.currentTarget;}} onclick={event=>{if(pressedScrim&&event.target===event.currentTarget)onClose();pressedScrim=false;}}>
  <div class="panel" role="dialog" aria-modal="true" aria-label={$t('settings.title')} tabindex="-1" bind:this={dialog} onkeydown={trapFocus}>
    <div class="side">
      <div class="side-top"><button type="button" class="close" bind:this={close} aria-label={$t('settings.close')} title={$t('settings.close')} onclick={onClose}><svg viewBox="0 0 12 12" aria-hidden="true"><path d="m3 3 6 6M9 3 3 9" /></svg></button></div>
      <div class="search" role="search">
        <svg viewBox="0 0 16 16" aria-hidden="true"><circle cx="7" cy="7" r="4.5" /><path d="m10.5 10.5 3 3" /></svg>
        <input type="search" bind:this={search} bind:value={query} aria-label={$t('settings.searchPlaceholder')} placeholder={$t('settings.searchPlaceholder')} autocomplete="off" spellcheck="false" />
        {#if query}<button type="button" class="clear" aria-label={$t('windows.settings.clearSearch')} onclick={()=>{query='';search.focus();}}><svg viewBox="0 0 12 12" aria-hidden="true"><path d="m3 3 6 6M9 3 3 9" /></svg></button>{/if}
      </div>
      <!-- svelte-ignore a11y_no_noninteractive_element_interactions -->
      <nav class="categories" bind:this={nav} aria-label={$t('windows.settings.categoriesNav')} onkeydown={navigate}>
        {#each settingsSections as section (section)}
          {@const items=matches.filter(category=>category.section===section)}
          {#if items.length}
            <div class="section" role="group" aria-labelledby={`settings-section-${section}`}>
              <p class="section-title" id={`settings-section-${section}`}>{$t(settingsSectionKey(section))}</p>
              {#each items as category (category.id)}
                <button type="button" class="item" data-category={category.id} aria-current={selected===category.id?'page':undefined} onclick={()=>selected=category.id}>
                  <span class="glyph"><SettingsIcon name={category.id} /></span><span class="label">{$t(category.titleKey)}</span>
                </button>
              {/each}
            </div>
          {/if}
        {/each}
        {#if !matches.length}<p class="empty" role="status">{$t('windows.settings.noResults')}</p>{/if}
      </nav>
    </div>
    <div class="detail settings-detail" role="region" aria-labelledby="settings-category-title">
      {#key selected}
        <div class="content" data-category={selected}>
          <header><h2 id="settings-category-title">{$t(current.titleKey)}</h2><p>{$t(current.subtitleKey)}</p></header>
          {#if selected==='general'}<GeneralSettings />
          {:else if selected==='playback'}<PlaybackSettings {exponentialVolume} {volumeModePending} {onExponentialVolume} />
          {:else if selected==='appearance'}<AppearanceSettings />
          {:else if selected==='visualProviders'}<SettingsGroup><div class="slot"><VisualProviderSettings /></div></SettingsGroup>
          {:else if selected==='homeFeed'}<HomeFeedSettings {settings} {kind} {categories} {libraryError} {onChange} {onKind} {onRetryLibrary} scrollSelector={detailSelector} />
          {:else if selected==='account'}<AccountSettings />
          {:else}<ShortcutsSettings />{/if}
        </div>
      {/key}
    </div>
  </div>
</div>
<style>
  .scrim { position:fixed; z-index:120; inset:var(--titlebar-height,32px) 0 0 0; display:grid; place-items:center; box-sizing:border-box; padding:8px; background:rgb(0 0 0 / 38%); }
  /* Apple: up to 1240x860, never below 780x520, otherwise follows the window. */
  .panel { box-sizing:border-box; display:grid; grid-template-columns:244px minmax(0,1fr); overflow:hidden; color:#f7f7fa;
    width:min(clamp(780px,calc(100vw - 48px),1240px),calc(100vw - 16px)); height:min(clamp(520px,calc(100vh - 96px),860px),calc(100vh - var(--titlebar-height,32px) - 16px));
    background:var(--sideb-acrylic-surface); backdrop-filter:var(--sideb-acrylic-blur); border:1px solid var(--sideb-surface-border); border-radius:16px; box-shadow:0 12px 24px #0006, 0 16px 50px #0007; }
  .panel:focus { outline:none; }
  .side { display:flex; flex-direction:column; min-height:0; background:rgb(0 0 0 / 12%); border-right:1px solid rgb(255 255 255 / 6%); }
  .side-top { padding:14px 16px 0; }
  button { border:0; color:inherit; font:inherit; cursor:pointer; }
  .close { display:inline-flex; align-items:center; justify-content:center; width:22px; height:22px; padding:0; border-radius:50%; background:rgb(255 255 255 / 10%); color:var(--control-muted,#c3c3cb); }
  .close:hover { background:rgb(255 255 255 / 18%); color:#fff; }
  .close svg { width:10px; height:10px; }
  svg { fill:none; stroke:currentColor; stroke-width:1.6; stroke-linecap:round; stroke-linejoin:round; }
  .search { display:flex; align-items:center; gap:6px; box-sizing:border-box; height:28px; margin:12px 12px 6px; padding:0 9px; border-radius:8px; background:rgb(255 255 255 / 7%); color:var(--control-muted,#c3c3cb); }
  .search:focus-within { outline:2px solid var(--sideb-highlight); outline-offset:1px; }
  .search > svg { width:13px; height:13px; flex:none; }
  .search input { flex:1; min-width:0; height:100%; border:0; padding:0; background:transparent; color:var(--control-foreground,#f3f3f6); font:inherit; font-size:13px; outline:none; }
  .search input::-webkit-search-cancel-button { display:none; }
  .clear { display:inline-flex; align-items:center; justify-content:center; flex:none; width:16px; height:16px; padding:0; border-radius:50%; background:transparent; color:inherit; }
  .clear:hover { color:#fff; background:rgb(255 255 255 / 14%); } .clear svg { width:9px; height:9px; }
  .clear:focus-visible { outline:2px solid var(--sideb-highlight); outline-offset:1px; }
  .categories { flex:1; min-height:0; overflow-y:auto; display:flex; flex-direction:column; gap:14px; padding:8px 12px 12px; scrollbar-width:none; }
  .section { display:flex; flex-direction:column; gap:2px; }
  .section-title { margin:0; padding:0 10px 3px; font-size:11px; font-weight:600; line-height:14px; color:rgb(255 255 255 / 45%); }
  .item { display:flex; align-items:center; gap:9px; box-sizing:border-box; width:100%; height:30px; padding:0 10px; border-radius:8px; background:transparent; text-align:left; color:var(--control-foreground,#f3f3f6); font-size:13px; }
  .item:hover { background:rgb(255 255 255 / 5%); }
  .item[aria-current='page'] { background:rgb(255 255 255 / 12%); }
  .item:focus-visible { outline:2px solid var(--sideb-highlight); outline-offset:-2px; }
  .glyph { display:inline-flex; width:20px; height:20px; flex:none; align-items:center; justify-content:center; color:var(--sideb-highlight); }
  .glyph :global(svg) { width:17px; height:17px; }
  .label { min-width:0; overflow:hidden; text-overflow:ellipsis; white-space:nowrap; }
  .empty { margin:0; padding:0 10px; font-size:12px; color:var(--control-muted,#c3c3cb); }
  .detail { min-width:0; min-height:0; overflow-y:auto; container-type:inline-size; container-name:settings-detail; }
  .content { box-sizing:border-box; display:flex; flex-direction:column; gap:26px; width:100%; max-width:720px; margin-inline:auto; padding:34px 36px 32px; }
  .content[data-category='homeFeed'] { max-width:980px; }
  header { display:flex; flex-direction:column; gap:5px; }
  h2 { margin:0; font-size:28px; line-height:34px; font-weight:700; }
  header p { margin:0; font-size:13px; line-height:18px; color:var(--control-muted,#c3c3cb); }
  .slot { display:flex; flex-direction:column; gap:6px; min-width:0; font-size:13px; }
  @media (prefers-reduced-transparency:reduce) { .panel { background:#24242a; backdrop-filter:none; } }
</style>
