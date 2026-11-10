<script lang="ts">
  import { t, language } from '$lib/i18n';
  import { providerHeading } from '$lib/i18n/presentation';
  import { defaults, move, normalized, orderCategories, type CollectionKind, type HomeSettings } from '$lib/home/settings';
  import ControlButton from '../common/ControlButton.svelte';
  import ControlSegments from '../common/ControlSegments.svelte';
  import VirtualStack from '../common/VirtualStack.svelte';
  import SettingsGroup from './SettingsGroup.svelte';
  import SettingsRow from './SettingsRow.svelte';
  import SettingsSwitch from './SettingsSwitch.svelte';
  interface Category { key: string; title: string }
  interface Props { settings: HomeSettings; kind: CollectionKind; categories: Category[]; libraryError: string | null; onChange: (settings: HomeSettings) => void; onKind: (kind: CollectionKind) => void; onRetryLibrary: () => void; scrollSelector: string }
  let { settings, kind, categories, libraryError, onChange, onKind, onRetryLibrary, scrollSelector }: Props = $props();
  let query = $state(''); let dragSource: number | null = null; let dragCategory: string | null = null;
  $effect(() => { kind; dragSource = null; });
  const field = $derived(kind === 'albums' ? 'albumSources' : 'playlistSources');
  const sources = $derived(settings[field]);
  const ordered = $derived(settings.categoryOrderMode === 'custom' ? [...categories].sort((a, b) => { const rank = (key: string) => { const i = settings.categoryOrder.indexOf(key); return i < 0 ? 1e9 : i; }; return rank(a.key) - rank(b.key); }) : categories);
  const filtered = $derived(ordered.filter(category => normalized(category.title).includes(normalized(query)) || normalized(providerHeading(category.title, $language)).includes(normalized(query))));
  const orderDescription = $derived($t(settings.categoryOrderMode === 'youtube' ? 'settings.orderYouTube' : settings.categoryOrderMode === 'custom' ? 'settings.orderCustom' : 'settings.orderSideB'));
  function moveSource(from: number, to: number) { onChange({ ...settings, [field]: move(sources, from, to) }); }
  function moveCategory(key: string, to: number) { onChange(orderCategories(settings, move(ordered.map(category => category.key), ordered.findIndex(category => category.key === key), to))); }
  function toggleCategory(key: string, show: boolean) { onChange({ ...settings, hiddenCategoryKeys: show ? settings.hiddenCategoryKeys.filter(k => k !== key) : [...settings.hiddenCategoryKeys, key] }); }
  function dropSource(event: DragEvent, to: number) { event.preventDefault(); if (dragSource !== null) moveSource(dragSource, to); dragSource = null; }
  function dropCategory(event: DragEvent, key: string) { event.preventDefault(); if (dragCategory) moveCategory(dragCategory, ordered.findIndex(category => category.key === key)); dragCategory = null; }
</script>
{#snippet moveButtons(title: string, index: number, count: number, up: () => void, down: () => void)}
  <button type="button" class="step" aria-label={$t('settings.up', [title])} disabled={index === 0} onclick={up}><svg viewBox="0 0 12 12" aria-hidden="true"><path d="M2.5 7.5 6 4l3.5 3.5" /></svg></button>
  <button type="button" class="step" aria-label={$t('settings.down', [title])} disabled={index >= count - 1} onclick={down}><svg viewBox="0 0 12 12" aria-hidden="true"><path d="M2.5 4.5 6 8l3.5-3.5" /></svg></button>
{/snippet}
<div class="stack">
  <SettingsGroup title={$t('settings.featured')}>
    <SettingsRow title={$t('settings.featuredKind')}>
      {#snippet children()}
        <ControlSegments id="settings-featured-kind" appearance="toolbar" label={$t('settings.featuredKind')} value={kind} onChange={onKind}
          options={[{ id: 'albums', label: $t('sidebar.albums') }, { id: 'playlists', label: $t('windows.ui.playlists') }]} />
      {/snippet}
    </SettingsRow>
  </SettingsGroup>
  <div class="columns">
    <SettingsGroup title={$t('windows.settings.group.sources')} footer={$t('settings.sourcesHint')}>
      {#each sources as row, index (row.source)}
        {@const title = $t('settings.source.' + row.source)}
        <!-- svelte-ignore a11y_no_static_element_interactions -->
        <div class="line" ondragover={event => { if (dragSource !== null) event.preventDefault(); }} ondrop={event => dropSource(event, index)}>
          <button type="button" class="handle" draggable="true" aria-label={$t('settings.dragAX', [title])} title={$t('settings.drag', [title])}
            ondragstart={event => { dragSource = index; event.dataTransfer?.setData('text/plain', row.source); }} ondragend={() => dragSource = null}><svg viewBox="0 0 12 12" aria-hidden="true"><path d="M2 3.5h8M2 6h8M2 8.5h8" /></svg></button>
          <span class="name" id={`source-${row.source}`}>{title}</span>
          {@render moveButtons(title, index, sources.length, () => moveSource(index, index - 1), () => moveSource(index, index + 1))}
          <SettingsSwitch labelledby={`source-${row.source}`} checked={row.enabled}
            onChange={enabled => onChange({ ...settings, [field]: sources.map(r => r.source === row.source ? { ...r, enabled } : r) })} />
        </div>
      {/each}
      {#if !sources.some(s => s.enabled)}<p class="note" role="status">{$t('settings.enableSource')}</p>{/if}
      {#if libraryError}
        <div class="note-row"><p class="error" role="alert">{$t('settings.libraryError')}</p><ControlButton size="utility" onclick={onRetryLibrary}>{$t('settings.retryLibrary')}</ControlButton></div>
      {/if}
      <div class="actions"><ControlButton size="utility" onclick={() => onChange({ ...settings, [field]: defaults()[field] })}>{$t('settings.restoreSources')}</ControlButton></div>
    </SettingsGroup>
    <SettingsGroup title={$t('settings.categories')} footer={`${$t('settings.categoriesHint')}\n${orderDescription}`}>
      {#if categories.length > 8}
        <div class="filter"><svg viewBox="0 0 16 16" aria-hidden="true"><circle cx="7" cy="7" r="4.5" /><path d="m10.5 10.5 3 3" /></svg>
          <input type="search" aria-label={$t('settings.searchCategory')} placeholder={$t('settings.searchCategory')} bind:value={query} /></div>
      {/if}
      {#if !categories.length}<p class="note">{$t('settings.categoriesLoading')}</p>{:else if !filtered.length}<p class="note">{$t('settings.noCategories')}</p>{/if}
      {#if filtered.length}
        <div class="virtual" data-flush>
          <VirtualStack items={filtered} height={() => 49} key={category => category.key} {scrollSelector}>
            {#snippet children(category)}
              {@const index = ordered.findIndex(c => c.key === category.key)}
              {@const title = providerHeading(category.title, $language)}
              <!-- svelte-ignore a11y_no_static_element_interactions -->
              <div class="line category" ondragover={event => { if (dragCategory) event.preventDefault(); }} ondrop={event => dropCategory(event, category.key)}>
                <button type="button" class="handle" draggable="true" aria-label={$t('settings.dragAX', [title])} title={$t('settings.drag', [title])}
                  ondragstart={event => { dragCategory = category.key; event.dataTransfer?.setData('text/plain', category.key); }} ondragend={() => dragCategory = null}><svg viewBox="0 0 12 12" aria-hidden="true"><path d="M2 3.5h8M2 6h8M2 8.5h8" /></svg></button>
                <span class="name" title={title}>{title}</span>
                {@render moveButtons(title, index, ordered.length, () => moveCategory(category.key, index - 1), () => moveCategory(category.key, index + 1))}
                <SettingsSwitch label={$t('windows.settings.showCategory', [title])} checked={!settings.hiddenCategoryKeys.includes(category.key)} onChange={show => toggleCategory(category.key, show)} />
              </div>
            {/snippet}
          </VirtualStack>
        </div>
      {/if}
      <div class="actions wrap">
        <ControlButton size="utility" onclick={() => onChange({ ...settings, hiddenCategoryKeys: [] })}>{$t('settings.showAll')}</ControlButton>
        <ControlButton size="utility" onclick={() => onChange({ ...settings, categoryOrderMode: 'youtube', categoryOrder: [] })}>{$t('settings.youtubeOrder')}</ControlButton>
        <ControlButton size="utility" onclick={() => onChange({ ...settings, categoryOrderMode: 'sideB', categoryOrder: [] })}>{$t('settings.restoreOrder')}</ControlButton>
      </div>
    </SettingsGroup>
  </div>
</div>
<style>
  .stack { display:flex; flex-direction:column; gap:24px; min-width:0; }
  /* Two columns when the detail pane is wide enough for two readable lists (Apple: ViewThatFits at 2 x 400). */
  .columns { display:grid; grid-template-columns:minmax(0,1fr); gap:24px; align-items:start; min-width:0; }
  @container settings-detail (min-width:896px) { .columns { grid-template-columns:repeat(2,minmax(0,1fr)); } }
  .line { display:flex; align-items:center; gap:8px; min-width:0; min-height:28px; }
  .category { box-sizing:border-box; height:49px; padding:0 14px; border-bottom:1px solid rgb(255 255 255 / 8%); }
  .virtual + .actions { border-top:0; }
  .name { flex:1 1 auto; min-width:0; overflow:hidden; text-overflow:ellipsis; white-space:nowrap; font-size:13px; line-height:18px; }
  button { border:0; color:inherit; font:inherit; cursor:pointer; }
  .handle, .step { display:inline-flex; align-items:center; justify-content:center; flex:none; padding:0; border-radius:6px; background:transparent; color:var(--control-muted, #c3c3cb); }
  .handle { width:20px; height:26px; cursor:grab; opacity:.8; }
  .step { width:24px; height:24px; }
  .handle:hover, .step:hover:not(:disabled) { background:rgb(255 255 255 / 10%); color:#fff; }
  .step:disabled { opacity:.3; cursor:default; }
  svg { width:12px; height:12px; fill:none; stroke:currentColor; stroke-width:1.5; stroke-linecap:round; stroke-linejoin:round; }
  .handle:focus-visible, .step:focus-visible { outline:2px solid var(--sideb-highlight, #d06c70); outline-offset:1px; }
  .note { margin:0; font-size:12px; line-height:17px; color:#f2b66b; }
  .note-row { display:flex; align-items:center; justify-content:space-between; gap:12px; }
  .error { margin:0; font-size:12px; line-height:17px; color:#ffb9c0; }
  .actions { display:flex; justify-content:flex-end; gap:8px; }
  .actions.wrap { flex-wrap:wrap; justify-content:flex-start; }
  .filter { display:flex; align-items:center; gap:8px; color:var(--control-muted, #c3c3cb); }
  .filter svg { width:14px; height:14px; flex:none; }
  .filter input { flex:1; min-width:0; box-sizing:border-box; height:26px; border:0; background:transparent; color:var(--control-foreground, #f3f3f6); font:inherit; font-size:13px; }
  .filter input:focus-visible { outline:2px solid var(--sideb-highlight, #d06c70); outline-offset:2px; border-radius:4px; }
</style>
