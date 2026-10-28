<script lang="ts">
  import { t } from '$lib/i18n';
  import type { Snippet } from 'svelte';
  import ExplicitBadge from '../common/ExplicitBadge.svelte';
  import { contentRating, type ContentMetadata } from '$lib/contentRating';
  let { identity, title, thumbnail, kind, credit, summary, description, onDescription, actions, tools, content }:
    { identity:string;title:string;thumbnail:string|null;kind:string;credit?:Snippet;summary?:string|null;description?:string|null;onDescription?:()=>void;actions:Snippet;tools?:Snippet;content?:ContentMetadata } = $props();
  let failed = $state(false);
  $effect(()=>{identity;thumbnail;failed=false;});
</script>
<header class="collection-header">
  <div class="identity">
  {#if thumbnail&&!failed}<img class="artwork" src={thumbnail} alt={$t('windows.fullscreen.artwork', [title])} onerror={()=>failed=true} />{:else}<div class="artwork placeholder" aria-hidden="true">♫</div>{/if}
  <div class="metadata"><div class="eyebrow">{kind}</div><div class="title-line"><h1>{title}</h1></div>{#if credit || contentRating(content) !== 'unknown'}<div class="credit">{#if content}<ExplicitBadge item={content} />{/if}{#if credit}{@render credit()}{/if}</div>{/if}
    {#if summary}<p class="summary">{summary}</p>{/if}
    {#if description}<button class="description" type="button" aria-label={$t('windows.ui.readFullDescription')} onclick={onDescription}>{description}<span> {$t('detail.more')}</span></button>{/if}
  </div>
  </div>
  <div class="toolbar"><div class="actions">{@render actions()}</div>{#if tools}<div class="tools">{@render tools()}</div>{/if}</div>
</header>
<style>
  .collection-header {container:collection-header / inline-size;display:flex;flex-direction:column;gap:24px;padding:28px 32px 18px;color:#f7f7f8;}
  .identity {display:flex;align-items:flex-start;gap:28px;min-width:0;width:100%;}
  .artwork {width:216px;height:216px;flex:0 0 216px;border-radius:10px;object-fit:cover;background:#303036;box-shadow:0 16px 28px #0006;} .placeholder {display:grid;place-items:center;color:#ddd;font-size:60px;}
  .metadata {display:flex;min-width:0;min-height:216px;flex:1;flex-direction:column;align-items:flex-start;gap:7px;}
  .eyebrow {color:#aaaab1;font-size:12px;font-weight:700;letter-spacing:.12em;} h1 {max-width:100%;margin:0;font-size:38px;line-height:1.12;overflow-wrap:anywhere;display:-webkit-box;-webkit-box-orient:vertical;-webkit-line-clamp:2;line-clamp:2;overflow:hidden;}
  .title-line {display:flex;align-items:center;gap:8px;max-width:100%;min-width:0;}
  .credit {display:flex;align-items:center;gap:4px;min-width:0;max-width:100%;overflow-wrap:anywhere;font-size:18px;font-weight:600;} .summary {margin:0;overflow-wrap:anywhere;color:#aaaab1;font-size:14px;}
  .description {display:-webkit-box;max-width:min(720px,100%);overflow:hidden;padding:0;border:0;color:#aaaab1;background:transparent;font:inherit;font-size:13px;line-height:18px;text-align:left;-webkit-box-orient:vertical;-webkit-line-clamp:2;line-clamp:2;cursor:pointer;} .description span {color:#f1f1f3;font-weight:600;}
  .toolbar {display:flex;flex-wrap:wrap;align-items:center;justify-content:space-between;gap:16px 20px;width:100%;min-width:0;}
  .actions {display:flex;max-width:100%;flex-wrap:wrap;align-items:center;gap:var(--control-action-gap);} .tools {flex:1 1 320px;max-width:520px;min-width:0;margin-left:auto;}
 button:focus-visible {outline:2px solid var(--sideb-highlight);outline-offset:3px;}
  @container collection-header (max-width:760px){.actions {--control-action-padding:12px;--control-action-gap:8px;}}
  @container collection-header (max-width:600px){.identity {gap:20px;}.artwork {width:160px;height:160px;flex-basis:160px;}.metadata {min-height:160px;}h1 {font-size:30px;}.credit {font-size:16px;}.tools {max-width:none;flex-basis:100%;}}
  @container collection-header (max-width:480px){.identity {flex-direction:column;gap:20px;}.metadata {min-height:0;}h1 {font-size:28px;}}
</style>
