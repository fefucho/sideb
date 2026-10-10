import type { BrowseCardDto, PlaylistDetailDto } from '../types';
import type { MenuTarget } from './types';

/** LM is a known account collection; ownership/capabilities come only from cached provider detail. */
export function likedPlaylistTarget(loggedIn: boolean, label: string, playlists: BrowseCardDto[], detail?: PlaylistDetailDto | null): MenuTarget | null {
  if (!loggedIn) return null;
  const isLiked = (id: string) => id.replace(/^VL/, '') === 'LM';
  const cached = detail && isLiked(detail.id) ? detail : undefined;
  const saved = playlists.find(card => card.kind === 'playlist' && isLiked(card.id));
  const card = saved ?? { kind: 'playlist', id: 'LM', title: cached?.title ?? label, subtitle: cached?.subtitle ?? null, thumbnail: cached?.thumbnail ?? null, duration: null };
  return { kind: 'playlist', card, ...(cached ? { detail: cached } : {}) };
}
