<script lang="ts">
  import type { AlbumDetailDto } from "$lib/types";
  import ArtistCredits from "$lib/components/ArtistCredits.svelte";
  import { createMenuHandlers } from "$lib/menu/hooks";
  interface Props {
    album: AlbumDetailDto; loggedIn: boolean; onPlay: (index: number, shuffle?: boolean) => void;
    onOpenArtist: (id: string) => void; onToggleLibrary: () => Promise<void>;
    onDescription: () => void;
  }
  let { album, loggedIn, onPlay, onOpenArtist, onToggleLibrary, onDescription }: Props = $props();
  const createMenu = createMenuHandlers();
  const menu = createMenu(() => ({ kind: 'album', card: { kind: 'album', id: album.browseId, title: album.title, subtitle: album.artist, thumbnail: album.thumbnail, duration: null }, detail: album }), () => ({ view: 'album_detail', currentId: album.browseId }));
  let imageFailed = $state(false);
  let saving = $state(false);
  let libraryError = $state("");
  const hasDescription = $derived(Boolean(album.description?.trim()));
  const meta = $derived([album.subtitle, album.secondSubtitle ?? `${album.items.length} canciones`].filter(Boolean));

  async function toggleLibrary() {
    if (!loggedIn || saving) return;
    saving = true; libraryError = "";
    try { await onToggleLibrary(); } catch (error) { libraryError = error instanceof Error ? error.message : "No se pudo actualizar la biblioteca."; }
    finally { saving = false; }
  }
</script>

<div class="header">
  {#if album.thumbnail && !imageFailed}
    <img class="artwork" src={album.thumbnail} alt="Portada de {album.title}" onerror={() => imageFailed = true} />
  {:else}
    <div class="artwork placeholder" aria-hidden="true"><span>♫</span></div>
  {/if}
  <div class="info">
    <div class="eyebrow">ÁLBUM</div>
    <h1>{album.title}</h1>
    {#if album.artistRuns?.length || album.artist}<div class="artist-credit-line"><ArtistCredits artistRuns={album.artistRuns} artists={album.artist} artistId={album.artistId} {onOpenArtist} /></div>{/if}
    <div class="metadata">{#each meta as part, i (i)}{#if i > 0}<span aria-hidden="true">·</span>{/if}<span>{part}</span>{/each}</div>
    {#if hasDescription}<button class="description" type="button" aria-label="Leer descripción completa" onclick={onDescription}>{album.description}<span> más</span></button>{/if}
    <div class="actions">
      <button class="primary" type="button" disabled={!album.items.length} onclick={() => onPlay(0)}><span aria-hidden="true">▶</span> Reproducir</button>
      <button type="button" disabled={!album.items.length} onclick={() => onPlay(0, true)}><span aria-hidden="true">⤨</span> Aleatorio</button>
      {#if album.playlistId}
        <button type="button" disabled={!loggedIn || saving} title={loggedIn ? (album.inLibrary ? "Quitar de la biblioteca" : "Guardar en biblioteca") : "Inicia sesión para guardar"} onclick={toggleLibrary}>
          {saving ? "Guardando…" : album.inLibrary ? "▣ En biblioteca" : "▢ Guardar"}
        </button>
      {/if}
      <button type="button" class="more" aria-label="Más opciones" title="Más opciones" aria-haspopup="menu" onclick={menu.onContextMenu} onkeydown={menu.onKeyDown}>•••</button>
    </div>
    {#if libraryError}<p class="error" role="alert">{libraryError}</p>{/if}
  </div>
</div>

<style>
  .header { display: flex; align-items: flex-start; gap: 24px; padding: 28px 32px 16px; color: #f7f7f8; }
  .artwork { flex: none; width: 180px; height: 180px; object-fit: cover; border-radius: 10px; background: #303036; box-shadow: 0 16px 28px #0006; }
  .placeholder { display: grid; place-items: center; background: linear-gradient(145deg, #583036, #29292f 75%); }
  .placeholder span { color: #ddd; font-size: 58px; }
  .info { display: flex; min-width: 0; min-height: 180px; flex: 1; flex-direction: column; align-items: flex-start; }
  .eyebrow { color: #a6a6ad; font-size: 11px; font-weight: 700; letter-spacing: .12em; }
  h1 { margin: 4px 0 3px; max-width: 100%; font-size: 32px; line-height: 1.12; font-weight: 700; }
  .artist-credit-line { min-width: 0; max-width: 100%; color: #f7f7f8; font-size: 16px; font-weight: 650; }
  .metadata { display: flex; flex-wrap: wrap; gap: 6px; margin-top: 5px; color: #aaaab1; font-size: 12px; }
  .description { max-width: min(620px, 100%); margin: 5px 0 0; padding: 0; overflow: hidden; border: 0; color: #aaaab1; background: none; font: inherit; font-size: 12px; line-height: 1.45; text-align: left; display: -webkit-box; -webkit-box-orient: vertical; -webkit-line-clamp: 2; line-clamp: 2; cursor: pointer; }
  .description span { color: #f7f7f8; font-weight: 650; white-space: nowrap; }
  .actions { display: flex; flex-wrap: wrap; align-items: center; gap: 9px; margin-top: auto; }
  .actions > button, .more { min-height: 34px; padding: 0 14px; border: 1px solid rgb(255 255 255 / 10%); border-radius: 999px; color: #f3f3f5; background: rgb(255 255 255 / 6%); font: inherit; font-size: 12px; font-weight: 550; cursor: pointer; }
  .actions > button:hover:not(:disabled), .more:hover { background: rgb(255 255 255 / 12%); }
  .actions > button:disabled { opacity: .45; cursor: not-allowed; }
  .actions > .primary { border-color: transparent; background: var(--sideb-accent, #a33d45); font-weight: 650; }
  .primary span { margin-right: 4px; }
  .more { width: 36px; padding: 0; font-size: 15px; }
  .error { margin: 5px 0 0; color: #ff9d9d; font-size: 12px; }
  button:focus-visible { outline: 2px solid var(--sideb-highlight); outline-offset: 3px; }
  @media (max-width: 680px) { .header { gap: 16px; padding: 22px 18px; } .artwork { width: 128px; height: 128px; } .info { height: auto; min-height: 128px; } h1 { font-size: 24px; } .eyebrow { font-size: 10px; } .artist-credit-line { font-size: 14px; } .actions { margin-top: 14px; } }
  @media (max-width: 480px) { .header { flex-direction: column; } .info { width: 100%; } }
</style>
