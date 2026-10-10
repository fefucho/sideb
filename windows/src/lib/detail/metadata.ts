import type { AlbumDetailDto, SongDto } from '../types';

const normalizedCredit = (value: string | null | undefined) => (value ?? '').trim().normalize('NFD').replace(/[\u0300-\u036f]/g, '').replace(/\s+/g, ' ').toLowerCase();

/** A header destination belongs only to its exact credit. Guest credits and supplied runs remain authoritative. */
export function albumTrackWithCredit<T extends SongDto>(song: T, album: Pick<AlbumDetailDto, 'artist' | 'artistId'>): T {
  const artistId = album.artistId?.trim(); const artist = album.artist?.trim();
  if (!artistId || !artist || song.artistId?.trim() || song.artistRuns?.length) return song;
  if (normalizedCredit(song.artists) && normalizedCredit(song.artists) !== normalizedCredit(artist)) return song;
  return { ...song, artistId, artists: (song.artists ?? '').trim() ? song.artists : artist };
}
