<script lang="ts">
  import { t, language, setLanguage } from '$lib/i18n';
  import { providerHeading } from '$lib/i18n/presentation';
  import { onMount } from 'svelte';
  import { defaults, move, normalized, orderCategories, sourceLabels, type CollectionKind, type HomeSettings } from '$lib/home/settings';
  import VirtualStack from '../common/VirtualStack.svelte';
  interface Category { key:string; title:string }
  interface Props { settings:HomeSettings; kind:CollectionKind; categories:Category[]; libraryError:string|null; onChange:(settings:HomeSettings)=>void; onKind:(kind:CollectionKind)=>void; onRetryLibrary:()=>void; onClose:()=>void; exponentialVolume?:boolean; volumeModePending?:boolean; onExponentialVolume?:(enabled:boolean)=>void }
  let { settings, kind, categories, libraryError, onChange, onKind, onRetryLibrary, onClose, exponentialVolume=false, volumeModePending=false, onExponentialVolume }:Props=$props();
  let query=$state(''); let close:HTMLButtonElement; let dragSource:number|null=null; let dragCategory:string|null=null;
  $effect(()=>{kind;dragSource=null;});
  const field=$derived(kind==='albums'?'albumSources':'playlistSources');
  const sources=$derived(settings[field]);
  const ordered=$derived(settings.categoryOrderMode==='custom' ? [...categories].sort((a,b) => { const rank=(key:string) => {const i=settings.categoryOrder.indexOf(key);return i<0?1e9:i;}; return rank(a.key)-rank(b.key); }) : categories);
  const filtered=$derived(ordered.filter(category=>normalized(category.title).includes(normalized(query)) || normalized(providerHeading(category.title,$language)).includes(normalized(query))));
  function moveSource(from:number,to:number) { onChange({...settings,[field]:move(sources,from,to)}); }
  function moveCategory(key:string,to:number) { onChange(orderCategories(settings,move(ordered.map(category=>category.key),ordered.findIndex(category=>category.key===key),to))); }
  function toggleCategory(key:string,show:boolean) { onChange({...settings,hiddenCategoryKeys:show?settings.hiddenCategoryKeys.filter(k=>k!==key):[...settings.hiddenCategoryKeys,key]}); }
  function dropSource(event:DragEvent,to:number) { event.preventDefault();if(dragSource!==null) moveSource(dragSource,to);dragSource=null; }
  function dropCategory(event:DragEvent,key:string) { event.preventDefault();if(dragCategory) moveCategory(dragCategory,ordered.findIndex(category=>category.key===key));dragCategory=null; }
  function requestVolumeMode(event: Event & { currentTarget: HTMLInputElement }) {
    const requested = event.currentTarget.checked;
    event.currentTarget.checked = exponentialVolume;
    onExponentialVolume?.(requested);
  }
  onMount(()=>{ close.focus(); });
</script>
<svelte:window onkeydown={event=>{if(event.key==='Escape'&&!event.defaultPrevented){event.preventDefault();event.stopPropagation();onClose();}}} />
<aside class="settings" aria-label={$t('windows.ui.homeSettings')}>
  <header><h2>{$t('windows.ui.homeSettings')}</h2><button type="button" bind:this={close} aria-label={$t('settings.close')} onclick={onClose}>×</button></header>
  <div class="settings-scroll">
    {#if onExponentialVolume}<section><h3>{$t('windows.settings.audio')}</h3><label><input type="checkbox" checked={exponentialVolume} disabled={volumeModePending} onchange={requestVolumeMode} aria-describedby="exponential-volume-hint" /><span>{$t('windows.settings.exponentialVolume')}</span></label><p id="exponential-volume-hint">{$t('windows.settings.exponentialVolumeHint')}</p></section>{/if}
    <section><h3>{$t('settings.general')}</h3><label>{$t('settings.language')} <select aria-label={$t('settings.language')} value={$language} onchange={event=>setLanguage(event.currentTarget.value==='en'?'en':'es')}><option value="es">Español</option><option value="en">English</option></select></label></section>
    <section><h3>{$t('settings.featured')}</h3><div class="kinds" role="group" aria-label={$t('settings.featuredKind')}><button type="button" aria-pressed={kind==='albums'} onclick={()=>onKind('albums')}>{$t('sidebar.albums')}</button><button type="button" aria-pressed={kind==='playlists'} onclick={()=>onKind('playlists')}>{$t('windows.ui.playlists')}</button></div>
    <p>{$t('settings.sourcesHint')}</p>
    {#each sources as row,index (row.source)}
      <!-- svelte-ignore a11y_no_static_element_interactions -->
      <div class="setting-row" ondragover={event=>{if(dragSource!==null)event.preventDefault();}} ondrop={event=>dropSource(event,index)}>
        <label><input type="checkbox" checked={row.enabled} onchange={event=>onChange({...settings,[field]:sources.map(r=>r.source===row.source?{...r,enabled:event.currentTarget.checked}:r)})} /><span>{$t('settings.source.' + row.source)}</span></label>
        <button type="button" aria-label={$t('settings.up', [$t('settings.source.' + row.source)])} disabled={index===0} onclick={()=>moveSource(index,index-1)}>↑</button><button type="button" aria-label={$t('settings.down', [$t('settings.source.' + row.source)])} disabled={index===sources.length-1} onclick={()=>moveSource(index,index+1)}>↓</button>
        <button type="button" class="handle" draggable="true" aria-label={$t('settings.dragAX', [$t('settings.source.' + row.source)])} ondragstart={event=>{dragSource=index;event.dataTransfer?.setData('text/plain',row.source);}} ondragend={()=>dragSource=null}>⠿</button>
      </div>
    {/each}
    {#if !sources.some(s=>s.enabled)}<p role="status">{$t('settings.enableSource')}</p>{/if}
    {#if libraryError}<p class="error" role="alert">{$t('settings.libraryError')}</p><button type="button" class="text-action" onclick={onRetryLibrary}>{$t('settings.retryLibrary')}</button>{/if}
    <button type="button" class="text-action" onclick={()=>onChange({...settings,[field]:defaults()[field]})}>{$t('settings.restoreSources')}</button></section>
    <section><h3>{$t('settings.categories')}</h3><p>{$t('settings.categoriesHint')}</p>
    {#if categories.length>8}<input class="filter" aria-label={$t('settings.searchCategory')} placeholder={$t('settings.searchCategory')} bind:value={query} />{/if}
    {#if !categories.length}<p>{$t('settings.categoriesLoading')}</p>{:else if !filtered.length}<p>{$t('settings.noCategories')}</p>{/if}
    <VirtualStack items={filtered} height={()=>52} key={category=>category.key} scrollSelector=".settings-scroll">
      {#snippet children(category)}
        {@const index=ordered.findIndex(c=>c.key===category.key)}
        {@const title=providerHeading(category.title,$language)}
        <!-- svelte-ignore a11y_no_static_element_interactions -->
        <div class="setting-row category" ondragover={event=>{if(dragCategory)event.preventDefault();}} ondrop={event=>dropCategory(event,category.key)}>
          <label><input type="checkbox" aria-label={$t('windows.settings.showCategory', [title])} checked={!settings.hiddenCategoryKeys.includes(category.key)} onchange={event=>toggleCategory(category.key,event.currentTarget.checked)} /><span title={title}>{title}</span></label>
          <button type="button" aria-label={$t('settings.up', [title])} disabled={index===0} onclick={()=>moveCategory(category.key,index-1)}>↑</button><button type="button" aria-label={$t('settings.down', [title])} disabled={index===ordered.length-1} onclick={()=>moveCategory(category.key,index+1)}>↓</button>
          <button type="button" class="handle" draggable="true" aria-label={$t('settings.dragAX', [title])} ondragstart={event=>{dragCategory=category.key;event.dataTransfer?.setData('text/plain',category.key);}} ondragend={()=>dragCategory=null}>⠿</button>
        </div>
      {/snippet}
    </VirtualStack>
    <button type="button" class="text-action" onclick={()=>onChange({...settings,hiddenCategoryKeys:[]})}>{$t('settings.showAll')}</button>
    <button type="button" class="text-action" onclick={()=>onChange({...settings,categoryOrderMode:'youtube',categoryOrder:[]})}>{$t('settings.youtubeOrder')}</button>
    <button type="button" class="text-action" onclick={()=>onChange({...settings,categoryOrderMode:'sideB',categoryOrder:[]})}>{$t('settings.restoreOrder')}</button></section>
  </div>
</aside>
<style>
  .settings { box-sizing:border-box; position:fixed; z-index:45; top:116px; right:16px; bottom:116px; width:min(292px,calc(100vw - var(--sidebar-width) - 24px)); display:flex; flex-direction:column; color:#f7f7fa; background:var(--sideb-acrylic-surface); backdrop-filter:var(--sideb-acrylic-blur); border:1px solid var(--sideb-surface-border); border-radius:14px; box-shadow:0 16px 50px #0007; }
  header { display:flex; align-items:center; justify-content:space-between; padding:14px; gap:8px; } h2 { margin:0; font-size:14px; } header button { font-size:23px; }
  .settings-scroll { overflow-y:auto; min-height:0; padding:0 12px 16px; } section+section { margin-top:24px; } h3 { font-size:14px; margin:8px 0; } p { font-size:12px; color:#b9b9c4; line-height:17px; }
  button { border:0; border-radius:6px; background:transparent; color:inherit; cursor:pointer; font:inherit; } button:hover:not(:disabled) { background:#ffffff14; } button:disabled { opacity:.3; cursor:default; }
  .kinds { display:flex; border-radius:8px; padding:3px; background:#0003; } .kinds button { flex:1; padding:6px 3px; font-size:12px; } [aria-pressed='true'] { background:#ffffff24; }
  .setting-row { display:flex; align-items:center; gap:2px; min-height:44px; } .setting-row button { width:22px; height:28px; flex:none; font-size:13px; } .setting-row .handle { width:18px; cursor:grab; }
  label { display:flex; align-items:center; gap:7px; min-width:0; flex:1; font-size:12px; } label span { overflow:hidden; text-overflow:ellipsis; } input[type=checkbox] { accent-color:var(--sideb-accent); flex:none; }
  .category { height:52px; } .category label span { white-space:nowrap; } .filter { width:100%; box-sizing:border-box; margin:5px 0 8px; padding:8px; border:1px solid #fff3; border-radius:7px; background:#0003; color:white; }
  .text-action { display:block; font-size:12px; padding:7px 4px; text-align:left; } .error { color:#ffb9c0; }
  button:focus-visible,input:focus-visible { outline:2px solid var(--sideb-highlight); outline-offset:2px; }
  @media (prefers-reduced-transparency:reduce) { .settings { background:#24242a; backdrop-filter:none; } }
</style>
