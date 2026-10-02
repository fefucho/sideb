<script lang="ts">
  import type { BrowseCardDto } from '$lib/types';
  import { createMenuHandlers } from '$lib/menu/hooks';

  interface Props {
    card: BrowseCardDto;
    size: 'artist' | 'album' | 'playlist';
    filtered?: boolean;
    onActivate: () => void;
  }

  let { card, size, filtered = false, onActivate }: Props = $props();
  const createMenu = createMenuHandlers();
  const menu = createMenu(() => ({ kind: size === 'artist' ? 'artist' : size === 'playlist' ? 'playlist' : 'album', card }), { view: 'search_results' });
</script>

<button class="result-card" class:artist={size === 'artist'} class:filtered type="button" onclick={onActivate} oncontextmenu={menu.onContextMenu} onkeydown={menu.onKeyDown} aria-label={`${size === 'artist' ? 'Abrir artista' : size === 'album' ? 'Abrir álbum' : 'Abrir playlist'} ${card.title}`}>
  <span class="artwork" class:round={size === 'artist'}>
    {#if card.thumbnail}<img src={card.thumbnail} alt="" loading="lazy" />{:else}<svg class="fallback-icon" viewBox="0 0 32 32" aria-hidden="true">{#if size === 'artist'}<circle cx="16" cy="10" r="5"/><path d="M5 29c.6-6.5 4.5-10 11-10s10.4 3.5 11 10"/>{:else}<circle cx="16" cy="16" r="12"/><circle cx="16" cy="16" r="3"/>{/if}</svg>{/if}
    <span class="card-action" aria-hidden="true">{#if size === 'artist'}<svg viewBox="0 0 24 24"><path d="M5 12h14m-6-6 6 6-6 6"/></svg>{:else}<svg viewBox="0 0 24 24"><path d="m9 5 10 7-10 7z"/></svg>{/if}</span>
  </span>
  <span class="title">{card.title}</span>
  {#if card.subtitle}<span class="subtitle">{card.subtitle}</span>{/if}
</button>

<style>
  .result-card { display:flex; width:144px; flex:none; flex-direction:column; align-items:flex-start; gap:5px; padding:0; border:0; border-radius:9px; background:transparent; color:inherit; text-align:left; cursor:pointer; }
  .result-card.artist { width:130px; }
  .result-card.filtered { width:100%; max-width:180px; }
  .artwork { position:relative; display:grid; width:144px; height:144px; place-items:center; overflow:hidden; border-radius:10px; background:rgb(255 255 255 / 7%); color:rgb(255 255 255 / 44%); font-size:30px; }
  .artist .artwork { width:130px; height:130px; border-radius:50%; }
  .filtered .artwork { width:100%; height:auto; aspect-ratio:1; }
  .artwork.round { border-radius:50%; }
  .artwork img { width:100%; height:100%; object-fit:cover; }
  .fallback-icon { width:32px; height:32px; fill:none; stroke:currentColor; stroke-width:1.4; stroke-linecap:round; stroke-linejoin:round; }
  .card-action { position:absolute; right:6px; bottom:6px; display:grid; width:26px; height:26px; place-items:center; border-radius:50%; background:rgb(25 25 28 / 83%); color:#fff; opacity:0; transform:translateY(3px); transition:opacity .15s ease, transform .15s ease; }
  .card-action svg { width:15px; height:15px; fill:none; stroke:currentColor; stroke-width:1.8; stroke-linecap:round; stroke-linejoin:round; }
  .result-card:hover .card-action, .result-card:focus-visible .card-action { opacity:1; transform:none; }
  .title { display:block; max-width:100%; overflow:hidden; color:rgb(255 255 255 / 91%); font-size:12.5px; font-weight:550; text-overflow:ellipsis; white-space:nowrap; }
  .subtitle { display:block; max-width:100%; overflow:hidden; color:rgb(255 255 255 / 57%); font-size:11px; text-overflow:ellipsis; white-space:nowrap; }
  .result-card:hover .title { color:#fff; }
  .result-card:hover .artwork { outline:1px solid rgb(255 255 255 / 18%); }
  .result-card:focus-visible { outline:2px solid var(--sideb-highlight, #d06c70); outline-offset:4px; }
</style>
