import type { BrowseCardDto, HomeArtistRunDto } from '../types';

const typeLabel = /^(?:song|canción|cancion|video|vídeo|album|álbum|single|sencillo|ep|playlist|lista|mix)$/iu;
const duration = /^\d+(?::\d{2}){1,2}$/u;
const year = /^(?:19|20)\d{2}$/u;
// Full metric expressions only: names such as "Views", "Plays" and "The 1975" remain names.
const count = /^(?:[\d.,\s\u00a0\u202f]+\s*(?:[kmb]|mil|millón|millon|millones|millions?|billions?)?\s*(?:de\s+)?(?:plays?|views?|streams?|listeners?|subscribers?|reproducciones|visualizaciones|vistas|oyentes|suscriptores))(?:\s+.*)?$/iu;
export function isProviderStatistic(value: string): boolean { return count.test(value.trim()); }
const parts = (value: string | null | undefined) => (value ?? '').split(/[•·]/u).map(part => part.trim()).filter(Boolean);
const descriptor = (value: string) => typeLabel.test(value.trim()) || duration.test(value.trim()) || isProviderStatistic(value);
function cleanArtistRuns(runs: HomeArtistRunDto[]): HomeArtistRunDto[] {
  const groups: number[][] = [[]];
  runs.forEach((run,index) => { if (/^[•·]$/u.test(run.text.trim())) groups.push([]); else groups.at(-1)!.push(index); });
  const rejected = new Set<number>();
  for (const group of groups) {
    if (!group.some(index => runs[index].id) && descriptor(group.map(index => runs[index].text).join(''))) group.forEach(index => rejected.add(index));
    for (const index of group) if (!runs[index].id && descriptor(runs[index].text)) rejected.add(index);
  }
  // Empty descriptor groups may leave separators; ArtistCredits already ignores punctuation,
  // but trimming them keeps the plain-text credit usable by the native queue as well.
  const retained = runs.filter((_,index) => !rejected.has(index));
  while (retained.length && /^[\s•·,;&]+$/u.test(retained[0].text)) retained.shift();
  while (retained.length && /^[\s•·,;&]+$/u.test(retained.at(-1)!.text)) retained.pop();
  return retained.length === runs.length ? runs : retained;
}
const credit = (value: string | null | undefined, fallback = false) => {
  const fields = parts(value);
  while (fields.length > 1 && typeLabel.test(fields[0])) fields.shift();
  const first = fields[0] ?? '';
  return !first || typeLabel.test(first) || duration.test(first) || isProviderStatistic(first) || (fallback && year.test(first)) ? '' : first;
};

/** Home descriptors are presentation text, not an album contract. Keep known links/flags and
 * accept a non-statistical subtitle album label only with its album ID. Missing albums
 * must be hydrated from the selected song's canonical metadata, never from a play count. */
export function normalizeHomeSongCard<T extends BrowseCardDto>(card: T): T {
  if (card.kind !== 'song' && card.kind !== 'video') return card;
  const runs = cleanArtistRuns(card.artistRuns ?? []);
  const linked = runs.some(run => Boolean(run.id));
  const runText = runs.reduce((text, run) => text + (/[\p{L}\p{N}]$/u.test(text) && /^[\p{L}\p{N}]/u.test(run.text) ? ', ' : '') + run.text, '');
  const linkedCredit = linked ? runText.trim() : '';
  // The typed field can contain several unlinked collaborators. Only the raw subtitle has
  // the positional artist/descriptor ambiguity, so don't truncate a typed collaborator list.
  const typedCredit = parts(card.artists).filter(field => !descriptor(field)).join(' • ');
  const artists = linkedCredit || typedCredit || credit(card.subtitle, true);
  let album = card.album?.trim() || null;
  // This field comes from a positional Home subtitle. A valid album destination
  // does not make a counter its title; canonical SongDto/album details are separate.
  if (album && (isProviderStatistic(album) || duration.test(album))) album = null;
  if (!album && card.albumId) {
    const fields = parts(card.subtitle);
    while (fields.length > 1 && typeLabel.test(fields[0])) fields.shift();
    const candidate = fields.slice(1).find(field => !isProviderStatistic(field) && !duration.test(field) && !year.test(field) && !typeLabel.test(field));
    album = candidate ?? null;
  }
  return { ...card, artists, album, artistRuns: runs };
}
