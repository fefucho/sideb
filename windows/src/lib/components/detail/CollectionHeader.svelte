<script lang="ts">
  import { t } from '$lib/i18n';
  import type { Snippet } from 'svelte';
  let { identity, title, thumbnail, kind, credit, summary, description, onDescription, actions, tools }:
    { identity:string;title:string;thumbnail:string|null;kind:string;credit?:Snippet;summary?:string|null;description?:string|null;onDescription?:()=>void;actions:Snippet;tools?:Snippet } = $props();
  let failed = $state(false);
  $effect(()=>{identity;thumbnail;failed=false;});
</script>
<header class="collection-header">
  {#if thumbnail&&!failed}<img class="artwork" src={thumbnail} alt={$t('windows.fullscreen.artwork', [title])} onerror={()=>failed=true} />{:else}<div class="artwork placeholder" aria-hidden="true">♫</div>{/if}
  <div class="metadata"><div class="eyebrow">{kind}</div><h1>{title}</h1>{#if credit}<div class="credit">{@render credit()}</div>{/if}
    {#if summary}<p class="summary">{summary}</p>{/if}
    {#if description}<button class="description" type="button" aria-label={$t('windows.ui.readFullDescription')} onclick={onDescription}>{description}<span> {$t('detail.more')}</span></button>{/if}
    <div class="toolbar"><div class="actions">{@render actions()}</div>{#if tools}<div class="tools">{@render tools()}</div>{/if}</div>
  </div>
</header>
<style>
  .collection-header {display:flex;align-items:flex-start;gap:28px;padding:28px 32px 18px;color:#f7f7f8;}
  .artwork {width:216px;height:216px;flex:0 0 216px;border-radius:10px;object-fit:cover;background:#303036;box-shadow:0 16px 28px #0006;} .placeholder {display:grid;place-items:center;color:#ddd;font-size:60px;}
  .metadata {display:flex;min-width:0;min-height:216px;flex:1;flex-direction:column;align-items:flex-start;gap:7px;}
  .eyebrow {color:#aaaab1;font-size:12px;font-weight:700;letter-spacing:.12em;} h1 {max-width:100%;margin:0;font-size:38px;line-height:1.12;overflow-wrap:anywhere;display:-webkit-box;-webkit-box-orient:vertical;-webkit-line-clamp:2;line-clamp:2;overflow:hidden;}
  .credit {min-width:0;max-width:100%;font-size:18px;font-weight:600;} .summary {margin:0;color:#aaaab1;font-size:14px;}
  .description {display:-webkit-box;max-width:min(720px,100%);overflow:hidden;padding:0;border:0;color:#aaaab1;background:transparent;font:inherit;font-size:13px;line-height:18px;text-align:left;-webkit-box-orient:vertical;-webkit-line-clamp:2;line-clamp:2;cursor:pointer;} .description span {color:#f1f1f3;font-weight:600;}
  .toolbar {display:flex;flex-wrap:wrap;align-items:center;justify-content:space-between;gap:12px 20px;width:100%;margin-top:auto;padding-top:12px;}
  .actions {display:flex;flex-wrap:wrap;align-items:center;gap:9px;} .tools {flex:1 1 380px;max-width:520px;min-width:0;margin-left:auto;}
  .actions :global(button) {min-height:38px;border-radius:999px;} button:focus-visible {outline:2px solid var(--sideb-highlight);outline-offset:3px;}
  @media(max-width:680px){.collection-header {gap:16px;padding:22px 18px;}.artwork {width:128px;height:128px;flex-basis:128px;}.metadata {min-height:128px;}h1 {font-size:26px;}.credit {font-size:15px;}.toolbar {margin-top:4px;}.tools {max-width:none;flex-basis:100%;}}
  @media(max-width:480px){.collection-header {flex-direction:column;}.metadata {min-height:0;}}
</style>
