import type { SongDto } from '../types';

export type TrackOrder = 'custom' | 'title' | 'artist' | 'album' | 'duration';
export function captureTrackOccurrence(tracks:SongDto[], index:number) {
  const track=tracks[index]; if(!track)return null;
  const matches=(song:SongDto)=>song.videoId===track.videoId && (song.setVideoId??null)===(track.setVideoId??null);
  return { videoId:track.videoId, setVideoId:track.setVideoId??null, ordinal:tracks.slice(0,index).filter(matches).length };
}
export function findTrackOccurrence(tracks:SongDto[], selected:ReturnType<typeof captureTrackOccurrence>) {
  if(!selected)return -1;
  let ordinal=0;
  return tracks.findIndex(song=>song.videoId===selected.videoId && (song.setVideoId??null)===selected.setVideoId && ordinal++===selected.ordinal);
}
export const normalize = (value: string) => value.trim().normalize('NFD').replace(/[\u0300-\u036f]/g, '').toLocaleLowerCase();
function duration(value: string | null) {
  if (!value || !/^\d+(?::\d{1,2}){1,2}$/.test(value)) return Infinity;
  return value.split(':').reduce((sum, part) => sum * 60 + Number(part), 0);
}
/** Filtering changes visibility only; sourceIndex remains the playback occurrence. */
export function projectTracks<T extends SongDto>(tracks: T[], query = '', order: TrackOrder = 'custom') {
  const ordinals = new Map<string, number>();
  const all = tracks.map((track, sourceIndex) => {
    const base = track.setVideoId ? `set:${track.setVideoId}` : `index:${sourceIndex}:${track.videoId}`;
    const ordinal = ordinals.get(base) ?? 0; ordinals.set(base, ordinal + 1);
    return { track, sourceIndex, key: `${base}:${ordinal}` };
  });
  const needle = normalize(query);
  const visible = all.filter(({ track }) => !needle || [track.title, track.artists, track.album ?? ''].some(value => normalize(value).includes(needle)));
  if (order !== 'custom') visible.sort((left, right) => {
    if (order === 'duration') { const a = duration(left.track.duration), b = duration(right.track.duration); return (a === b ? 0 : a < b ? -1 : 1) || left.sourceIndex - right.sourceIndex; }
    const field = order === 'artist' ? 'artists' : order;
    return normalize(left.track[field] ?? '').localeCompare(normalize(right.track[field] ?? ''), undefined, { numeric: true }) || left.sourceIndex - right.sourceIndex;
  });
  return visible;
}

/** Complete ordered source and selected occurrence, independent of a visible filter. */
export function projectedPlayback<T extends SongDto>(tracks: T[], sourceIndex: number, order: TrackOrder) {
  const all = projectTracks(tracks, '', order);
  return { items: all.map(entry => entry.track), index: all.findIndex(entry => entry.sourceIndex === sourceIndex) };
}

export function canReorderPlaylist(items: SongDto[], continuation: string | null, owned: boolean, order: TrackOrder, query: string, busy: boolean) {
  const ids = items.map(item => item.setVideoId);
  return owned && !continuation && order === 'custom' && !query.trim() && !busy && ids.every(Boolean) && new Set(ids).size === ids.length;
}
