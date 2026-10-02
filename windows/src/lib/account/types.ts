import type { PlaylistDetailDto, SongDto } from "../types";

/** Feedback tokens are transient action data returned by the core for a song row. */
export interface LibraryToggleDto {
  inLibrary: boolean;
  addToken: string | null;
  removeToken: string | null;
}

/** Account-aware song metadata; the base SongDto remains compatible with local producers. */
export interface AccountSongDto extends SongDto {
  setVideoId?: string | null;
  library?: LibraryToggleDto | null;
}

export interface PlaylistContinuationDto {
  items: AccountSongDto[];
  continuation: string | null;
}

export interface HistoryGroupDto {
  title: string;
  items: AccountSongDto[];
}

/** Full playlist metadata returned by sideb-core, including ownership and editing capabilities. */
export interface AccountPlaylistDto extends PlaylistDetailDto {
  subtitle: string | null;
  description: string | null;
  owned: boolean;
  inLibrary: boolean;
  privacy: string | null;
  collaborative: boolean;
  sort: string | null;
  sortEditable: boolean;
  items: AccountSongDto[];
}
