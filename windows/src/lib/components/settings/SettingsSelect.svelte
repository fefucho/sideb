<script lang="ts">
  interface Option { value: string; label: string }
  interface Props { value: string; options: Option[]; onChange: (value: string) => void; id?: string; label?: string; labelledby?: string; describedby?: string; disabled?: boolean }
  let { value, options, onChange, id, label, labelledby, describedby, disabled = false }: Props = $props();
</script>
<select {id} class="picker" {value} aria-label={label} aria-labelledby={label ? undefined : labelledby} aria-describedby={describedby} {disabled}
  onchange={event => onChange(event.currentTarget.value)}>
  {#each options as option (option.value)}<option value={option.value} selected={option.value === value}>{option.label}</option>{/each}
</select>
<style>
  .picker { appearance:none; box-sizing:border-box; max-width:100%; height:28px; padding:0 28px 0 10px; border:1px solid var(--control-border, rgb(255 255 255 / 11%)); border-radius:8px; color:var(--control-foreground, #f3f3f6); font:inherit; font-size:13px; cursor:pointer;
    background-color:var(--control-surface, #353538);
    background-image:url("data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 12 12'%3E%3Cpath d='M3 4.5 6 7.5 9 4.5' fill='none' stroke='%23c3c3cb' stroke-width='1.5' stroke-linecap='round' stroke-linejoin='round'/%3E%3C/svg%3E");
    background-repeat:no-repeat; background-position:right 8px center; background-size:12px; transition:background-color 140ms ease-out, border-color 140ms ease-out; }
  .picker:hover:not(:disabled) { border-color:var(--control-border-hover, rgb(255 255 255 / 19%)); background-color:var(--control-hover, #404043); }
  .picker:disabled { opacity:.45; cursor:default; }
  .picker:focus-visible { outline:2px solid var(--sideb-highlight, #d06c70); outline-offset:2px; }
  .picker option { background:var(--sideb-background, #1b1b1e); color:var(--control-foreground, #f3f3f6); }
</style>
