import { writable, type Readable } from 'svelte/store';
import { visualProviderApi, type VisualProviderApi } from './api';
import type { VisualProviderLoginState, VisualProviderState } from './types';

export interface VisualProviderSettingsView {
  state: VisualProviderState | null;
  /** An install/uninstall/save call is running: controls are disabled. */
  pending: boolean;
  /** The last operation failed (generic message; details never include credentials). */
  failed: boolean;
  /** Login dialog state; null = no dialog. */
  login: VisualProviderLoginState | null;
}

/** The shared string mentions the macOS Keychain; Windows has its own wording for that state. */
export function settingsStatusKey(key: string): string {
  return key === 'visualProvider.status.tokenRequired' ? 'windows.visualProvider.status.tokenRequired' : key;
}

const CONNECTED_DIALOG_MS = 1500;

/**
 * Controller of the settings section. It owns no truth: the host does. It disables controls while an
 * operation runs, shows the login dialog from host events and never keeps a typed token around.
 */
export function createVisualProviderSettings(api: VisualProviderApi = visualProviderApi, schedule: (run: () => void, ms: number) => unknown = setTimeout) {
  const store = writable<VisualProviderSettingsView>({ state: null, pending: false, failed: false, login: null });
  let view: VisualProviderSettingsView = { state: null, pending: false, failed: false, login: null };
  const update = (patch: Partial<VisualProviderSettingsView>) => { view = { ...view, ...patch }; store.set(view); };
  const apply = (state: VisualProviderState) => { if (!view.state || state.revision >= view.state.revision) update({ state }); };
  let stopped = true;
  let hideTimer = 0;

  async function run(operation: () => Promise<VisualProviderState>): Promise<boolean> {
    update({ pending: true });
    try {
      apply(await operation());
      update({ failed: false });
      return true;
    } catch {
      update({ failed: true });
      return false;
    } finally {
      update({ pending: false });
    }
  }

  function onLogin(state: VisualProviderLoginState) {
    const token = ++hideTimer;
    if (state === 'closed') { update({ login: null }); return; }
    update({ login: state });
    if (state === 'connected') schedule(() => { if (hideTimer === token && view.login === 'connected') update({ login: null }); }, CONNECTED_DIALOG_MS);
  }

  return {
    subscribe: store.subscribe as Readable<VisualProviderSettingsView>['subscribe'],
    /** Loads the state and follows host events. Call once on mount; call the result on destroy. */
    start(): () => void {
      stopped = false;
      const unlisten: Array<() => void> = [];
      api.onChanged(apply).then(stop => { if (stopped) stop(); else unlisten.push(stop); }).catch(() => undefined);
      api.onLogin(onLogin).then(stop => { if (stopped) stop(); else unlisten.push(stop); }).catch(() => undefined);
      api.state().then(apply).catch(() => update({ failed: true }));
      return () => { stopped = true; unlisten.splice(0).forEach(stop => stop()); };
    },
    setEnabled: (enabled: boolean) => run(() => api.setEnabled(enabled)),
    installBundled: () => run(() => api.installBundled()),
    installFromFolder: (path: string) => run(() => api.installFromFolder(path.trim())),
    uninstall: () => run(() => api.uninstall()),
    saveToken: (token: string) => run(() => api.saveToken(token)),
    /** Opens the provider's login window once; the dialog follows its progress. */
    async signIn(title: string | null): Promise<void> {
      update({ login: 'waiting', failed: false });
      try {
        if (!(await api.openLogin(title))) update({ login: 'failed' });
      } catch {
        update({ login: 'failed' });
      }
    },
    async closeLogin(): Promise<void> {
      hideTimer++;
      update({ login: null });
      try { await api.cancelLogin(); } catch { /* The window may already be gone. */ }
    },
  };
}
