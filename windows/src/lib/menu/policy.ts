import type { MenuAction, MenuFacts, MenuIconName, MenuItem, MenuOrigin, MenuTarget } from './types';

/** Mirrors macOS MenuPolicy: availability is based on known capabilities, not guesses about ownership. */
export function menuItems(target: MenuTarget, origin: MenuOrigin, facts: MenuFacts, localize: (ownText: string) => string = value => value): MenuItem[] {
  const result: MenuItem[] = [];
  const iconFor = (id: MenuAction['type']): MenuIconName => {
    switch (id) {
      case 'play': return target.kind === 'playlist' && target.card.id.replace(/^VL/, '').startsWith('RD') ? 'radio' : 'play';
      case 'shuffle': return 'shuffle';
      case 'radio': return 'radio';
      case 'enqueue-next': return 'queue-next';
      case 'enqueue-end': return 'queue-end';
      case 'like': return target.kind === 'song' && facts.likedIds.has(target.song.videoId) ? 'heart-remove' : 'heart';
      case 'save-song': return target.kind === 'song' && target.song.library?.inLibrary ? 'bookmark-fill' : 'bookmark';
      case 'save-collection': return target.kind !== 'song' && target.detail && 'inLibrary' in target.detail && target.detail.inLibrary ? 'bookmark-fill' : 'bookmark';
      case 'subscribe': return target.kind === 'artist' && target.detail?.subscribed ? 'bell-off' : 'bell';
      case 'open': return target.kind === 'album' ? 'disc' : target.kind === 'artist' ? 'person' : target.kind === 'playlist' && target.card.id.replace(/^VL/, '').startsWith('RD') ? 'radio' : 'music-list';
      case 'open-album': return 'disc';
      case 'open-artist': return 'person';
      case 'share': return 'share';
      case 'remove-playlist': case 'delete-playlist': return 'trash';
      case 'remove-queue': return 'minus';
      case 'edit-playlist': return 'edit';
      case 'new-playlist': return 'plus';
      case 'sort-playlist': return 'sort';
    }
    return 'music-list';
  };
  const add = (id: MenuAction['type'], label: string, disabled = false, checked?: boolean) => result.push({ id, label: localize(label), icon: iconFor(id), disabled, checked, action: { type: id } as MenuAction });
  const group = () => { if (result.length && !result.at(-1)?.separator) result.push({ id: `separator-${result.length}`, label: '', separator: true }); };
  const auth = !facts.loggedIn;
  if (target.kind === 'song') {
    const { song, entryId } = target;
    const current = !!origin.nowPlaying || !!entryId && entryId === origin.currentQueueEntryId;
    if (!origin.nowPlaying && !current) add('play', 'Reproducir ahora');
    if (song.videoId) add('radio', 'Iniciar radio');
    if (!current) add('enqueue-next', 'Reproducir a continuación');
    add('enqueue-end', 'Agregar a la cola'); group();
    add('like', facts.likedIds.has(song.videoId) ? 'Quitar Me gusta' : 'Me gusta', auth);
    const token = song.library?.inLibrary ? song.library.removeToken : song.library?.addToken;
    if (token) add('save-song', song.library?.inLibrary ? 'Quitar de la biblioteca' : 'Guardar en biblioteca', auth);
    const children: MenuItem[] = facts.playlists.filter(card => !card.id.replace(/^VL/, '').startsWith('RD') && card.id.replace(/^VL/, '') !== 'LM')
      .map(card => ({ id: `add-${card.id}`, label: card.title, icon: 'music-list' as const, action: { type: 'add-to-playlist', playlistId: card.id } }));
    children.push({ id: 'new-playlist', label: localize('Nueva playlist…'), icon: 'plus', action: { type: 'new-playlist' } });
    result.push({ id: 'add-playlist', label: localize('Agregar a playlist'), icon: 'list-add', disabled: auth, children }); group();
    if (song.albumId && !(origin.view === 'album_detail' && origin.currentId === song.albumId)) add('open-album', 'Ir al álbum');
    if (song.artistId && !(origin.view === 'artist_detail' && origin.currentId === song.artistId)) add('open-artist', 'Ir al artista');
    add('share', 'Copiar enlace');
    if (origin.playlistOwned && origin.playlistId && song.setVideoId) { group(); add('remove-playlist', 'Quitar de esta playlist', auth); }
    if (entryId && !current) { group(); add('remove-queue', 'Quitar de la cola'); }
    return result;
  }
  const id = target.card.id.replace(/^VL/, '');
  if (target.kind === 'artist') {
    if (!target.detail || target.detail.radioPlaylistId) add('radio', 'Iniciar radio');
    // A card has no subscription capability until its full profile has been loaded.
    if (target.detail) add('subscribe', target.detail.subscribed ? 'Cancelar suscripción' : 'Suscribirse', auth);
    if (!(origin.view === 'artist_detail' && origin.currentId === id)) add('open', 'Ir al artista');
    group(); add('share', 'Copiar enlace'); return result;
  }
  const dynamic = target.kind === 'playlist' && id.startsWith('RD');
  add('play', dynamic ? 'Reproducir mix' : 'Reproducir');
  if (!dynamic) {
    add('shuffle', 'Aleatorio');
    add('radio', 'Iniciar radio');
    add('enqueue-next', 'Reproducir a continuación');
    add('enqueue-end', 'Agregar a la cola');
  }
  const detail = target.detail;
  const canSave = detail && id !== 'LM' && (target.kind !== 'album' || target.detail?.playlistId) && !(target.kind === 'playlist' && target.detail?.owned);
  if (canSave) { group(); add('save-collection', detail.inLibrary ? 'Quitar de la biblioteca' : 'Guardar en biblioteca', auth); }
  group();
  const view = target.kind === 'album' ? 'album_detail' : 'playlist_detail';
  if (!(origin.view === view && origin.currentId?.replace(/^VL/, '') === id)) add('open', target.kind === 'album' ? 'Ir al álbum' : dynamic ? 'Ver mix' : 'Ir a la playlist');
  if (target.kind === 'album' && target.detail?.artistId) add('open-artist', 'Ir al artista');
  add('share', 'Copiar enlace');
  if (target.kind === 'playlist' && target.detail?.owned && id !== 'LM' && !dynamic) {
    group(); add('edit-playlist', 'Editar detalles…', auth);
    if (target.detail.sortEditable) {
      result.push({ id: 'sort-playlist', label: localize('Ordenar por'), icon: 'sort', disabled: auth, children: [
        ['default', 'Orden manual', 'reorder'], ['newest', 'Más recientes', 'history'], ['oldest', 'Más antiguas', 'clock'], ['title', 'Título', 'text'], ['artist', 'Artista', 'person'], ['album', 'Álbum', 'disc'],
      ].map(([sort, label, icon]) => ({ id: `sort-${sort}`, label: localize(label), icon: icon as MenuIconName, checked: (target.detail?.sort ?? 'default') === sort, action: { type: 'sort-playlist', sort } })) });
    }
    add('delete-playlist', 'Eliminar playlist…', auth);
  }
  return result;
}
