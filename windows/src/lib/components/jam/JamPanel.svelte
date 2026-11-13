<script lang="ts">
  import '$lib/styles/controls.css';
  import { onMount, tick } from 'svelte';
  import { t, language } from '$lib/i18n';
  import ControlButton from '$lib/components/common/ControlButton.svelte';
  import type { JamActions, JamMatchedSong, JamViewState } from '$lib/jam/types';
  import type { SongDto } from '$lib/types';
  import JamAvatar from './JamAvatar.svelte';
  import JamDebugPanel from './JamDebugPanel.svelte';
  import JamOffsetControl from './JamOffsetControl.svelte';
  import JamVersionPicker from './JamVersionPicker.svelte';
  import { durationDelta, formatMs, formatSecs, inviteCardTitle, inviteParticipantsLabel, isJamPhase, jamText, jamTitle, syncLabel } from './view';

  interface Props {
    state: JamViewState;
    actions: JamActions;
    /** Raw YouTube Music song search for "choose another version". */
    searchSongs: (query: string) => Promise<SongDto[]>;
    /** `popover` is the Connections flyout; `fullscreen` the Jam tab over the fullscreen scene. */
    variant?: 'popover' | 'fullscreen';
  }
  let { state: jam, actions, searchSongs, variant = 'popover' }: Props = $props();

  let link = $state('');
  let showVersions = $state(false);
  let showSync = $state(false);
  let showDebug = $state(false);
  let menuOpen = $state(false);
  let menuButton = $state<HTMLButtonElement>();
  let menu = $state<HTMLDivElement>();
  let busy = $state(false);

  const live = $derived(isJamPhase(jam.phase));
  const stage = $derived(jam.phase === 'joining' ? 'connecting' : live ? 'live' : 'join');
  const trimmed = $derived(link.trim());
  const linkLooksWrong = $derived(trimmed !== '' && !trimmed.toLowerCase().includes('spotify'));
  const needsSignInMessage = $derived(jam.phase === 'error' && /notSignedIn|authRequired/.test(jam.messageKey ?? ''));
  const access = $derived(!jam.runtime.pluginAvailable ? 'pluginMissing' : jam.runtime.signedIn === false || needsSignInMessage ? 'needsLogin' : 'ready');
  const title = $derived(stage === 'live' ? jamTitle(jam, $language) : $t('jam.panel.title'));
  const participants = $derived(jam.members.length === 1 ? $t('jam.participants.one') : $t('jam.participants.many', [jam.members.length]));
  const shownMembers = $derived(jam.members.slice(0, 4));
  const label = $derived(syncLabel(jam));
  const delta = $derived(durationDelta(jam.current));
  const current = $derived(jam.current);
  const failureText = $derived(jam.phase === 'error' && jam.messageKey ? jamText(jam.messageKey, undefined, $language) : null);
  const endedText = $derived(jam.phase === 'ended' ? `${jamText(jam.messageKey ?? 'jam.ended.left', undefined, $language)} ${$t('jam.ended.body')}` : null);
  const statusText = $derived({
    synced: $t('jam.status.synced'), adjusting: $t('jam.status.adjusting'), paused: $t('jam.status.paused'),
    hostInactive: $t('jam.status.hostInactive'), searching: $t('jam.status.searching'), noMatch: $t('jam.status.noMatch'), waiting: $t('jam.status.waiting'),
  }[label]);
  const statusTone = $derived(label === 'synced' ? 'ok' : label === 'hostInactive' || label === 'noMatch' ? 'warn' : label === 'adjusting' ? 'accent' : 'muted');

  onMount(() => { void actions.refreshStatus(); });

  async function join() {
    if (!trimmed || busy) return;
    busy = true;
    try { await actions.join(trimmed); } finally { busy = false; }
  }
  async function paste() {
    try { const text = await navigator.clipboard.readText(); if (text) link = text.trim(); } catch { /* No clipboard permission: the field stays editable. */ }
  }
  function pick(song: JamMatchedSong) {
    if (!current) return;
    void actions.correctMatch(current.key, song);
    showVersions = false;
  }

  function closeMenu(restoreFocus = false) {
    menuOpen = false;
    if (restoreFocus) menuButton?.focus({ preventScroll: true });
  }
  async function toggleMenu() {
    menuOpen = !menuOpen;
    if (menuOpen) { await tick(); menu?.querySelector<HTMLButtonElement>('[role^="menuitem"]')?.focus(); }
  }
  function menuKeydown(event: KeyboardEvent) {
    const items = [...(menu?.querySelectorAll<HTMLButtonElement>('[role^="menuitem"]') ?? [])];
    const at = items.indexOf(document.activeElement as HTMLButtonElement);
    if (event.key === 'Escape') { event.preventDefault(); event.stopPropagation(); closeMenu(true); }
    else if (event.key === 'ArrowDown' || event.key === 'ArrowUp') {
      event.preventDefault(); items[(at + (event.key === 'ArrowDown' ? 1 : -1) + items.length) % items.length]?.focus();
    } else if (event.key === 'Tab') closeMenu();
  }
  function outsideMenu(event: PointerEvent) {
    if (menuOpen && event.target instanceof Node && !menu?.contains(event.target) && !menuButton?.contains(event.target)) closeMenu();
  }
</script>

<svelte:window onpointerdown={outsideMenu} />

<div class="panel" class:fullscreen={variant === 'fullscreen'} data-jam-panel data-stage={stage}>
  <header>
    <span class="glyph" aria-hidden="true">
      <svg viewBox="0 0 24 24" fill="currentColor"><circle cx="8" cy="8" r="3" /><path d="M2.500 20c0-3.600 2.500-5.700 5.500-5.700s5.500 2.100 5.500 5.700Z" />{#if stage === 'live'}<path d="M16.500 9.500a3.500 3.500 0 0 1 0 5M19.500 7a7 7 0 0 1 0 10" fill="none" stroke="currentColor" stroke-width="1.900" stroke-linecap="round" />{:else}<circle cx="16.500" cy="9" r="2.600" /><path d="M16 14.300c3-.4 5.500 1.200 5.500 5.700H16Z" />{/if}</svg>
    </span>
    <div class="heading">
      <h2 data-jam-title>{title}</h2>
      {#if stage === 'live'}<p data-jam-participants>{participants}</p>{/if}
    </div>
    <div class="more">
      <button bind:this={menuButton} type="button" class="more-button" aria-haspopup="menu" aria-expanded={menuOpen} aria-label={$t('jam.menu.more')} title={$t('jam.menu.more')} data-jam-more onclick={toggleMenu}>
        <svg viewBox="0 0 24 24" fill="currentColor" aria-hidden="true"><circle cx="5" cy="12" r="1.800" /><circle cx="12" cy="12" r="1.800" /><circle cx="19" cy="12" r="1.800" /></svg>
      </button>
      {#if menuOpen}
        <div bind:this={menu} class="menu" role="menu" aria-label={$t('jam.menu.more')} tabindex="-1" onkeydown={menuKeydown}>
          <button type="button" role="menuitemcheckbox" aria-checked={showSync} data-jam-menu="sync" onclick={() => { showSync = !showSync; closeMenu(true); }}><span class="tick" aria-hidden="true">{showSync ? '✓' : ''}</span>{$t('jam.menu.syncSettings')}</button>
          <button type="button" role="menuitemcheckbox" aria-checked={showDebug} data-jam-menu="debug" onclick={() => { showDebug = !showDebug; closeMenu(true); }}><span class="tick" aria-hidden="true">{showDebug ? '✓' : ''}</span>{$t('jam.menu.debug')}</button>
          {#if jam.runtime.signedIn === true}
            <hr />
            <button type="button" role="menuitem" data-jam-menu="signout" onclick={() => { closeMenu(true); void actions.signOut(); }}><span class="tick" aria-hidden="true"></span>{$t('jam.menu.signOut')}</button>
          {/if}
        </div>
      {/if}
    </div>
  </header>

  {#if stage === 'join'}
    {#if endedText}
      <div class="banner ok" role="status"><svg viewBox="0 0 24 24" fill="currentColor" aria-hidden="true"><path d="M12 2a10 10 0 1 0 0 20 10 10 0 0 0 0-20Zm4.600 7.600-5.400 6a.9.9 0 0 1-1.300.1l-2.600-2.400 1.200-1.300 1.900 1.700 4.800-5.300Z" /></svg><div><b>{$t('jam.ended.title')}</b><span data-jam-message>{endedText}</span></div></div>
    {/if}
    {#if failureText}
      <div class="banner warn" role="alert"><svg viewBox="0 0 24 24" fill="currentColor" aria-hidden="true"><path d="M12 2.500 1.500 21h21Zm-1 6h2v6h-2Zm0 8h2v2h-2Z" /></svg><div><b>{$t('jam.failure.title')}</b><span data-jam-message>{failureText}</span></div></div>
    {/if}
    {#if access === 'pluginMissing'}
      <div class="card" data-jam-access="pluginMissing"><b>{$t('jam.plugin.missing.title')}</b><p>{$t('jam.plugin.missing.body')}</p></div>
    {:else if access === 'needsLogin'}
      <div class="intro"><p class="lead">{$t('jam.panel.intro')}</p><p class="hint">{$t('jam.panel.introHint')}</p></div>
      <div class="card" data-jam-access="needsLogin">
        <b>{$t('jam.signin.title')}</b>
        <p>{$t(needsSignInMessage ? 'jam.signin.failed' : 'jam.signin.body')}</p>
        <ControlButton emphasis="prominent" data-jam-signin data-autofocus onclick={() => void actions.openLogin($t('jam.signin.title'))}>{$t(needsSignInMessage ? 'jam.signin.retry' : 'jam.signin.button')}</ControlButton>
      </div>
    {:else}
      <div class="intro"><p class="lead">{$t('jam.panel.intro')}</p><p class="hint">{$t('jam.panel.introHint')}</p></div>
      {#if jam.invites.length > 0}
        <div class="invites-section" data-jam-invites>
          <span class="caption">{$t('jam.invites.section')}</span>
          <div class="invites-list">
            {#each jam.invites as invite (invite.id)}
              {@const cardTitle = inviteCardTitle(invite, $language)}
              <div class="invite-card" data-jam-invite-id={invite.id}>
                <JamAvatar name={invite.senderName} imageUrl={invite.senderImageUrl} size={32} />
                <div class="invite-copy">
                  <b title={cardTitle}>{cardTitle}</b>
                  <span>{inviteParticipantsLabel(invite, $language)}</span>
                </div>
                <div class="invite-actions">
                  <ControlButton
                    size="utility"
                    emphasis="prominent"
                    disabled={busy}
                    data-jam-invite-join={invite.id}
                    aria-label={`${$t('jam.invite.join')}, ${cardTitle}`}
                    onclick={() => void actions.joinInvite(invite)}
                  >
                    {$t('jam.invite.join')}
                  </ControlButton>
                  <button
                    type="button"
                    class="invite-dismiss"
                    title={$t('jam.invite.dismiss')}
                    aria-label={`${$t('jam.invite.dismiss')}, ${cardTitle}`}
                    data-jam-invite-dismiss={invite.id}
                    onclick={() => actions.dismissInvite(invite.id)}
                  >
                    <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.600" stroke-linecap="round" aria-hidden="true"><path d="M6 6 18 18M18 6 6 18" /></svg>
                  </button>
                </div>
              </div>
            {/each}
          </div>
        </div>
      {/if}
      <div class="field" class:wrong={linkLooksWrong}>
        <svg class="link-icon" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M10 14a4.500 4.500 0 0 0 6.400 0l3-3a4.500 4.500 0 0 0-6.400-6.400l-1 1M14 10a4.500 4.500 0 0 0-6.400 0l-3 3a4.500 4.500 0 0 0 6.400 6.400l1-1" /></svg>
        <input type="text" inputmode="url" autocomplete="off" spellcheck="false" bind:value={link} placeholder={$t('jam.link.placeholder')} aria-label={$t('jam.link.label')} aria-invalid={linkLooksWrong || undefined} data-jam-link data-autofocus onkeydown={(event) => { if (event.key === 'Enter') { event.preventDefault(); void join(); } }} />
        {#if trimmed === ''}
          <button type="button" class="text-button" title={$t('jam.link.pasteHelp')} data-jam-paste onclick={paste}>{$t('jam.link.paste')}</button>
        {:else}
          <button type="button" class="clear" title={$t('jam.link.clear')} aria-label={$t('jam.link.clear')} data-jam-clear onclick={() => link = ''}><svg viewBox="0 0 24 24" fill="currentColor" aria-hidden="true"><path d="M12 2a10 10 0 1 0 0 20 10 10 0 0 0 0-20Zm4 12.600-1.400 1.400-2.600-2.600-2.600 2.600L8 14.600 10.600 12 8 9.400 9.400 8l2.600 2.600L14.600 8 16 9.400 13.400 12Z" /></svg></button>
        {/if}
      </div>
      {#if linkLooksWrong}<p class="field-warn" role="status"><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" aria-hidden="true"><circle cx="12" cy="12" r="9.500" /><path d="M12 7v6M12 16.500v.5" stroke-linecap="round" /></svg>{$t('jam.link.looksWrong')}</p>{/if}
      <ControlButton emphasis="prominent" disabled={!trimmed || busy} title={trimmed ? undefined : $t('jam.join.needsLink')} data-jam-join onclick={() => void join()}>
        <svg viewBox="0 0 24 24" fill="currentColor" aria-hidden="true"><path d="M12 2a10 10 0 1 0 0 20 10 10 0 0 0 0-20Zm1 5.600 4.400 4.400-4.400 4.400-1.300-1.300 2.200-2.200H7v-1.800h6.900l-2.200-2.200Z" /></svg>{$t('jam.join')}
      </ControlButton>
      {#if jam.runtime.signedIn === true}
        <p class="signed"><svg viewBox="0 0 24 24" fill="currentColor" aria-hidden="true"><path d="M12 2a10 10 0 1 0 0 20 10 10 0 0 0 0-20Zm4.600 7.600-5.400 6a.9.9 0 0 1-1.300.1l-2.600-2.400 1.200-1.300 1.900 1.700 4.800-5.300Z" /></svg>{$t('jam.signin.connected')}</p>
      {/if}
    {/if}
  {:else if stage === 'connecting'}
    <div class="card connecting" data-jam-access="connecting" role="status"><span class="spinner" aria-hidden="true"></span><div><b>{$t('jam.connecting.title')}</b><p>{$t('jam.connecting.hint')}</p></div></div>
    <ControlButton size="utility" data-jam-cancel onclick={() => void actions.leave()}>{$t('jam.cancel')}</ControlButton>
  {:else}
    {#if jam.phase === 'reconnecting'}<p class="reconnecting" role="status" data-jam-reconnecting><span class="spinner" aria-hidden="true"></span>{$t('windows.jam.reconnecting')}</p>{/if}
    <div class="card pairing" data-jam-pairing>
      {#if current}
        <span class="caption">{$t('jam.pairing.spotify')}</span>
        <div class="track"><div class="text"><b title={current.title}>{current.title}</b>{#if current.artists}<span title={current.artists}>{current.artists}</span>{/if}</div>{#if current.durationMs}<time>{formatMs(current.durationMs)}</time>{/if}</div>
        <svg class="arrow" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="3" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M12 5v14m-6-6 6 6 6-6" /></svg>
        <span class="caption">{$t('jam.pairing.ytm')}</span>
        {#if current.matched}
          <div class="track version" data-jam-match>
            <span class="cover" aria-hidden="true">{#if current.matched.thumbnail}<img src={current.matched.thumbnail} alt="" decoding="async" draggable="false" />{:else}<svg viewBox="0 0 24 24" fill="currentColor"><path d="M10 5v12.1a4 4 0 1 1-2-3.46V3l12-2v14.1a4 4 0 1 1-2-3.46V4.4z" /></svg>{/if}</span>
            <div class="text"><b title={current.matched.title}>{current.matched.title}</b>{#if current.matched.artists}<span title={current.matched.artists}>{current.matched.artists}</span>{/if}</div>
            {#if current.matched.durationSecs}<time>{formatSecs(current.matched.durationSecs)}</time>{/if}
          </div>
        {:else if label === 'searching'}
          <p class="searching"><span class="spinner" aria-hidden="true"></span>{$t('jam.pairing.searching')}</p>
        {:else}
          <div class="no-match" data-jam-nomatch><b>{$t('jam.pairing.noMatch')}</b><span>{$t('jam.pairing.noMatchHint')}</span></div>
        {/if}
        {#if delta !== null}<p class="warn-line" data-jam-duration-warning><svg viewBox="0 0 24 24" fill="currentColor" aria-hidden="true"><path d="M12 2.500 1.500 21h21Zm-1 6h2v6h-2Zm0 8h2v2h-2Z" /></svg>{$t(delta > 0 ? 'jam.pairing.longer' : 'jam.pairing.shorter', [Math.round(Math.abs(delta))])}</p>{/if}
      {:else}
        <p class="waiting">{$t('jam.pairing.waiting')}</p>
      {/if}
      <hr />
      <div class="footer">
        <span class={`status ${statusTone}`} role="status" aria-label={$t('jam.status.label')} data-jam-status={label} title={label === 'hostInactive' ? $t('jam.status.hostInactive.help') : undefined}>
          {#if label === 'searching' || label === 'adjusting'}<span class="spinner small" aria-hidden="true"></span>{:else}<i aria-hidden="true"></i>{/if}<span>{statusText}</span>
        </span>
        {#if current}
          <button type="button" class="text-button choose" aria-expanded={showVersions} data-jam-choose onclick={() => showVersions = !showVersions}>{$t(showVersions ? 'jam.versions.hide' : 'jam.versions.choose')}<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="3.500" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true" class:flipped={showVersions}><path d="m6 9 6 6 6-6" /></svg></button>
        {/if}
      </div>
    </div>
    {#if showVersions && current}
      {#key current.key}
        <JamVersionPicker query={[current.title, current.artists].filter(Boolean).join(' ')} currentVideoId={current.matched?.videoId ?? null} search={searchSongs} onPick={pick} onClose={() => showVersions = false} />
      {/key}
    {/if}
    <div class="card members" data-jam-members>
      {#each shownMembers as member, index (member.id + ':' + index)}
        <div class="member" class:me={member.isMe}>
          <JamAvatar name={member.name} imageUrl={member.imageUrl} size={26} />
          <span class="name" title={member.name || undefined}>{member.name || $t('jam.member.guest')}</span>
          {#if member.isHost}<span class="tag host">{$t('jam.member.host')}</span>{:else if member.isMe}<span class="tag">{$t('jam.member.you')}</span>{/if}
        </div>
      {/each}
      {#if jam.members.length > shownMembers.length}<p class="more-members">{$t('jam.members.more', [jam.members.length - shownMembers.length])}</p>{/if}
    </div>
    {#if !jam.canControl}<p class="no-control" data-jam-nocontrol><svg viewBox="0 0 24 24" fill="currentColor" aria-hidden="true"><path d="M7 10V8a5 5 0 0 1 10 0v2h1.500v11h-13V10Zm2 0h6V8a3 3 0 0 0-6 0Z" /></svg>{$t('jam.control.noControl')}</p>{/if}
  {/if}

  {#if showSync && stage !== 'connecting'}
    <div class="card" data-jam-sync>
      <span class="caption">{$t('jam.sync.title')}</span>
      <JamOffsetControl title={$t('windows.jam.debug.manual')} hint={$t('windows.jam.sync.manualHint')} value={jam.sync.manualOffsetMs} onChange={ms => actions.setManualOffset(ms)} />
    </div>
  {/if}
  {#if showDebug}<JamDebugPanel state={jam} {actions} onClose={() => showDebug = false} />{/if}

  {#if stage === 'live'}
    <ControlButton size="utility" title={$t('jam.leave.help')} data-jam-leave onclick={() => void actions.leave()}>
      <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M9 21H5a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h4M16 17l5-5-5-5M21 12H9" /></svg>{$t('jam.leave')}
    </ControlButton>
  {/if}
</div>

<style>
  .panel { display: flex; flex-direction: column; gap: 14px; box-sizing: border-box; width: 100%; min-width: 0; padding: 16px; color: #f3f3f6; font-size: 13px; line-height: 1.35; text-align: left; }
  .panel.fullscreen { height: 100%; overflow-y: auto; padding: 24px; scrollbar-width: thin; scrollbar-color: rgb(255 255 255 / 28%) transparent; }
  p, h2, b { margin: 0; }
  header { display: flex; align-items: center; gap: 10px; }
  .glyph { display: grid; flex: none; place-items: center; width: 32px; height: 32px; border-radius: 9px; color: #fff; background: color-mix(in srgb, var(--sideb-accent) 90%, transparent); }
  .glyph svg { width: 18px; height: 18px; }
  .heading { flex: 1; min-width: 0; }
  h2 { overflow: hidden; font-size: 15px; font-weight: 600; text-overflow: ellipsis; white-space: nowrap; }
  .heading p { color: rgb(255 255 255 / 70%); font-size: 12px; }
  .more { position: relative; flex: none; }
  .more-button { display: grid; place-items: center; width: 28px; height: 28px; padding: 0; border: 0; border-radius: 7px; color: rgb(255 255 255 / 70%); background: transparent; cursor: pointer; }
  .more-button:hover, .more-button[aria-expanded='true'] { color: #fff; background: rgb(255 255 255 / 10%); } .more-button svg { width: 18px; height: 18px; }
  .menu { position: absolute; z-index: 5; top: calc(100% + 4px); right: 0; box-sizing: border-box; min-width: 220px; padding: 5px; border: 1px solid rgb(255 255 255 / 12%); border-radius: 9px; background: #29292f; box-shadow: 0 10px 30px rgb(0 0 0 / 45%); }
  .menu button { display: flex; align-items: center; gap: 6px; box-sizing: border-box; width: 100%; min-height: 32px; padding: 6px 9px 6px 4px; border: 0; border-radius: 5px; color: inherit; background: transparent; font: inherit; text-align: left; white-space: nowrap; cursor: pointer; }
  .menu button:hover, .menu button:focus-visible { outline: 0; background: rgb(255 255 255 / 9%); }
  .menu .tick { flex: none; width: 18px; color: var(--sideb-highlight); text-align: center; }
  .menu hr { height: 1px; margin: 4px 6px; border: 0; background: rgb(255 255 255 / 10%); }
  .intro { display: flex; flex-direction: column; gap: 4px; } .lead { font-size: 13px; } .hint { color: rgb(255 255 255 / 60%); font-size: 12px; }
  .card { display: flex; flex-direction: column; gap: 10px; box-sizing: border-box; min-width: 0; padding: 12px; border: 1px solid var(--sideb-surface-border); border-radius: 12px; background: var(--sideb-surface); }
  .card > b { font-size: 13px; font-weight: 600; } .card > p { color: rgb(255 255 255 / 66%); font-size: 12px; }
  .card.connecting { flex-direction: row; align-items: center; gap: 12px; } .card.connecting p { color: rgb(255 255 255 / 66%); font-size: 12px; }
  .banner { display: flex; align-items: flex-start; gap: 10px; padding: 12px; border: .75px solid color-mix(in srgb, var(--tint) 28%, transparent); border-radius: 12px; background: color-mix(in srgb, var(--tint) 12%, transparent); }
  .banner.ok { --tint: #34c759; } .banner.warn { --tint: #ff9f0a; }
  .banner > svg { flex: none; width: 15px; height: 15px; margin-top: 2px; color: var(--tint); }
  .banner div { display: flex; flex-direction: column; gap: 2px; min-width: 0; } .banner b { font-size: 13px; font-weight: 600; } .banner span { color: rgb(255 255 255 / 66%); font-size: 12px; }
  .field { display: flex; align-items: center; gap: 8px; box-sizing: border-box; height: 36px; padding: 0 11px; border: .75px solid var(--sideb-surface-border); border-radius: 10px; background: var(--sideb-surface); }
  .field.wrong { border-color: rgb(255 159 10 / 70%); }
  .field input { flex: 1; min-width: 0; height: 100%; padding: 0; border: 0; outline: 0; color: #f3f3f6; background: transparent; font: inherit; font-size: 13px; }
  .field:focus-within { outline: 2px solid var(--sideb-highlight); outline-offset: 2px; }
  .link-icon { flex: none; width: 13px; height: 13px; color: rgb(255 255 255 / 52%); }
  .text-button { padding: 0; border: 0; color: var(--sideb-highlight); background: transparent; font: inherit; font-size: 12px; font-weight: 600; cursor: pointer; }
  .clear { display: grid; place-items: center; padding: 0; border: 0; color: rgb(255 255 255 / 52%); background: transparent; cursor: pointer; } .clear:hover { color: #fff; } .clear svg { width: 15px; height: 15px; }
  .field-warn { display: flex; align-items: center; gap: 6px; margin-top: -8px; color: #ff9f0a; font-size: 11px; } .field-warn svg { flex: none; width: 12px; height: 12px; }
  .signed { display: flex; align-items: center; gap: 5px; color: rgb(255 255 255 / 52%); font-size: 11px; } .signed svg { width: 13px; height: 13px; color: #34c759; }
  .caption { color: rgb(255 255 255 / 52%); font-size: 10px; font-weight: 600; letter-spacing: .6px; text-transform: uppercase; }
  .track { display: flex; align-items: center; gap: 10px; min-width: 0; }
  .track .text { display: flex; flex: 1; flex-direction: column; gap: 1px; min-width: 0; }
  .text b, .text span { overflow: hidden; text-overflow: ellipsis; white-space: nowrap; } .text b { font-size: 13px; font-weight: 600; } .text span { color: rgb(255 255 255 / 68%); font-size: 12px; }
  time { flex: none; color: rgb(255 255 255 / 52%); font-size: 11px; font-variant-numeric: tabular-nums; }
  .cover { display: grid; place-items: center; flex: none; width: 38px; height: 38px; overflow: hidden; border-radius: 6px; color: rgb(255 255 255 / 45%); background: var(--sideb-surface-hover); } .cover img { width: 100%; height: 100%; object-fit: cover; } .cover svg { width: 16px; height: 16px; }
  .arrow { align-self: center; width: 11px; height: 11px; color: rgb(255 255 255 / 52%); }
  .searching, .waiting { display: flex; align-items: center; gap: 8px; color: rgb(255 255 255 / 66%); font-size: 12px; }
  .no-match { display: flex; flex-direction: column; gap: 2px; } .no-match b { font-size: 12px; font-weight: 500; } .no-match span { color: rgb(255 255 255 / 66%); font-size: 11px; }
  .warn-line { display: flex; align-items: flex-start; gap: 6px; color: #ff9f0a; font-size: 11px; } .warn-line svg { flex: none; width: 12px; height: 12px; margin-top: 1px; }
  hr { width: 100%; height: 1px; margin: 0; border: 0; background: rgb(255 255 255 / 9%); }
  .footer { display: flex; align-items: center; justify-content: space-between; gap: 8px; }
  .status { display: inline-flex; align-items: center; gap: 6px; min-width: 0; font-size: 11px; font-weight: 500; }
  .status i { flex: none; width: 7px; height: 7px; border-radius: 50%; background: currentColor; }
  .status.ok { color: rgb(255 255 255 / 70%); } .status.ok i { background: #34c759; } .status.warn { color: #ff9f0a; } .status.accent { color: var(--sideb-highlight); } .status.muted { color: rgb(255 255 255 / 66%); }
  .choose { display: inline-flex; align-items: center; gap: 3px; flex: none; font-size: 11px; } .choose svg { width: 9px; height: 9px; transition: transform 140ms ease; } .choose svg.flipped { transform: rotate(180deg); }
  .members { gap: 8px; }
  .member { display: flex; align-items: center; gap: 9px; min-width: 0; } .member.me .name { font-weight: 600; }
  .name { flex: 1; min-width: 0; overflow: hidden; font-size: 13px; text-overflow: ellipsis; white-space: nowrap; }
  .tag { flex: none; padding: 2px 7px; border-radius: 999px; color: rgb(255 255 255 / 66%); background: var(--sideb-surface-hover); font-size: 10px; font-weight: 600; } .tag.host { color: #fff; background: color-mix(in srgb, var(--sideb-accent) 85%, transparent); }
  .more-members { color: rgb(255 255 255 / 52%); font-size: 11px; }
  .no-control { display: flex; align-items: flex-start; gap: 6px; color: rgb(255 255 255 / 66%); font-size: 12px; } .no-control svg { flex: none; width: 12px; height: 12px; margin-top: 2px; }
  .reconnecting { display: flex; align-items: center; gap: 8px; color: #ff9f0a; font-size: 12px; }
  .spinner { flex: none; width: 14px; height: 14px; border: 2px solid rgb(255 255 255 / 24%); border-top-color: var(--sideb-highlight); border-radius: 50%; animation: spin .8s linear infinite; } .spinner.small { width: 10px; height: 10px; border-width: 1.5px; }
  @keyframes spin { to { transform: rotate(360deg); } }
  @media (prefers-reduced-motion: reduce) { .spinner { animation-duration: 2.4s; } .choose svg { transition: none; } }
  .invites-section { display: flex; flex-direction: column; gap: 8px; }
  .invites-list { display: flex; flex-direction: column; gap: 8px; }
  .invite-card { display: flex; align-items: center; gap: 10px; box-sizing: border-box; min-width: 0; padding: 10px; border: 1px solid var(--sideb-surface-border); border-radius: 10px; background: var(--sideb-surface); }
  .invite-copy { display: flex; flex: 1; flex-direction: column; gap: 2px; min-width: 0; }
  .invite-copy b, .invite-copy span { overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
  .invite-copy b { font-size: 12.5px; font-weight: 600; }
  .invite-copy span { color: rgb(255 255 255 / 68%); font-size: 11px; }
  .invite-actions { display: flex; flex: none; align-items: center; gap: 4px; }
  .invite-dismiss { display: grid; flex: none; place-items: center; width: 24px; height: 24px; padding: 0; border: 0; border-radius: 50%; color: rgb(255 255 255 / 56%); background: transparent; cursor: pointer; }
  .invite-dismiss:hover { color: #fff; background: var(--sideb-surface-hover); }
  .invite-dismiss svg { width: 10px; height: 10px; }
  button:focus-visible { outline: 2px solid var(--sideb-highlight); outline-offset: 2px; }
</style>
