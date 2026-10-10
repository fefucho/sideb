import type { AlbumDetailDto, HomeItemDto, PlaylistDetailDto } from '../types';
export interface FeaturedMetadata { title: string; summary: string; artists: string | null; artistId: string | null }
export type CollectionDetail = AlbumDetailDto | PlaylistDetailDto;
const clean = (value: string | null | undefined) => value?.trim() || null;
const parts = (value: string | null | undefined) => (value ?? '').split(/[•·]/).map(clean).filter((part): part is string => part !== null);
const year = (value: string | null | undefined) => value?.match(/(?<!\d)(?:19|20)\d{2}(?!\d)/)?.[0] ?? null;

export type AlbumCollectionType = 'album' | 'single' | 'ep';
/** Use a real leading provider component. Track counts never determine a release type. */
export function albumCollectionType(item: Pick<HomeItemDto, 'subtitle'>, detail?: Pick<AlbumDetailDto, 'subtitle'> | null): AlbumCollectionType {
  for (const subtitle of [detail?.subtitle, item.subtitle]) {
    const prefix = parts(subtitle)[0]?.normalize('NFD').replace(/[\u0300-\u036f]/g, '').toLowerCase();
    if (prefix === 'single' || prefix === 'sencillo') return 'single';
    if (prefix === 'ep') return 'ep';
    if (prefix === 'album') return 'album';
  }
  return 'album';
}

/** HomeCollectionMetadataFormatting: reject malformed and incomplete duration totals. */
export function durationSeconds(raw: string | null | undefined): number | null {
  const value = clean(raw);
  if (!value) return null;
  if (/^\d+$/.test(value)) return Number.isSafeInteger(Number(value)) ? Number(value) : null;
  if (!/^\d+:\d+(?::\d+)?$/.test(value)) return null;
  const values = value.split(':').map(Number);
  if (values.slice(1).some(number => number >= 60)) return null;
  const total = values.reduce((sum, number) => sum * 60 + number, 0);
  return Number.isSafeInteger(total) ? total : null;
}
export function formatDuration(seconds: number): string {
  const hours = Math.floor(seconds / 3600), minutes = Math.floor(seconds % 3600 / 60);
  return hours ? `${hours} h${minutes ? ` ${minutes} min` : ''}` : minutes ? `${minutes} min` : `${seconds} s`;
}
export function providerDuration(raw: string | null | undefined, acceptsBareSeconds = true): string | null {
  const units = /(\d+)\s*(hours?|hrs?|horas?|h)\b|(\d+)\s*(minutes?|mins?|minutos?|m)\b|(\d+)\s*(seconds?|secs?|segundos?|s)\b/gi;
  for (const segment of parts(raw)) {
    const matches = [...segment.matchAll(units)];
    const residual = segment.replace(units, ' ').replace(/\band\b/gi, '').replace(/^[ ,;\t\n\r]+|[ ,;\t\n\r]+$/g, '');
    if (!matches.length || residual) continue;
    let total = 0;
    for (const match of matches) for (const index of [1,3,5]) if (match[index] !== undefined) {
      const unit = match[index+1].toLowerCase();
      total += Number(match[index]) * (unit.startsWith('h') ? 3600 : unit === 'm' || unit.startsWith('min') ? 60 : 1);
    }
    if (Number.isSafeInteger(total) && total > 0) return formatDuration(total);
  }
  for (const segment of parts(raw)) {
    if (!acceptsBareSeconds && !segment.includes(':')) continue;
    const seconds = durationSeconds(segment); if (seconds !== null) return formatDuration(seconds);
  }
  return null;
}
function completeDuration(items: { duration: string | null }[]): string | null {
  if (!items.length) return null;
  const values = items.map(item => durationSeconds(item.duration));
  return values.every(value => value !== null) ? formatDuration(values.reduce<number>((sum,value) => sum + (value ?? 0),0)) : null;
}
function trackCount(raw: string | null | undefined): number | null {
  const match = raw?.match(/(?<![\d.,])\d+(?:[.,\s]\d{3})*\s+(?:songs?|tracks?|canci[oó]n(?:es)?|pistas?)\b/i);
  return match ? Number(match[0].match(/^[\d.,\s]+/)![0].replace(/\D/g,'')) : null;
}
function albumArtist(raw: string | null | undefined): string | null {
  return clean(parts(raw).filter(part => !/^(?:álbum|album|single|sencillo|ep|(?:19|20)\d{2}|\d+\s*(?:songs?|tracks?|canciones?|pistas?|hours?|hrs?|horas?|h|minutes?|mins?|minutos?|m|seconds?|secs?|segundos?|s))$/i.test(part)).join(' • '));
}
function creator(raw: string | null | undefined): string | null {
  return clean(parts(raw).filter(part => {
    const value = part.normalize('NFD').replace(/[\u0300-\u036f]/g,'').toLowerCase();
    return !/^(?:playlist|lista de reproduccion|mix|(?:19|20)\d{2})$/.test(value) && trackCount(value) === null && providerDuration(value,false) === null
      && !/^\d+(?:[.,]\d+)?\s*[kmb]?\s+(?:views?|visualizaciones?|reproducciones?|subscribers?|suscriptores?)$/i.test(value);
  }).join(' • '));
}
/** HomeAlbumMetadata.make / HomePlaylistMetadata.make, including unloaded fallback values. */
export function metadataFor(item: HomeItemDto, detail: CollectionDetail | null = null): FeaturedMetadata {
  const title = clean(detail?.title) ?? clean(item.title) ?? '';
  const runs = item.artistRuns ?? [];
  if (item.kind === 'album') {
    const album = detail as AlbumDetailDto | null;
    const artists = albumArtist(album?.artist) ?? albumArtist(item.artists) ?? albumArtist(runs.map(run=>run.text).join(' • ')) ?? albumArtist(item.subtitle);
    const artistId = clean(album?.artistId) ?? clean(item.artistId) ?? clean(runs.find(run=>run.id)?.id);
    const summary = [{ album: 'Álbum', single: 'Sencillo', ep: 'EP' }[albumCollectionType(item, album)]];
    const published = year(album?.subtitle) ?? year(item.subtitle); if (published) summary.push(published);
    if (album) {
      const count = album.items.length ? album.items.length : album.secondSubtitle?.match(/\b\d+\s+(?:songs?|tracks?|canciones?|pistas?)\b/i)?.[0].match(/^\d+/)?.[0];
      if (count !== undefined) summary.push(Number(count) === 1 ? '1 canción' : `${count} canciones`);
      const duration = completeDuration(album.items) ?? providerDuration(album.secondSubtitle); if (duration) summary.push(duration);
    }
    return { title, artists, artistId, summary: summary.join(' • ') };
  }
  const playlist = detail as PlaylistDetailDto | null;
  const artists = creator(item.artists) ?? creator(runs.map(run=>run.text).join(' • ')) ?? creator(item.subtitle) ?? creator(playlist?.subtitle);
  const channelID = (value: string | null | undefined) => clean(value)?.startsWith('UC') ? clean(value) : null;
  const artistId = channelID(item.artistId) ?? channelID(runs.find(run=>creator(run.text) === artists && channelID(run.id))?.id);
  const subtitles = [playlist?.subtitle,item.subtitle];
  const complete = playlist !== null && clean(playlist.continuation) === null;
  const count = subtitles.map(trackCount).find(count=>count !== null) ?? (complete && playlist!.items.length ? playlist!.items.length : null);
  const duration = subtitles.map(value=>providerDuration(value,false)).find(value=>value !== null) ?? (complete ? completeDuration(playlist!.items) : null);
  return { title, artists, artistId, summary: ['Playlist',count !== null ? count === 1 ? '1 canción' : `${count} canciones` : null,duration].filter(Boolean).join(' • ') };
}
