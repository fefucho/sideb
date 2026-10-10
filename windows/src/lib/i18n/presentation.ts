import { categoryKey } from '../home/settings';
import { count, text, type AppLanguage } from './index';
/** Classify original metadata first. Unknown provider names keep their original spelling. */
export function providerHeading(raw: string, language: AppLanguage): string {
  const family = categoryKey(raw);
  const known = ['quick-picks', 'speed-dial', 'recommended-albums', 'mixes-for-you', 'listen-again', 'new-releases', 'forgotten-favorites', 'from-library', 'from-community'];
  const other: Record<string, string> = { 'similar artists': 'similar-artists', 'artistas similares': 'similar-artists', 'songs for today': 'songs-for-today', 'canciones para hoy': 'songs-for-today', 'featured playlists': 'featured-playlists', 'listas destacadas': 'featured-playlists', 'more to listen': 'more-to-listen', 'más para escuchar': 'more-to-listen', 'more artists': 'more-artists', 'más artistas': 'more-artists' };
  const key = known.includes(family) ? family : other[raw.toLowerCase()];
  return key ? text(`provider.heading.${key}`, [], language) : raw;
}
/** Own summaries are produced by metadataFor; they are never written back over provider metadata. */
export function collectionSummary(raw: string, language: AppLanguage): string {
  return raw.split(' • ').map(part => {
    if (part === 'Álbum') return text('metadata.album', [], language);
    if (part === 'Sencillo') return text('metadata.single', [], language);
    if (part === 'Playlist') return text('metadata.playlist.short', [], language);
    const quantity = /^(\d+) canci(?:ón|ones)$/.exec(part);
    return quantity ? count('common.songCount', Number(quantity[1]), language) : part;
  }).join(' • ');
}
