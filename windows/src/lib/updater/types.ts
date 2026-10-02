export interface UpdateInfo {
  tagName: string;
  version: string;
  releaseNotes: string;
  downloadUrl: string;
  publishedAt?: string | null;
}

export type UpdateState =
  | { type: 'idle' }
  | { type: 'checking' }
  | { type: 'upToDate'; version: string }
  | { type: 'available'; info: UpdateInfo }
  | { type: 'downloading'; progress: number; info: UpdateInfo }
  | { type: 'installing'; info: UpdateInfo }
  | { type: 'failed'; message: string };

export interface DownloadProgressPayload {
  percentage: number;
  downloadedBytes: number;
  totalBytes?: number | null;
}

export interface UpdaterApi {
  getAppVersion(): Promise<string>;
  checkForUpdates(manual: boolean): Promise<{ status: 'upToDate'; currentVersion: string } | { status: 'available'; data: UpdateInfo }>;
  downloadAndInstallUpdate(downloadUrl: string): Promise<void>;
  skipVersion(version: string): Promise<void>;
  resetSkippedVersion(): Promise<void>;
  getSkippedVersion(): Promise<string | null>;
  onDownloadProgress?(callback: (payload: DownloadProgressPayload) => void): () => void;
}
