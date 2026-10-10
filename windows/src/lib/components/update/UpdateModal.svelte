<script lang="ts">
  import { t , language, resolveMessage } from '$lib/i18n';
  import ReleaseNotes from './ReleaseNotes.svelte';
  import { onMount, tick } from 'svelte';
  import type { UpdaterController, UpdaterSnapshot } from '$lib/updater/controller';

  interface Props {
    controller: UpdaterController;
    onOpenExternal?: (url: string) => void;
  }

  let { controller, onOpenExternal }: Props = $props();

  let snapshot = $state<UpdaterSnapshot>({
    state: { type: 'idle' },
    currentVersion: '0.1.0',
    isModalOpen: false,
  });
  let closeButton: HTMLButtonElement | undefined = $state();
  let previousFocus: HTMLElement | null = null;

  $effect(() => {
    snapshot = controller.getSnapshot();
    const unsubscribe = controller.subscribe(next => {
      snapshot = next;
    });
    return unsubscribe;
  });

  onMount(() => {
    previousFocus = document.activeElement instanceof HTMLElement ? document.activeElement : null;
    closeButton?.focus();

    const handleKeydown = (event: KeyboardEvent) => {
      if (snapshot.state.type === 'installing') return;

      if (event.key === 'Escape') {
        event.stopPropagation();
        controller.closeModal();
      }
      if (event.key === 'Tab') {
        const focusable = Array.from(
          document.querySelectorAll<HTMLElement>('[role=dialog] button:not(:disabled)')
        );
        if (focusable.length === 0) {
          event.preventDefault();
          return;
        }
        if (focusable.length === 1) {
          event.preventDefault();
          focusable[0].focus();
          return;
        }
        if (event.shiftKey && document.activeElement === focusable[0]) {
          event.preventDefault();
          focusable.at(-1)?.focus();
        } else if (!event.shiftKey && document.activeElement === focusable.at(-1)) {
          event.preventDefault();
          focusable[0]?.focus();
        }
      }
    };

    document.addEventListener('keydown', handleKeydown);
    return () => {
      document.removeEventListener('keydown', handleKeydown);
      void tick().then(() => previousFocus?.focus());
    };
  });

  function handleScrimClick(event: MouseEvent) {
    if (snapshot.state.type === 'installing') return;
    if (event.target === event.currentTarget) {
      controller.closeModal();
    }
  }

  function handleUpdateClick() {
    void controller.downloadAndInstall();
  }

  function handleSkipClick() {
    if (snapshot.state.type === 'available') {
      void controller.skipVersion(snapshot.state.info.version);
    }
  }

  function handleCloseClick() {
    controller.closeModal();
  }
</script>

{#if snapshot.isModalOpen}
  <div class="scrim" role="presentation" onclick={handleScrimClick}>
    <div class="dialog" role="dialog" aria-modal="true" aria-labelledby="updater-title">
      <!-- HEADER -->
      <div class="header">
        <div class="icon-badge" class:accent={snapshot.state.type === 'available'} class:success={snapshot.state.type === 'upToDate'}>
          {#if snapshot.state.type === 'upToDate'}
            <svg viewBox="0 0 24 24" width="24" height="24" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round">
              <polyline points="20 6 9 17 4 12"></polyline>
            </svg>
          {:else if snapshot.state.type === 'failed'}
            <svg viewBox="0 0 24 24" width="24" height="24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
              <circle cx="12" cy="12" r="10"></circle>
              <line x1="12" y1="8" x2="12" y2="12"></line>
              <line x1="12" y1="16" x2="12.01" y2="16"></line>
            </svg>
          {:else}
            <svg viewBox="0 0 24 24" width="24" height="24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
              <path d="M12 2v4M12 18v4M4.93 4.93l2.83 2.83M16.24 16.24l2.83 2.83M2 12h4M18 12h4M4.93 19.07l2.83-2.83M16.24 7.76l2.83-2.83"></path>
            </svg>
          {/if}
        </div>

        <div class="header-text">
          <h2 id="updater-title">
            {#if snapshot.state.type === 'available'}
              {$t('windows.ui.updateAvailable')}
            {:else if snapshot.state.type === 'checking'}
              {$t('windows.ui.checkingForUpdates')}
            {:else if snapshot.state.type === 'upToDate'}
              {$t('windows.ui.sideBIsUpToDate')}
            {:else if snapshot.state.type === 'downloading'}
              {$t('update.downloading')}
            {:else if snapshot.state.type === 'installing'}
              {$t('update.installing')}
            {:else if snapshot.state.type === 'failed'}
              {$t('windows.ui.updateError')}
            {:else}
              {$t('windows.ui.softwareUpdate')}
            {/if}
          </h2>

          <p class="subtitle">
            {#if snapshot.state.type === 'available'}
              {$t('windows.ui.aNewVersionOfSideBIsReadyToInstall')}
            {:else if snapshot.state.type === 'checking'}
              {$t('windows.ui.lookingForRecentVersionsOnGitHubReleases')}
            {:else if snapshot.state.type === 'upToDate'}
              {$t('windows.ui.theLatestVersionIsInstalledOnYourComputer')}
            {:else if snapshot.state.type === 'downloading'}
              {$t('windows.ui.downloadingTheWindowsPackageDirectlyFromGitHubReleases')}
            {:else if snapshot.state.type === 'installing'}
              {$t('windows.ui.sideBWillCloseAndRestartAutomaticallyWithTheNewVersion')}
            {:else if snapshot.state.type === 'failed'}
              {$t('windows.ui.couldnTCompleteTheUpdateOperation')}
            {/if}
          </p>

          {#if snapshot.state.type === 'available'}
            <div class="version-badges">
              <span class="badge current">
                <span class="badge-label">{$t('windows.ui.installed')}</span>
                <strong>{snapshot.currentVersion}</strong>
              </span>
              <span class="arrow">→</span>
              <span class="badge new">
                <span class="badge-label">{$t('windows.ui.new')}</span>
                <strong>{snapshot.state.info.version}</strong>
              </span>
            </div>
          {/if}
        </div>

        {#if snapshot.state.type !== 'installing'}
          <button
            bind:this={closeButton}
            type="button"
            class="close-btn"
            aria-label={$t('windows.ui.closeDialog')}
            onclick={handleCloseClick}
          >
            ×
          </button>
        {/if}
      </div>

      <!-- BODY CONTENT -->
      <div class="body">
        {#if snapshot.state.type === 'checking'}
          <div class="status-box center">
            <div class="spinner"></div>
            <p>{$t('windows.ui.checkingForNewVersionsOnGitHubReleases')}</p>
          </div>

        {:else if snapshot.state.type === 'upToDate'}
          <div class="status-box center success-box">
            <svg viewBox="0 0 24 24" width="44" height="44" fill="none" stroke="#4ade80" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
              <path d="M22 11.08V12a10 10 0 1 1-5.93-9.14"></path>
              <polyline points="22 4 12 14.01 9 11.01"></polyline>
            </svg>
            <p class="highlight-text">{$t('windows.update.version', [snapshot.state.version])}</p>
            <p class="detail-text">{$t('windows.ui.sideBIsUpToDateWithTheLatestImprovements')}</p>
          </div>

        {:else if snapshot.state.type === 'available'}
          <div class="fix-report-section">
            <div class="section-title">
              <svg viewBox="0 0 24 24" width="16" height="16" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
                <polygon points="12 2 15.09 8.26 22 9.27 17 14.14 18.18 21.02 12 17.77 5.82 21.02 7 14.14 2 9.27 8.91 8.26 12 2"></polygon>
              </svg>
              <span>{$t('update.release_notes_heading')}</span>
            </div>
            <div class="fix-report-scroll">
              <ReleaseNotes text={snapshot.state.info.releaseNotes} {onOpenExternal} />
            </div>
          </div>

        {:else if snapshot.state.type === 'downloading'}
          <div class="download-section">
            <div class="download-header">
              <span>{$t('windows.ui.downloadingSideB')}</span>
              <span class="percentage">{Math.round(snapshot.state.progress * 100)}%</span>
            </div>
            <div class="progress-bar">
              <div class="progress-fill" style="width: {snapshot.state.progress * 100}%"></div>
            </div>
            <p class="download-hint">{$t('windows.ui.preparingTheWindowsUpdateInstaller')}</p>
          </div>

        {:else if snapshot.state.type === 'installing'}
          <div class="status-box center">
            <div class="spinner"></div>
            <p class="highlight-text">{$t('update.installing')}</p>
            <p class="detail-text">{$t('windows.ui.theAppWillRestartAutomaticallyInAFewSeconds')}</p>
          </div>

        {:else if snapshot.state.type === 'failed'}
          <div class="status-box center error-box">
            <p class="error-title">{$t('windows.ui.couldnTUpdate')}</p>
            <p class="error-message">{resolveMessage(snapshot.state.message, $language)}</p>
          </div>
        {/if}
      </div>

      <!-- FOOTER -->
      <div class="footer">
        {#if snapshot.state.type === 'available'}
          <button type="button" class="btn btn-ghost" onclick={handleSkipClick}>
            {$t('update.skip_version')}
          </button>
          <div class="spacer"></div>
          <button type="button" class="btn btn-secondary" onclick={handleCloseClick}>
            {$t('windows.ui.later')}
          </button>
          <button type="button" class="btn btn-primary" onclick={handleUpdateClick}>
            {$t('update.update_now')}
          </button>

        {:else if snapshot.state.type === 'upToDate' || snapshot.state.type === 'failed'}
          <div class="spacer"></div>
          <button type="button" class="btn btn-primary" onclick={handleCloseClick}>
            {$t('menu.accept')}
          </button>
        {/if}
      </div>
    </div>
  </div>
{/if}

<style>
  .scrim {
    position: fixed;
    inset: 0;
    z-index: 9999;
    display: grid;
    place-items: center;
    padding: 24px;
    background: rgb(0 0 0 / 68%);
    backdrop-filter: blur(8px);
  }

  .dialog {
    width: min(540px, 100%);
    max-height: min(85vh, 620px);
    overflow: hidden;
    display: flex;
    flex-direction: column;
    border: 1px solid var(--sideb-surface-border, rgb(255 255 255 / 10%));
    border-radius: 16px;
    color: #f7f7f8;
    background: #24242a;
    box-shadow: 0 24px 80px rgb(0 0 0 / 60%);
  }

  .header {
    display: flex;
    align-items: flex-start;
    gap: 16px;
    padding: 22px 24px 16px;
    border-bottom: 1px solid var(--sideb-surface-border, rgb(255 255 255 / 8%));
  }

  .icon-badge {
    flex: none;
    width: 48px;
    height: 48px;
    border-radius: 12px;
    display: grid;
    place-items: center;
    background: rgb(255 255 255 / 8%);
    color: #a6a6ad;
  }

  .icon-badge.accent {
    background: rgb(163 61 69 / 20%);
    color: #d06c70;
  }

  .icon-badge.success {
    background: rgb(74 222 128 / 15%);
    color: #4ade80;
  }

  .header-text {
    flex: 1;
    min-width: 0;
  }

  h2 {
    margin: 0 0 4px;
    font-size: 18px;
    font-weight: 600;
  }

  .subtitle {
    margin: 0;
    color: #a6a6ad;
    font-size: 13px;
    line-height: 1.4;
  }

  .version-badges {
    display: flex;
    align-items: center;
    gap: 8px;
    margin-top: 10px;
    font-size: 12px;
  }

  .badge {
    display: inline-flex;
    align-items: center;
    gap: 4px;
    padding: 3px 8px;
    border-radius: 6px;
    background: rgb(255 255 255 / 6%);
    border: 1px solid rgb(255 255 255 / 8%);
  }

  .badge.new {
    background: rgb(163 61 69 / 15%);
    border-color: rgb(208 108 112 / 30%);
    color: #fff;
  }

  .badge-label {
    color: #8c8c94;
    font-size: 11px;
  }

  .arrow {
    color: #63636b;
    font-weight: bold;
  }

  .close-btn {
    flex: none;
    width: 30px;
    height: 30px;
    border: 0;
    border-radius: 50%;
    color: #a6a6ad;
    background: rgb(255 255 255 / 6%);
    font-size: 20px;
    line-height: 1;
    cursor: pointer;
    display: grid;
    place-items: center;
    transition: background 0.15s ease, color 0.15s ease;
  }

  .close-btn:hover {
    background: rgb(255 255 255 / 12%);
    color: #fff;
  }

  .body {
    padding: 20px 24px;
    overflow: auto;
    flex: 1;
  }

  .section-title {
    display: flex;
    align-items: center;
    gap: 8px;
    font-size: 13px;
    font-weight: 600;
    color: #e2e2e6;
    margin-bottom: 8px;
  }

  .fix-report-scroll {
    max-height: 190px;
    overflow-y: auto;
    padding: 12px 14px;
    background: rgb(0 0 0 / 25%);
    border: 1px solid rgb(255 255 255 / 8%);
    border-radius: 10px;
  }

  .fix-report-scroll :global(pre) {
    margin: 0;
    font-family: inherit;
    font-size: 13px;
    line-height: 1.55;
    color: #c8c8cf;
    white-space: pre-wrap;
    word-break: break-word;
  }

  .download-section {
    display: flex;
    flex-direction: column;
    gap: 10px;
    padding: 14px 0;
  }

  .download-header {
    display: flex;
    justify-content: space-between;
    font-size: 13px;
    font-weight: 600;
    color: #e2e2e6;
  }

  .percentage {
    font-family: monospace;
    color: #d06c70;
  }

  .progress-bar {
    width: 100%;
    height: 8px;
    border-radius: 4px;
    background: rgb(255 255 255 / 10%);
    overflow: hidden;
  }

  .progress-fill {
    height: 100%;
    background: linear-gradient(90deg, #a33d45, #d06c70);
    border-radius: 4px;
    transition: width 0.15s ease;
  }

  .download-hint {
    margin: 0;
    font-size: 12px;
    color: #8c8c94;
  }

  .status-box {
    display: flex;
    flex-direction: column;
    align-items: center;
    justify-content: center;
    gap: 12px;
    min-height: 140px;
    text-align: center;
    color: #c8c8cf;
    font-size: 13px;
  }

  .spinner {
    width: 30px;
    height: 30px;
    border: 3px solid rgb(255 255 255 / 15%);
    border-top-color: #d06c70;
    border-radius: 50%;
    animation: spin 0.8s linear infinite;
  }

  @keyframes spin {
    to { transform: rotate(360deg); }
  }

  .highlight-text {
    margin: 0;
    font-weight: 600;
    font-size: 14px;
    color: #fff;
  }

  .detail-text {
    margin: 0;
    font-size: 12px;
    color: #8c8c94;
  }

  .error-box {
    color: #f87171;
  }

  .error-title {
    margin: 0;
    font-weight: 600;
    font-size: 14px;
  }

  .error-message {
    margin: 0;
    font-size: 12px;
    color: #a6a6ad;
    max-width: 400px;
  }

  .footer {
    display: flex;
    align-items: center;
    gap: 10px;
    padding: 16px 24px;
    border-top: 1px solid var(--sideb-surface-border, rgb(255 255 255 / 8%));
    background: rgb(0 0 0 / 12%);
  }

  .spacer {
    flex: 1;
  }

  .btn {
    padding: 8px 16px;
    border-radius: 8px;
    font-size: 13px;
    font-weight: 500;
    cursor: pointer;
    border: 0;
    transition: background 0.15s ease, opacity 0.15s ease;
  }

  .btn:focus-visible {
    outline: 2px solid var(--sideb-highlight, #d06c70);
    outline-offset: 2px;
  }

  .btn-ghost {
    background: transparent;
    color: #8c8c94;
    padding: 8px 10px;
  }

  .btn-ghost:hover {
    color: #e2e2e6;
  }

  .btn-secondary {
    background: rgb(255 255 255 / 8%);
    color: #e2e2e6;
  }

  .btn-secondary:hover {
    background: rgb(255 255 255 / 14%);
  }

  .btn-primary {
    background: var(--sideb-accent, #a33d45);
    color: #fff;
  }

  .btn-primary:hover {
    background: var(--sideb-highlight, #d06c70);
  }
</style>
