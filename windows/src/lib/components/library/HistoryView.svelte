<script lang="ts">
  import type { HistoryGroupDto, AccountSongDto } from '$lib/account/types';
  import AccountTrackTable from './AccountTrackTable.svelte';
  interface Props {
    loggedIn: boolean; groups: HistoryGroupDto[]; loading: boolean; error: string | null;
    currentTrackId: string | null; isPlaying: boolean; likedIds: Set<string>; pendingIds: Set<string>;
    onLogin: () => void; onRefresh: () => void; onPlay: (items: AccountSongDto[], index: number) => void;
    onToggleLike: (song: AccountSongDto) => void; onToggleSaved: (song: AccountSongDto) => void;
    onOpenArtist: (id: string) => void; onOpenAlbum: (id: string) => void;
  }
  let { loggedIn, groups, loading, error, currentTrackId, isPlaying, likedIds, pendingIds,
    onLogin, onRefresh, onPlay, onToggleLike, onToggleSaved, onOpenArtist, onOpenAlbum }: Props = $props();
  const allTracks = $derived(groups.flatMap(group => group.items));
</script>
<section class="history" aria-busy={loading}>
  <header><div><div class="eyebrow">COLECCIÓN</div><h1>Historial</h1><p>Tus reproducciones recientes ordenadas por día</p></div>
    {#if loggedIn}<button type="button" onclick={onRefresh} disabled={loading} aria-label="Actualizar historial">↻</button>{/if}
  </header>
  <div class="divider"></div>
  {#if !loggedIn}<div class="state"><h2>Iniciá sesión para ver tu historial</h2><button type="button" onclick={onLogin}>Iniciar sesión</button></div>
  {:else if loading && !allTracks.length}<div class="state" role="status">Cargando historial…</div>
  {:else if error && !allTracks.length}<div class="state" role="alert"><h2>No se pudo cargar el historial</h2><p>{error}</p><button type="button" onclick={onRefresh}>Reintentar</button></div>
  {:else if !allTracks.length}<div class="state"><h2>No hay reproducciones recientes</h2></div>
  {:else}
    {#if error}<p class="error" role="alert">{error}</p>{/if}
    {#each groups as group, groupIndex (group.title + ':' + groupIndex)}
      {@const offset = groups.slice(0, groupIndex).reduce((sum, item) => sum + item.items.length, 0)}
      <section aria-label={group.title}><h2 class="group-heading">{group.title}</h2>
        <AccountTrackTable items={group.items} {currentTrackId} {isPlaying} {likedIds} {pendingIds} numbered={false}
          onPlay={(index) => onPlay(allTracks, offset + index)} {onToggleLike} {onToggleSaved} {onOpenArtist} {onOpenAlbum} />
      </section>
    {/each}
  {/if}
</section>
<style>
  .history { min-width: 0; padding-bottom: 130px; color: #f7f7f8; }
  header { display: flex; align-items: center; justify-content: space-between; padding: 24px 32px 14px; }
  .eyebrow { font-size: 11px; font-weight: 700; letter-spacing: 1.2px; color: #aaaab1; }
  h1 { margin: 4px 0 0; font-size: 32px; } header p { margin: 6px 0 0; font-size: 13px; color: #aaaab1; }
  .divider { height: 1px; background: #ffffff15; margin: 0 32px 8px; }
  button { border: 0; border-radius: 8px; padding: 8px 14px; color: inherit; background: var(--sideb-surface); font: inherit; cursor: pointer; }
  button:hover { background: var(--sideb-surface-hover); } button:focus-visible { outline: 2px solid var(--sideb-highlight); }
  .state { min-height: 300px; display: flex; flex-direction: column; align-items: center; justify-content: center; gap: 14px; color: #aaaab1; }
  .state h2 { font-size: 17px; } .group-heading { margin: 20px 32px 8px; font-size: 15px; } .error { margin: 14px 32px; color: #ffd5d5; }
</style>
