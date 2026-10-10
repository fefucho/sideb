export type CollectionKind = 'albums' | 'playlists';
export type Source = 'recommendedAlbums' | 'mixesForYou' | 'listenAgain' | 'forgottenFavorites' | 'fromLibrary' | 'newReleases' | 'fromCommunity' | 'otherHome' | 'libraryAlbums' | 'recentAlbums' | 'libraryPlaylists';
export const sourceLabels: Record<Source, string> = {
  recommendedAlbums: 'Recomendados para vos', mixesForYou: 'Mixes para vos', listenAgain: 'Volver a escuchar',
  forgottenFavorites: 'Favoritos olvidados', fromLibrary: 'De tu biblioteca en Inicio', newReleases: 'Nuevos lanzamientos',
  fromCommunity: 'De la comunidad', otherHome: 'Otros del Inicio', libraryAlbums: 'Álbumes guardados',
  recentAlbums: 'De tus escuchas recientes', libraryPlaylists: 'Playlists guardadas',
};
export interface SourcePreference { source: Source; enabled: boolean }
export interface HomeSettings {
  version: number; albumSources: SourcePreference[]; playlistSources: SourcePreference[];
  categoryOrderMode: 'sideB' | 'youtube' | 'custom'; categoryOrder: string[]; hiddenCategoryKeys: string[];
}
const allowed: Record<CollectionKind, Source[]> = {
  albums: ['recommendedAlbums', 'listenAgain', 'forgottenFavorites', 'fromLibrary', 'newReleases', 'otherHome', 'libraryAlbums', 'recentAlbums'],
  playlists: ['mixesForYou', 'listenAgain', 'forgottenFavorites', 'fromLibrary', 'fromCommunity', 'otherHome', 'libraryPlaylists'],
};
export function defaults(): HomeSettings {
  const preferences = (kind: CollectionKind) => allowed[kind].map(source => ({ source, enabled: !['libraryAlbums', 'recentAlbums', 'libraryPlaylists'].includes(source) }));
  return { version: 1, albumSources: preferences('albums'), playlistSources: preferences('playlists'), categoryOrderMode: 'sideB', categoryOrder: [], hiddenCategoryKeys: [] };
}
export function decodeSettings(value: unknown): HomeSettings {
  const fallback = defaults();
  if (!value || typeof value !== 'object') return fallback;
  const v = value as Record<string, unknown>;
  if (typeof v.version === 'number' && v.version > 1) return fallback;
  for (const kind of ['albums', 'playlists'] as const) {
    const field = kind === 'albums' ? 'albumSources' : 'playlistSources';
    if (!Array.isArray(v[field])) continue;
    const seen = new Set<Source>();
    const rows: SourcePreference[] = [];
    for (const row of v[field]) {
      if (!row || typeof row !== 'object' || !allowed[kind].includes(row.source) || seen.has(row.source)) continue;
      seen.add(row.source); rows.push({ source: row.source, enabled: row.enabled === true });
    }
    fallback[field] = rows;
  }
  if (['sideB', 'youtube', 'custom'].includes(String(v.categoryOrderMode))) fallback.categoryOrderMode = v.categoryOrderMode as HomeSettings['categoryOrderMode'];
  for (const field of ['categoryOrder', 'hiddenCategoryKeys'] as const) {
    if (Array.isArray(v[field])) fallback[field] = [...new Set(v[field].filter((key): key is string => typeof key === 'string' && key.length > 0))];
  }
  return fallback;
}
export function normalized(text: string) { return text.trim().toLowerCase().normalize('NFD').replace(/[\u0300-\u036f]/g, ''); }
const aliases: Record<string, string[]> = {
  'quick-picks': ['quick picks', 'selecciones rápidas'], 'speed-dial': ['speed dial', 'marcación rápida'],
  'recommended-albums': ['albums for you', 'álbumes para ti', 'recommended albums', 'álbumes recomendados'],
  'mixes-for-you': ['mixed for you', 'mixes for you', 'your mixes', 'personalized mixes', 'mixes para ti', 'tus mixes', 'mixes personalizados', 'hecho para ti'],
  'listen-again': ['listen again', 'vuelve a escucharlo', 'volver a escuchar', 'escuchar de nuevo'],
  'new-releases': ['new releases', 'nuevos lanzamientos', 'lanzamientos nuevos'],
  'forgotten-favorites': ['forgotten favorites', 'forgotten favourites', 'favoritos olvidados'],
  'from-library': ['from your library', 'de tu biblioteca', 'de la biblioteca'],
  'from-community': ['from the community', 'de la comunidad', 'de la comunidad de youtube music'],
};
export function categoryKey(title: string): string {
  const name = normalized(title);
  return Object.entries(aliases).find(([, names]) => names.some(alias => normalized(alias) === name))?.[0] ?? `custom:${name}`;
}
export function sourceForTitle(title: string): Source {
  return ({ 'recommended-albums': 'recommendedAlbums', 'mixes-for-you': 'mixesForYou', 'listen-again': 'listenAgain',
    'forgotten-favorites': 'forgottenFavorites', 'from-library': 'fromLibrary', 'new-releases': 'newReleases', 'from-community': 'fromCommunity' } as Record<string, Source>)[categoryKey(title)] ?? 'otherHome';
}
/** Mac HomeViewModel.hasReceivedEnabledSources: supplemental/Other Home do not require prefetch. */
export function missingHomeSources(titles: string[], settings: HomeSettings, kind: CollectionKind): boolean {
  const received = new Set(titles.map(sourceForTitle));
  return (kind === 'albums' ? settings.albumSources : settings.playlistSources)
    .some(row => row.enabled && !['otherHome', 'libraryAlbums', 'libraryPlaylists', 'recentAlbums'].includes(row.source) && !received.has(row.source));
}
export function canonicalId(kind: string, id: string) { return kind === 'playlist' ? id.trim().replace(/^VL/, '') : id.trim(); }
export function move<T>(items: T[], from: number, to: number): T[] {
  if (from < 0 || to < 0 || from >= items.length || to >= items.length) return items;
  const next = [...items]; const [item] = next.splice(from, 1); next.splice(to, 0, item); return next;
}
export function orderCategories(settings: HomeSettings, present: string[]): HomeSettings {
  return { ...settings, categoryOrderMode: 'custom', categoryOrder: [...present, ...settings.categoryOrder.filter(key => !present.includes(key))] };
}
export async function accountSettingsKey(identity: string) {
  const digest = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(identity));
  return `sideb.home.recommendations.v1.${Array.from(new Uint8Array(digest), byte => byte.toString(16).padStart(2, '0')).join('')}`;
}
