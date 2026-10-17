import type {BrowseCardDto,SearchResultsDto,SongDto} from '../types';
const cardKey=(card:BrowseCardDto)=>`${card.kind}:${card.id}`;
const songKey=(song:SongDto)=>`${song.isVideo?'video':'song'}:${song.videoId}`;
/** Restore credits omitted by an artist shelf, without changing the song's occurrence metadata. */
function associatedSong(source:SongDto,results:SearchResultsDto):SongDto {
 let song=source;
 if(!song.artists.trim()&&!song.artistRuns?.length){
  const complete=results.songs.find(item=>item.videoId===song.videoId&&item.isVideo===song.isVideo&&(item.artists.trim()||item.artistRuns?.length));
  if(complete)song={...song,artists:complete.artists,artistRuns:complete.artistRuns,artistId:song.artistId??complete.artistId};
 }
 if(!song.artists.trim()&&song.artistRuns?.length)song={...song,artists:song.artistRuns.map(run=>run.text).join('')};
 const artist=results.top[0];
 if(!song.artists.trim()&&!song.artistRuns?.length&&artist?.kind.toLowerCase()==='artist'&&artist.title.trim()&&(!song.artistId||song.artistId===artist.id)){
  song={...song,artists:artist.title,artistId:artist.id,artistRuns:[{text:artist.title,id:artist.id}]};
 }
 return song;
}
/** Stable provider order inside each type; only search resources are deduplicated. */
export function searchProjection(results:SearchResultsDto & {videos?:SongDto[]}, budget=Infinity):SearchResultsDto & {videos:SongDto[]} {
 const seen=new Set<string>();let remaining=budget;
 const cards=(items:BrowseCardDto[])=>items.filter(card=>{const key=cardKey(card);if(!card.id||seen.has(key)||remaining<=0)return false;seen.add(key);remaining--;return true;});
 const songs=(items:SongDto[])=>items.filter(song=>{const key=songKey(song);if(!song.videoId||seen.has(key)||remaining<=0)return false;seen.add(key);remaining--;return true;});
 const top=cards(results.top.slice(0,1));
 const associatedSeen=new Set<string>();
 const associated=(results.topSongs??[]).map(song=>associatedSong(song,results)).filter(song=>{const key=songKey(song);if(seen.has(key)||associatedSeen.has(key))return false;associatedSeen.add(key);return true;}).slice(0,3);
 const topSongs=songs(associated);
 return {top,topSongs,songs:songs(results.songs),artists:cards(results.artists),albums:cards(results.albums),playlists:cards(results.playlists),videos:songs(results.videos??[])};
}

/** Autocomplete top is an ordered stream of heterogeneous provider entities, not a catalog hero. */
export function suggestionProjection(results:SearchResultsDto,budget=8):SearchResultsDto {
 const seen=new Set<string>();let remaining=budget;
 const cards=(items:BrowseCardDto[])=>items.filter(card=>{const key=cardKey(card);if(!card.id||seen.has(key)||remaining<=0)return false;seen.add(key);remaining--;return true;});
 const songs=(items:SongDto[])=>items.filter(song=>{const key=songKey(song);if(!song.videoId||seen.has(key)||remaining<=0)return false;seen.add(key);remaining--;return true;});
 return {top:cards(results.top),topSongs:results.topSongs??[],songs:songs(results.songs),artists:cards(results.artists),albums:cards(results.albums),playlists:cards(results.playlists)};
}
