<script lang="ts">
  import type { Snippet } from 'svelte';
  interface Props { title?: string; footer?: string; children: Snippet }
  let { title, footer, children }: Props = $props();
  const id = $props.id();
</script>
<section class="group" aria-labelledby={title ? `${id}-title` : undefined} aria-describedby={footer ? `${id}-footer` : undefined}>
  {#if title}<h3 id={`${id}-title`}>{title}</h3>{/if}
  <div class="rows">{@render children()}</div>
  {#if footer}<p id={`${id}-footer`} class="footer">{footer}</p>{/if}
</section>
<style>
  .group { display:flex; flex-direction:column; gap:7px; min-width:0; }
  /* Apple-style grouped list: one rounded surface, hairline separators between consecutive rows. */
  .rows { overflow:hidden; border:1px solid rgb(255 255 255 / 6%); border-radius:10px; background:rgb(255 255 255 / 5.5%); }
  .rows > :global(:not([data-flush])) { padding:10px 14px; }
  .rows > :global(:not(:first-child)) { border-top:1px solid rgb(255 255 255 / 8%); }
  /* A section component that renders nothing (not installed, unavailable) must not leave an empty card. */
  .group:has(.rows > :global(.slot:only-child:empty)) { display:none; }
  h3 { margin:0; padding:0 4px; font-size:12px; font-weight:500; line-height:16px; color:var(--control-muted, #c3c3cb); }
  .footer { margin:0; padding:0 4px; font-size:11.5px; line-height:16px; color:var(--control-muted, #c3c3cb); white-space:pre-line; }
</style>
