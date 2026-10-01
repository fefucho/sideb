export interface LibraryToggleDto {
  inLibrary: boolean;
  addToken: string | null;
  removeToken: string | null;
}

export interface SongDto {
  videoId: string;
  title: string;
  artists: string;
  artistRuns?: HomeArtistRunDto[];
  album: string | null;
  duration: string | null;
  thumbnail: string | null;
  isVideo: boolean;
  artistId: string | null;
  albumId: string | null;
  setVideoId?: string | null;
  library?: LibraryToggleDto | null;
}

export interface AlbumCardDto {
  id: string;
  title: string;
  subtitle: string | null;
  thumbnail: string | null;
}

export interface AlbumDetailDto {
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

export interface HomeItemDto {
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
export interface BrowseCardDto { kind: string; id: string; title: string; subtitle: string | null; thumbnail: string | null; duration: string | null; artistRuns?: HomeArtistRunDto[]; artists?: string | null; artistId?: string | null; album?: string | null; albumId?: string | null; isVideo?: boolean; explicit?: boolean }
export interface SearchResultsDto {
  top: BrowseCardDto[];
  songs: SongDto[];
  albums: BrowseCardDto[];
  artists: BrowseCardDto[];
  playlists: BrowseCardDto[];
}
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
  thumbnail: string | null;
  message: string | null;
}

export interface CommandError {
  code: string;
  message: string;
}

export interface PlaybackTrackDto {
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
  isPlaying: boolean;
  isLoading: boolean;
  isEnded: boolean;
  position: number;
  duration: number;
  volume: number;
  currentTrack: PlaybackTrackDto | null;
  error: string | null;
  generation: number;
  queue: QueueStateDto;
}

export interface QueueEntryDto {
  entryId: string;
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
  position: number;
  duration: number;
  generation: number;
}
