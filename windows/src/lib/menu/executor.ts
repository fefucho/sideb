import type { AlbumDetailDto, ArtistDetailDto, PlaylistDetailDto, SongDto } from '../types';
import type { MenuAction, MenuOrigin, MenuTarget } from './types';

export interface MenuExecutorPorts {
  rpc: <T>(command: string, args?: Record<string, unknown>) => Promise<T>;
  // Captured when the action starts; async bulk loads cannot override later navigation/play/account intent.
  begin: (playIntent: boolean) => () => boolean;
  resolvePlaylist: (id: string, valid: () => boolean) => Promise<SongDto[]>;
  play: (songs: SongDto[], source: { kind: string; id: string; title: string }, shuffle: boolean, artwork: string | null) => Promise<void>;
  radio: (song: SongDto) => Promise<void>;
  enqueue: (songs: SongDto[], position: 'next' | 'end') => Promise<void>;
  removeQueue: (entryId: string) => Promise<void>;
  like: (song: SongDto) => Promise<void>;
  saveSong: (song: SongDto) => Promise<void>;
  addPlaylist: (id: string, song: SongDto) => Promise<void>;
  removePlaylistSong: (id: string, song: SongDto) => Promise<void>;
  sortPlaylist: (id: string, sort: string) => Promise<void>;
  saveCollection: (target: MenuTarget) => Promise<void>;
  subscribe: (artist: ArtistDetailDto) => Promise<void>;
  open: (kind: 'album' | 'artist' | 'playlist', id: string) => void | Promise<void>;
  editPlaylist: (playlist: PlaylistDetailDto) => void;
  deletePlaylist: (playlist: PlaylistDetailDto) => void;
  newPlaylist: (song: SongDto) => void;
  copy: (url: string) => Promise<void>;
}

export class MenuExecutor {
  constructor(private ports: MenuExecutorPorts) {}
  async execute(action: MenuAction, target: MenuTarget, origin: MenuOrigin) {
    const p = this.ports;
    const valid = p.begin(['play', 'shuffle', 'radio'].includes(action.type));
    const id = target.kind === 'song' ? target.song.videoId : target.card.id;
    if (action.type === 'share') {
      const canonical = id.replace(/^VL/, '');
      const url = target.kind === 'song' ? `https://music.youtube.com/watch?v=${encodeURIComponent(id)}`
        : target.kind === 'playlist' ? `https://music.youtube.com/playlist?list=${encodeURIComponent(canonical)}`
        : target.kind === 'album' && target.detail?.playlistId ? `https://music.youtube.com/playlist?list=${encodeURIComponent(target.detail.playlistId.replace(/^VL/, ''))}`
        : `https://music.youtube.com/browse/${encodeURIComponent(id)}`;
      await p.copy(url); return;
    }
    if (action.type === 'open' && target.kind !== 'song') { await p.open(target.kind, id); return; }
    if (action.type === 'open-album' && target.kind === 'song' && target.song.albumId) { await p.open('album', target.song.albumId); return; }
    if (action.type === 'open-artist') {
      const artistId = target.kind === 'song' ? target.song.artistId : target.kind === 'album' ? target.detail?.artistId : null;
      if (artistId) await p.open('artist', artistId); return;
    }
    if (action.type === 'save-collection') { await p.saveCollection(target); return; }
    if (action.type === 'subscribe' && target.kind === 'artist' && target.detail) { await p.subscribe(target.detail); return; }
    if (target.kind === 'playlist' && target.detail) {
      if (action.type === 'edit-playlist') { p.editPlaylist(target.detail); return; }
      if (action.type === 'delete-playlist') { p.deletePlaylist(target.detail); return; }
      if (action.type === 'sort-playlist') { await p.sortPlaylist(id, action.sort); return; }
    }
    if (target.kind === 'song') {
      if (action.type === 'like') { await p.like(target.song); return; }
      if (action.type === 'save-song') { await p.saveSong(target.song); return; }
      if (action.type === 'add-to-playlist') { await p.addPlaylist(action.playlistId, target.song); return; }
      if (action.type === 'new-playlist') { p.newPlaylist(target.song); return; }
      if (action.type === 'remove-playlist' && origin.playlistId) { await p.removePlaylistSong(origin.playlistId, target.song); return; }
      if (action.type === 'remove-queue' && target.entryId) { await p.removeQueue(target.entryId); return; }
    }
    let tracks: SongDto[] = [];
    let title = target.kind === 'song' ? target.song.title : target.card.title;
    let artwork = target.kind === 'song' ? target.song.thumbnail : target.card.thumbnail;
    if (target.kind === 'song') tracks = [target.song];
    if (target.kind === 'album') {
      const album = target.detail ?? await p.rpc<AlbumDetailDto>('get_album', { browseId: id });
      if (!valid()) return;
      tracks = album.items.map(song => ({ ...song, artists: song.artists || album.artist || '', thumbnail: song.thumbnail || album.thumbnail,
        albumId: song.albumId || album.browseId, album: song.album || album.title, artistId: song.artistId || album.artistId }));
      title = album.title; artwork = album.thumbnail;
    }
    if (target.kind === 'playlist') {
      tracks = id.replace(/^VL/, '').startsWith('RD')
        ? await p.rpc<SongDto[]>('get_artist_radio', { playlistId: id.replace(/^VL/, '') })
        : await p.resolvePlaylist(id, valid);
    }
    if (target.kind === 'artist' && action.type === 'radio') {
      const artist = target.detail ?? await p.rpc<ArtistDetailDto>('get_artist', { browseId: id });
      if (!valid()) return;
      if (!artist.radioPlaylistId) throw new Error('Este artista no ofrece una radio disponible.');
      tracks = await p.rpc<SongDto[]>('get_artist_radio', { playlistId: artist.radioPlaylistId });
    }
    if (!valid()) return;
    if (!tracks.length) throw new Error('No hay canciones disponibles para esta acción.');
    if (action.type === 'radio') { await p.radio(tracks[0]); return; }
    if (action.type === 'enqueue-next' || action.type === 'enqueue-end') { await p.enqueue(tracks, action.type === 'enqueue-next' ? 'next' : 'end'); return; }
    if (action.type === 'play' || action.type === 'shuffle') { await p.play(tracks, { kind: target.kind, id, title }, action.type === 'shuffle', artwork); return; }
    throw new Error('Esta acción no está disponible en este contexto.');
  }
}
