import type {BrowseCardDto,SearchResultsDto,SongDto} from '../types';
/** Resolve original DTO instead of losing occurrence/library tokens by rebuilding a card. */
export function resolveSearchSong(card:BrowseCardDto,results:Pick<SearchResultsDto,'songs'|'topSongs'>|null|undefined,videos:SongDto[]=[]):SongDto|null {
 if(!['song','video'].includes(card.kind))return null;
 return [...(results?.topSongs??[]),...(results?.songs??[]),...videos].find(song=>song.videoId===card.id)??null;
}
export function relatedTopSongs(results:Pick<SearchResultsDto,'top'|'topSongs'>):SongDto[] {
 const hero=results.top[0];const seen=new Set<string>();
 return (results.topSongs??[]).filter(song=>{
  if(!song.videoId || (['song','video'].includes(hero?.kind??'')&&song.videoId===hero.id) || seen.has(song.videoId))return false;
  seen.add(song.videoId);return true;
 }).slice(0,3);
}
