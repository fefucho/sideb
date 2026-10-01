import type { UpdateInfo, UpdateState, UpdaterApi, DownloadProgressPayload } from './types';

export class UpdaterControllerError extends Error {
  constructor(readonly action: string, cause: unknown) {
    const detail = cause instanceof Error ? cause.message : String(cause);
    super(`Error en el actualizador (${action}): ${detail}`, { cause });
    this.name = 'UpdaterControllerError';
  }
}

async function defaultTauriUpdaterApi(): Promise<UpdaterApi> {
  const { invoke } = await import('@tauri-apps/api/core');
  const { listen } = await import('@tauri-apps/api/event');

  return {
    getAppVersion: () => invoke<string>('get_app_version'),
    checkForUpdates: (manual: boolean) => invoke('check_for_updates', { manual }),
    downloadAndInstallUpdate: (downloadUrl: string) =>
      invoke('download_and_install_update', { downloadUrl }),
    skipVersion: (version: string) => invoke('skip_version', { version }),
    resetSkippedVersion: () => invoke('reset_skipped_version'),
    getSkippedVersion: () => invoke<string | null>('get_skipped_version'),
    onDownloadProgress: (callback: (payload: DownloadProgressPayload) => void) => {
      let unlistenFn: (() => void) | null = null;
      void listen<DownloadProgressPayload>('update-download-progress', event => {
        callback(event.payload);
      }).then(unlisten => {
        unlistenFn = unlisten;
      });
      return () => {
        unlistenFn?.();
      };
    },
  };
}

export interface UpdaterSnapshot {
  state: UpdateState;
  currentVersion: string;
  isModalOpen: boolean;
}

export class UpdaterController {
  private state: UpdateState = { type: 'idle' };
  private currentVersion = '0.1.0';
  private isModalOpen = false;
  private listeners = new Set<(snapshot: UpdaterSnapshot) => void>();
  private unlistenProgress: (() => void) | null = null;

  constructor(private readonly apiProvider: () => Promise<UpdaterApi> = defaultTauriUpdaterApi) {}

  subscribe(listener: (snapshot: UpdaterSnapshot) => void): () => void {
    this.listeners.add(listener);
    listener(this.getSnapshot());
    return () => {
      this.listeners.delete(listener);
    };
  }

  getSnapshot(): UpdaterSnapshot {
    return {
      state: this.state,
      currentVersion: this.currentVersion,
      isModalOpen: this.isModalOpen,
    };
  }

  private notify() {
    const snapshot = this.getSnapshot();
    for (const listener of this.listeners) {
      listener(snapshot);
    }
  }

  async init(): Promise<void> {
    try {
      const api = await this.apiProvider();
      this.currentVersion = await api.getAppVersion();
      this.notify();
    } catch {
      // Ignorar fallos de init si no estamos en runtime Tauri
    }
  }

  async checkForUpdates(manual = false): Promise<void> {
    this.state = { type: 'checking' };
    if (manual) {
      this.isModalOpen = true;
    }
    this.notify();

    try {
      const api = await this.apiProvider();
      this.currentVersion = await api.getAppVersion();
      const result = await api.checkForUpdates(manual);

      if (result.status === 'available') {
        this.state = { type: 'available', info: result.data };
        this.isModalOpen = true;
      } else {
        if (manual) {
          this.state = { type: 'upToDate', version: this.currentVersion };
          this.isModalOpen = true;
        } else {
          this.state = { type: 'idle' };
          this.isModalOpen = false;
        }
      }
    } catch (err) {
      const message = err instanceof Error ? err.message : String(err);
      if (manual) {
        this.state = { type: 'failed', message };
        this.isModalOpen = true;
      } else {
        this.state = { type: 'idle' };
      }
    } finally {
      this.notify();
    }
  }

  async downloadAndInstall(): Promise<void> {
    if (this.state.type !== 'available') return;
    const info = this.state.info;

    this.state = { type: 'downloading', progress: 0, info };
    this.notify();

    try {
      const api = await this.apiProvider();

      if (api.onDownloadProgress) {
        this.unlistenProgress?.();
        this.unlistenProgress = api.onDownloadProgress(payload => {
          if (this.state.type === 'downloading') {
            this.state = {
              type: 'downloading',
              progress: payload.percentage,
              info,
            };
            this.notify();
          }
        });
      }

      await api.downloadAndInstallUpdate(info.downloadUrl);
      this.state = { type: 'installing', info };
      this.notify();
    } catch (err) {
      const message = err instanceof Error ? err.message : String(err);
      this.state = { type: 'failed', message };
      this.notify();
    } finally {
      this.unlistenProgress?.();
      this.unlistenProgress = null;
    }
  }

  async skipVersion(version: string): Promise<void> {
    try {
      const api = await this.apiProvider();
      await api.skipVersion(version);
    } catch {
      // Ignorar fallo de almacenamiento
    }
    this.closeModal();
  }

  openModal(): void {
    this.isModalOpen = true;
    this.notify();
  }

  closeModal(): void {
    this.isModalOpen = false;
    if (this.state.type === 'upToDate' || this.state.type === 'failed') {
      this.state = { type: 'idle' };
    }
    this.notify();
  }
}
