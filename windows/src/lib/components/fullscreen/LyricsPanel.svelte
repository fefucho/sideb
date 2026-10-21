<script lang="ts">
  import { t } from '$lib/i18n';
  import { onMount, onDestroy, tick, untrack } from 'svelte';
  import { invoke } from '@tauri-apps/api/core';
  import type { PlaybackStateDto } from '$lib/types';
  import type { LyricsState } from '$lib/player/lyrics';
  import { KaraokeController, prepareKaraoke, karaokeFocus, seekSeconds, type KaraokeState } from '$lib/player/karaoke';
  import { KaraokeClock } from '$lib/player/karaoke-clock';
  import { LyricScroller } from '$lib/player/lyric-scroll';
  import KaraokePhrase from './KaraokePhrase.svelte';
  import LyricsWait from './LyricsWait.svelte';
  interface Props { state: LyricsState; playback: PlaybackStateDto; session: number; active?: boolean; onSeek: (seconds:number)=>void; onRetry: ()=>void }
  let { state:classicState, playback, session, active=true, onSeek, onRetry }: Props = $props();
  let rich = $state<KaraokeState>({occurrence:null,status:'idle',refreshing:false,document:null,error:null});
  const controller = new KaraokeController(invoke, next => rich=next);
  const clock = new KaraokeClock(), scroller = new LyricScroller();
  let original=$state(false), reading=$state(false), size=$state(36), following=$state(true), menu=$state(false);
  let motion=$state(true), translations=$state(true), offset=$state(0), reduced=$state(false), contrast=$state(false);
  let focus=$state<number|null>(null), gapIndex=$state(-1), container=$state<HTMLDivElement|null>(null), height=$state(0);
  let centerRevision=0, centered=false, lastOccurrence='', savedScrollTop=0;
  const occurrence=$derived(JSON.stringify([session,playback.queue.items[playback.queue.currentIndex??-1]?.entryId,playback.generation,playback.currentTrack?.videoId]));
  const duration=$derived(Number.isFinite(playback.duration)&&playback.duration>0?playback.duration:playback.currentTrack?.duration??0);
  const currentClassic=$derived.by(()=>{
    if(!classicState.lyrics||!classicState.trackKey||!playback.currentTrack)return null;
    try {
      const [video,generation,scope]=JSON.parse(classicState.trackKey);
      if(video!==playback.currentTrack.videoId||generation!==playback.generation)return null;
      if(typeof scope==='string') {
        const entry=JSON.parse(scope)[1]??null;
        if(entry!==(playback.queue.items[playback.queue.currentIndex??-1]?.entryId??null))return null;
      }
      return classicState.lyrics;
    }catch{return null;}
  });
  const classic=$derived(currentClassic?prepareKaraoke({...currentClassic,instrumental:false,lines:currentClassic.lines.map(line=>({...line,words:[]}))},duration):null);
  const lyricDocument=$derived(!original&&rich.occurrence===occurrence&&rich.document?rich.document:classic);
  const isRich=$derived(!original&&rich.occurrence===occurrence&&!!rich.document);
  const geometry=$derived(JSON.stringify([size,reading,translations]));
  const effectiveOffset=$derived(isRich?offset:0);
  const busy=$derived(original?classicState.status==='loading':rich.refreshing);
  const groupOrdinal=$derived(focus===null?-1:lyricDocument?.ordinals.get(focus)??-1);
  function manual() { ++centerRevision; scroller.cancel(); following=false; }
  function resume() { following=true; centered=false; }
  function seek(ms:number|null) {
    const seconds=seekSeconds(ms,duration,effectiveOffset); if(seconds===null)return;
    ++centerRevision; scroller.cancel(); resume(); onSeek(seconds);
  }
  function scrollKey(event:KeyboardEvent) {
    if(event.target instanceof HTMLInputElement || (event.key===' ' && event.target!==container))return;
    if(['ArrowUp','ArrowDown','PageUp','PageDown','Home','End',' '].includes(event.key))manual();
  }
  function useNew() { original=false; motion=true; translations=true; offset=0; void controller.retry(); }
  function refresh() { if(original)onRetry();else void controller.retry(); }
  function selectSource() { if(isRich){original=true;offset=0;}else useNew(); }
  $effect(()=>{
    const track=playback.currentTrack,key=occurrence,seconds=duration,enabled=active&&!original;
    untrack(()=>controller.setContext(track,key,seconds,enabled));
  });
  $effect(()=>{
    const key=occurrence;
    if(key!==lastOccurrence) { lastOccurrence=key; ++centerRevision; scroller.cancel(); following=true;offset=0;motion=true;translations=true;centered=false;savedScrollTop=0; if(container)container.scrollTop=0; }
  });
  $effect(()=>{
    const pending=typeof playback.seekPending==='number';
    // Pending is a fixed visual preview only; audio position stays engine-observed.
    const position=pending?playback.seekPending!:playback.position,playing=active&&playback.isPlaying&&!playback.isLoading,key=`${occurrence}:${playback.seekRevision??0}`;
    untrack(()=>clock.observe(position,playing,pending,key));
  });
  $effect(()=>{
    if(!active)return;
    const doc=lyricDocument,shift=effectiveOffset;
    return untrack(()=>clock.subscribe(ms=>{
      const next=doc?karaokeFocus(doc,ms+shift):null;if(focus!==next)focus=next;
      const gap=doc?.gaps.findIndex(item=>ms+shift>=item.start&&ms+shift<item.end)??-1;if(gapIndex!==gap)gapIndex=gap;
      return false;
    }));
  });
  $effect(()=>{
    if(!active){++centerRevision;scroller.cancel();if(container)savedScrollTop=container.scrollTop;return;}
    const doc=lyricDocument,index=focus,follow=following,element=container,layout=geometry,h=height,gap=gapIndex;
    const revision=++centerRevision;scroller.cancel();
    if(!follow||!element||!doc||index===null)return;
    void tick().then(()=>{
      if(revision!==centerRevision||!following||container!==element)return;
      const row=element.querySelector<HTMLElement>(gap>=0?`[data-gap="${gap}"]`:`[data-line="${index}"]`);if(!row)return;
      const top=element.scrollTop+row.getBoundingClientRect().top-element.getBoundingClientRect().top-element.clientHeight/2+row.clientHeight/2;
      scroller.center(element,top,centered&&!reduced);centered=true;
    });
  });
  $effect(()=>{
    if(active&&container&&!following) {
      const element=container,top=savedScrollTop;
      untrack(()=>{if(top>0&&element.scrollTop===0)element.scrollTop=top;});
    }
  });
  onMount(()=>{
    const media=window.matchMedia('(prefers-reduced-motion:reduce)'),high=window.matchMedia('(prefers-contrast:more)');
    const sync=()=>{reduced=media.matches;contrast=high.matches;};sync();
    media.addEventListener('change',sync);high.addEventListener('change',sync);
    return()=>{media.removeEventListener('change',sync);high.removeEventListener('change',sync);};
  });
  onDestroy(()=>{controller.dispose();clock.dispose();scroller.cancel();});
</script>
<section class="lyrics-panel" class:reading class:contrast class:manual={!following} class:reduced hidden={!active}
  style={`--size:${size}px;--edge:${active&&lyricDocument?.hasTiming&&!reading?height/2:12}px;--reserve:${reading?0:48}px`} aria-label={$t('windows.ui.songLyrics')}>
  {#if active}
  <div class="options">
    <button class="more" type="button" aria-label={$t('lyrics.experimental.options')} aria-expanded={menu} onclick={()=>menu=!menu}>•••</button>
    {#if menu}
      <div class="menu" role="dialog" tabindex="-1" aria-label={$t('lyrics.experimental.options')} onkeydown={event=>{if(event.key==='Escape')menu=false;}}>
        <button type="button" aria-pressed={!reading} onclick={()=>reading=false}>{$t('lyrics.experimental.mode.karaoke')}</button>
        <button type="button" aria-pressed={reading} onclick={()=>reading=true}>{$t('lyrics.experimental.mode.reading')}</button>
        <label>{$t('lyrics.experimental.textSize')}<input aria-label={$t('lyrics.experimental.textSize')} type="range" min="20" max="48" step="2" bind:value={size}/><output>{size}</output></label>
        {#if isRich}
          {#if lyricDocument?.hasWords}<label><input type="checkbox" bind:checked={motion}/>{$t('lyrics.experimental.wordMotion')}</label>{/if}
          {#if lyricDocument?.hasTranslations}<label><input type="checkbox" bind:checked={translations}/>{$t('lyrics.experimental.translation')}</label>{/if}
          {#if lyricDocument?.hasTiming}
            <label>{$t('lyrics.experimental.offset')}<input aria-label={$t('lyrics.experimental.offset')} type="range" min="-5000" max="5000" step="100" bind:value={offset}/><output>{offset>=0?'+':''}{(offset/1000).toFixed(1)} s</output></label>
            <button type="button" onclick={()=>offset=Math.min(5000,offset+100)} disabled={offset>=5000}>{$t('lyrics.experimental.offset.earlier')}</button>
            <button type="button" onclick={()=>offset=Math.max(-5000,offset-100)} disabled={offset<=-5000}>{$t('lyrics.experimental.offset.later')}</button>
            <button type="button" onclick={()=>offset=0} disabled={offset===0}>{$t('lyrics.experimental.offset.reset')}</button>
          {/if}
        {/if}
        <small>{$t('lyrics.experimental.source',[lyricDocument?.provider??'—'])} · {$t(lyricDocument?.hasWords?'lyrics.experimental.timing.words':lyricDocument?.hasTiming?'lyrics.experimental.timing.lines':'lyrics.experimental.timing.plain')}</small>
        <button type="button" disabled={busy} onclick={refresh}>{$t('lyrics.experimental.refresh')}</button>
        <button type="button" disabled={!isRich&&rich.refreshing} onclick={selectSource}>{$t(isRich?'lyrics.experimental.returnToCurrent':'lyrics.experimental.tryNew')}</button>
      </div>
    {/if}
  </div>
  {#if lyricDocument?.instrumental}
    <div class="message" role="status"><p>{$t('lyrics.experimental.instrumental')}</p><small>{$t('lyrics.experimental.instrumental.detail')}</small></div>
  {:else if lyricDocument?.lines.length}
    <!-- svelte-ignore a11y_no_noninteractive_tabindex, a11y_no_noninteractive_element_interactions -->
    <div class="lyrics-scroll" bind:this={container} bind:clientHeight={height} tabindex="0" role="region" aria-label={$t('windows.ui.lyricsText')}
      onscroll={()=>{if(!following&&container)savedScrollTop=container.scrollTop;}} onwheel={manual} ontouchstart={manual} onkeydown={scrollKey} onpointerdown={event=>{if(event.target===container)manual();}}>
      <div class="lines">
        {#each lyricDocument.groups as group, ordinal (group.anchor)}
          {#each lyricDocument.gaps as gap,i}{#if gap.before===ordinal}<LyricsWait {gap} index={i} {clock} offset={effectiveOffset} animate={!reading&&!reduced&&motion&&active}/>{/if}{/each}
          {@const distance=groupOrdinal<0?0:Math.min(3,Math.abs(groupOrdinal-ordinal))}
          {@const blur=!reading&&following&&!reduced&&!contrast&&distance>0?[0,1.2,2.1,3][distance]:0}
          <div class="group" class:focused={following&&group.anchor===focus} style={`--blur:${blur}px;--opacity:${distance===0||reading?1:contrast?.78:.40};--scale:${distance===0||reduced||reading?1:.98}`}>
            {#each group.indices as index}
              {@const line=lyricDocument.lines[index]}
              <div class="row" class:background={line.background} data-line={index} data-agent={line.agent??undefined} data-section={line.section??undefined}>
                {#if seekSeconds(line.start,duration,effectiveOffset)!==null}
                  <button type="button" class="line" aria-label={`${line.background?$t('lyrics.experimental.voice.background')+'. ':''}${line.text}${isRich&&translations&&line.translation?'. '+line.translation:''}`} aria-current={focus===group.anchor?'true':undefined} title={$t('fullscreen.goToLyricLine')} onclick={()=>seek(line.start)}>
                    <KaraokePhrase {line} {clock} enabled={isRich&&!reading} {motion} {reduced} offset={effectiveOffset} {geometry}/>
                  </button>
                {:else}<div class="line"><KaraokePhrase {line} {clock} enabled={false} {motion} {reduced} offset={effectiveOffset} {geometry}/></div>{/if}
                {#if isRich&&translations&&line.translation}<p class="translation">{line.translation}</p>{/if}
              </div>
            {/each}
          </div>
        {/each}
        {#each lyricDocument.gaps as gap,i}{#if gap.before===lyricDocument.groups.length}<LyricsWait {gap} index={i} {clock} offset={effectiveOffset} animate={!reading&&!reduced&&motion&&active}/>{/if}{/each}
      </div>
    </div>
    {#if !following}<button type="button" class="follow" onclick={resume}>{$t('fullscreen.returnToCurrentLyric')}</button>{/if}
  {:else}
    <div class="message" role="status"><p>{$t(!playback.currentTrack?'lyrics.experimental.noTrack':rich.status==='loading'||classicState.status==='loading'?'lyrics.experimental.loading':rich.status==='error'||classicState.status==='error'?'lyrics.experimental.error':'lyrics.experimental.empty')}</p><button type="button" disabled={busy} onclick={()=>{useNew();onRetry();}}>{$t('lyrics.experimental.retry')}</button></div>
  {/if}
  {#if rich.error&&lyricDocument&&!original}<span class="refresh-error" role="status">{$t('lyrics.experimental.error')}</span>{/if}
  {#if playback.seekError}<span class="refresh-error" role="status">{playback.seekError}</span>{/if}
  {/if}
</section>
<style>
  .lyrics-panel{position:relative;flex:1;width:100%;height:100%;min-width:0;min-height:0;container-type:inline-size;}.lyrics-panel[hidden]{display:none;}
  .lyrics-scroll{height:100%;overflow:auto;overscroll-behavior:contain;scrollbar-width:none;mask-image:linear-gradient(to bottom,transparent,#000 48px,#000 calc(100% - 88px),transparent);}.lyrics-scroll::-webkit-scrollbar{display:none;}
  .lines{padding:var(--edge) calc(32px + var(--reserve)) var(--edge) 32px;}@container(max-width:329px){.lines{padding-inline-start:20px;padding-inline-end:calc(20px + var(--reserve));}}
  .group{content-visibility:auto;contain-intrinsic-size:auto 90px;}.group.focused{content-visibility:visible;}.row{filter:blur(var(--blur));opacity:var(--opacity);transform:scale(var(--scale));transform-origin:left center;transition:opacity .788s,transform .788s,filter .788s;padding-block:10px;}
  .manual .row{filter:none;transition:opacity .788s,transform .788s;}.row:has(:global(.voice-active)){filter:none;opacity:1;transform:none;}.row+.row{padding-top:8px;}
  .line{display:block;width:100%;border:0;background:transparent;padding:0;margin:0;color:inherit;font-family:inherit;font-size:var(--size);font-weight:700;letter-spacing:-.18px;line-height:1.25;text-align:start;}button.line{cursor:pointer;}.background{--row-size:max(18px,calc(var(--size)*.68));}.background .line{font-size:var(--row-size);}
  .translation{font-size:max(13px,calc(var(--size)*.57));line-height:1.25;margin:7px 0 0;opacity:.8;font-weight:500;letter-spacing:0;}.background .translation{font-size:max(13px,calc(var(--row-size)*.57));}.reading .line{font-weight:500;letter-spacing:0;}.reading .row{padding-block:8px;}
  .options{position:absolute;right:8px;top:4px;z-index:3;}.more{width:32px;height:30px;border:0;border-radius:8px;background:#2228;color:white;cursor:pointer;}
  .menu{position:absolute;right:0;top:34px;width:260px;max-height:calc(100dvh - 220px);overflow:auto;display:flex;flex-direction:column;gap:6px;padding:12px;border-radius:10px;border:1px solid #ffffff30;background:#242326f5;box-shadow:0 8px 24px #0006;font-size:13px;}
  .menu button,.message button{color:white;background:#ffffff0c;border:0;padding:8px;text-align:start;border-radius:5px;cursor:pointer;}.menu button[aria-pressed=true]{background:#ffffff25;}.menu label{display:flex;align-items:center;gap:6px;flex-wrap:wrap;padding:6px 0;}.menu input[type=range]{width:125px;}.menu small{opacity:.65;padding:6px 0;}button:disabled{opacity:.4;cursor:default;}
  .follow{position:absolute;bottom:12px;left:50%;transform:translateX(-50%);white-space:nowrap;padding:10px 17px;background:#2c292aee;border:1px solid #ffffff30;border-radius:50px;color:white;cursor:pointer;}
  .message{height:100%;box-sizing:border-box;display:flex;flex-direction:column;align-items:center;justify-content:center;text-align:center;gap:12px;padding:32px;color:#ffffffa0;}.message p{margin:0;}.refresh-error{position:absolute;bottom:12px;left:12px;font-size:12px;color:#fff9;pointer-events:none;}
  button:focus-visible{outline:2px solid white;outline-offset:3px;}.contrast .lyrics-scroll{mask-image:none;}.contrast .row,.reduced .row{filter:none;}.contrast .translation{opacity:.95;}.reduced .row{transition:none;}
  @media(forced-colors:active){.lyrics-scroll{mask-image:none;}.row{filter:none!important;opacity:1!important;}.menu{background:Canvas;color:CanvasText;}.line{color:CanvasText;}}
</style>
