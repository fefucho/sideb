<script lang="ts">
  import { avatarTint, initialOf } from './view';
  /** Round participant photo; the initial on a stable colour shows until (or instead of) the image. */
  let { name, imageUrl = null, size = 28, ring = false }: { name: string | null | undefined; imageUrl?: string | null; size?: number; ring?: string | boolean } = $props();
  let failed = $state<string | null>(null);
</script>

<span class="avatar" class:ring={!!ring} style:--size={`${size}px`} style:--tint={avatarTint(name)} style:--ring={typeof ring === 'string' ? ring : undefined} aria-hidden="true">
  <span class="initial">{initialOf(name)}</span>
  {#if imageUrl && failed !== imageUrl}<img src={imageUrl} alt="" decoding="async" draggable="false" onerror={() => failed = imageUrl} />{/if}
</span>

<style>
  .avatar { position: relative; display: grid; flex: none; place-items: center; box-sizing: border-box; width: var(--size); height: var(--size); overflow: hidden; border-radius: 50%; color: #fff; background: var(--tint); }
  .avatar.ring { box-shadow: 0 0 0 1.5px var(--ring, rgb(0 0 0 / 35%)); }
  .initial { font-size: calc(var(--size) * .44); font-weight: 600; line-height: 1; }
  img { position: absolute; inset: 0; width: 100%; height: 100%; object-fit: cover; }
</style>
