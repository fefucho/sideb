<script lang="ts" module>
  export type SidebarIconName =
    | "home"
    | "search"
    | "liked"
    | "library"
    | "history"
    | "profile";
</script>

<script lang="ts">
  let { name }: { name: SidebarIconName } = $props();
</script>

<svg
  width="20"
  height="20"
  viewBox="0 0 24 24"
  fill="none"
  stroke="currentColor"
  stroke-width="1.8"
  stroke-linecap="round"
  stroke-linejoin="round"
  aria-hidden="true"
  focusable="false"
>
  {#if name === "home"}
    <path d="m3 10 9-7 9 7v10a1 1 0 0 1-1 1h-5v-7H9v7H4a1 1 0 0 1-1-1z" />
  {:else if name === "search"}
    <circle cx="10.8" cy="10.8" r="6.8" />
    <path d="m16 16 5 5" />
  {:else if name === "liked"}
    <path d="M20.7 8.5c0 4.2-6.5 9.3-8.7 11-2.2-1.7-8.7-6.8-8.7-11a4.9 4.9 0 0 1 8.7-3.1 4.9 4.9 0 0 1 8.7 3.1Z" />
  {:else if name === "library"}
    <path d="M4 4h5v17H4zM10 4h5v17h-5zM17 6l3-1 3 15-3 1z" />
  {:else if name === "history"}
    <path d="M3 11a9 9 0 1 1 2 6" />
    <path d="M3 5v6h6M12 7v5l3 2" />
  {:else if name === "profile"}
    <circle cx="12" cy="8" r="3.5" />
    <path d="M5 20a7 7 0 0 1 14 0" />
    <circle cx="12" cy="12" r="10" />
  {/if}
</svg>
