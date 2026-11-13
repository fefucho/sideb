<script lang="ts">
  import type { JamMember } from '$lib/jam/types';
  import JamAvatar from './JamAvatar.svelte';
  import { orderedMembers } from './view';
  /** Overlapping avatars, host first (port of `JamAvatarStack`); a "+N" disc stands for the rest. */
  let { members, size = 22, limit = 4 }: { members: JamMember[]; size?: number; limit?: number } = $props();
  const shown = $derived(orderedMembers(members).slice(0, limit));
  const extra = $derived(members.length - shown.length);
</script>

<span class="stack" style:--size={`${size}px`} aria-hidden="true">
  {#each shown as member, index (member.id + ':' + index)}
    <span class="slot" style:z-index={shown.length - index}><JamAvatar name={member.name} imageUrl={member.imageUrl} {size} ring /></span>
  {/each}
  {#if extra > 0}<span class="more" style:z-index="0">+{extra}</span>{/if}
</span>

<style>
  .stack { display: inline-flex; flex: none; align-items: center; }
  .slot { display: inline-flex; margin-left: calc(var(--size) * -.26); }
  .slot:first-child { margin-left: 0; }
  .more { display: grid; place-items: center; box-sizing: border-box; width: var(--size); height: var(--size); margin-left: calc(var(--size) * -.26); border-radius: 50%; color: #fff; background: rgb(128 128 128 / 60%); box-shadow: 0 0 0 1.5px rgb(0 0 0 / 35%); font-size: calc(var(--size) * .4); font-weight: 600; }
</style>
