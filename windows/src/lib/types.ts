import type { ContentMetadata } from './contentRating';

export interface LibraryToggleDto {
  inLibrary: boolean;
  addToken: string | null;
  removeToken: string | null;
}

export interface SongDto extends ContentMetadata {
  /** UI occurrence identity for a listen; never a provider mutation token. */
  historyOccurrenceId?: string;
  videoId: string;
  title: string;
  artists: string;
  artistRuns?: HomeArtistRunDto[];
  album: string | null;
  duration: string | null;
  thumbnail: string | null;
  isVideo: boolean;
  isUpload?: boolean;
  artistId: string | null;
  albumId: string | null;
  setVideoId?: string | null;
  library?: LibraryToggleDto | null;
}

export interface AlbumCardDto extends ContentMetadata {
  id: string;
  title: string;
  subtitle: string | null;
  thumbnail: string | null;
}

export interface AlbumDetailDto extends ContentMetadata {
  browseId: string;
  title: string;
  artist: string | null;
  artistRuns?: HomeArtistRunDto[];
  subtitle: string | null;
  secondSubtitle: string | null;
  description: string | null;
  thumbnail: string | null;
  items: SongDto[];
  artistId: string | null;
  playlistId: string | null;
  inLibrary: boolean;
  sections: ArtistCarouselDto[];
}

export interface HomeChipDto {
  title: string;
  params: string;
}

export interface HomeItemDto extends ContentMetadata {
  kind: string;
  id: string;
  title: string;
  subtitle: string | null;
  thumbnail: string | null;
  duration: string | null;
  artists: string | null;
  albumId: string | null;
  artistId: string | null;
  album: string | null;
  artistRuns: HomeArtistRunDto[];
  explicit: boolean;
}

export interface HomeSectionDto {
  title: string;
  format: string;
  items: HomeItemDto[];
  moreBrowseId: string | null;
  moreParams: string | null;
}

export interface HomePageDto {
  chips: HomeChipDto[];
  sections: HomeSectionDto[];
  continuation: string | null;
}

export interface HomeArtistRunDto { text: string; id: string | null }
export interface BrowseCardDto extends ContentMetadata { setVideoId?:string|null;library?:LibraryToggleDto|null;isUpload?:boolean;kind: string; id: string; title: string; subtitle: string | null; thumbnail: string | null; duration: string | null; artistRuns?: HomeArtistRunDto[]; artists?: string | null; artistId?: string | null; album?: string | null; albumId?: string | null; isVideo?: boolean; explicit?: boolean }
export interface SearchResultsDto {
  top: BrowseCardDto[];
  topSongs: SongDto[];
  songs: SongDto[];
  albums: BrowseCardDto[];
  artists: BrowseCardDto[];
  playlists: BrowseCardDto[];
}
export interface SearchSuggestionsDto { queries: string[]; results: SearchResultsDto }
export interface SearchCorrectionDto { query: string; applied: boolean }
export interface SearchCatalogDto { results: SearchResultsDto; correction: SearchCorrectionDto | null }
export interface ArtistCarouselDto { title: string; items: BrowseCardDto[]; moreBrowseId: string | null; moreParams: string | null }
export interface ArtistDetailDto {
  channelId: string; name: string; thumbnail: string | null; description: string | null;
  subscribers: string | null; monthlyListeners: string | null; subscribed: boolean;
  radioPlaylistId: string | null; topSongs: SongDto[]; topSongsId: string | null; sections: ArtistCarouselDto[];
}
export interface PlaylistDetailDto {
  id: string;
  title: string;
  subtitle: string | null;
  thumbnail: string | null;
  description: string | null;
  items: SongDto[];
  continuation: string | null;
  owned: boolean;
  inLibrary: boolean;
  privacy: string | null;
  collaborative: boolean;
  sort: string | null;
  sortEditable: boolean;
}

export interface BackendStatusDto {
  ready: boolean;
  status: string;
}

export interface AuthStatusDto {
  state: "guest" | "authorizing" | "ready" | "error";
  name: string | null;
  email: string | null;
  handle?: string | null;
  channelId?: string | null;
  thumbnail: string | null;
  message: string | null;
}

export interface CommandError {
  code: string;
  message: string;
}

export interface PlaybackTrackDto extends ContentMetadata {
  isUpload?: boolean;
  videoId: string;
  title: string;
  artists: string;
  artistRuns?: HomeArtistRunDto[];
  thumbnail: string | null;
  duration: number | null;
  artistId?: string | null;
  albumId?: string | null;
  album?: string | null;
}

export interface PlaybackStateDto {
  canNext?: boolean;
  sourceLoad?: {loading:boolean;error:string|null;canRetry:boolean;hasMore:boolean;loadedCount:number}|null;
  isPlaying: boolean;
  isLoading: boolean;
  isEnded: boolean;
  isShuffle: boolean;
  isRepeat: boolean;
  position: number;
  duration: number;
  volume: number;
  audioRevision?: number;
  authGeneration?: number;
  seekRevision?: number;
  seekPending?: number | null;
  seekError?: string | null;
  exponentialVolume?: boolean;
  currentTrack: PlaybackTrackDto | null;
  error: string | null;
  generation: number;
  queue: QueueStateDto;
}

export interface QueueEntryDto extends ContentMetadata {
  isUpload?: boolean;
  entryId: string;
  sourceOccurrenceId?: string | null;
  videoId: string;
  title: string;
  artists: string;
  artistRuns?: HomeArtistRunDto[];
  thumbnail: string | null;
  duration: number | null;
  artistId?: string | null;
  albumId?: string | null;
  album?: string | null;
}

export interface QueueStateDto {
  items: QueueEntryDto[];
  currentIndex: number | null;
  source: { kind: string; id: string | null; title: string | null } | null;
  revision: number;
  radio?: { loading: boolean; error: string | null; canRetry: boolean } | null;
}

export interface PlaybackProgressDto {
  seekRevision?: number;
  position: number;
  duration: number;
  generation: number;
}

export interface SearchChipDto {id:string;title:string;params:string|null;selected:boolean}
export interface SearchPageCorrectionDto extends SearchCorrectionDto {params:string|null;originalQuery:string|null;originalParams:string|null}
export interface SearchActionDto {title:string;videoId:string|null;playlistId:string|null;browseId:string|null;params:string|null}
export interface SearchSectionDto {id:string;title:string;layout:string;items:BrowseCardDto[];songs:SongDto[];primaryItemIndex?:number|null;relatedItemIndices?:number[];moreQuery:string|null;moreParams:string|null;moreBrowseId:string|null;actions:SearchActionDto[]}
export interface SearchPageDto {chips:SearchChipDto[];correction:SearchPageCorrectionDto|null;sections:SearchSectionDto[];continuation:string|null}
export interface SearchSuggestionEntryDto {id:string;kind:string;query:string|null;runs:{text:string;bold:boolean}[];feedbackToken:string|null;card:BrowseCardDto|null;song:SongDto|null}
export interface SearchSuggestionsPageDto {entries:SearchSuggestionEntryDto[]}

export interface SearchNextDto {items:SongDto[];continuation:string|null;automixPlaylistId:string|null}
