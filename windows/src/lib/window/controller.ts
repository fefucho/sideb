export interface WindowFullscreenApi {
  isFullscreen(): Promise<boolean>;
  setFullscreen(fullscreen: boolean): Promise<void>;
}

export type WindowAction = 'toggle-native-fullscreen';

export class WindowControllerError extends Error {
  constructor(readonly action: WindowAction, cause: unknown) {
    const detail = cause instanceof Error ? cause.message : String(cause);
    const message = 'No se pudo cambiar la pantalla completa de la ventana.';
    super(detail ? `${message} ${detail}` : message, { cause });
    this.name = 'WindowControllerError';
  }
}

async function tauriWindowApi(): Promise<WindowFullscreenApi> {
  if (typeof window === 'undefined') {
    throw new Error('La API de ventana sólo está disponible en la aplicación de escritorio.');
  }
  const { getCurrentWindow } = await import('@tauri-apps/api/window');
  const nativeWindow = getCurrentWindow();
  return {
    isFullscreen: () => nativeWindow.isFullscreen(),
    setFullscreen: fullscreen => nativeWindow.setFullscreen(fullscreen),
  };
}

/** Serializes F11 transitions. Expanded player presentation belongs to the app UI. */
export class WindowController {
  private operationQueue: Promise<void> = Promise.resolve();

  constructor(private readonly apiProvider: () => Promise<WindowFullscreenApi> = tauriWindowApi) {}

  toggleNativeFullscreen(): Promise<void> {
    return this.enqueue('toggle-native-fullscreen', async api => {
      const current = await api.isFullscreen();
      await api.setFullscreen(!current);
    });
  }

  private enqueue(action: WindowAction, operation: (api: WindowFullscreenApi) => Promise<void>): Promise<void> {
    const run = this.operationQueue.then(async () => {
      try {
        await operation(await this.apiProvider());
      } catch (error) {
        if (error instanceof WindowControllerError) throw error;
        throw new WindowControllerError(action, error);
      }
    });
    this.operationQueue = run.catch(() => undefined);
    return run;
  }
}
