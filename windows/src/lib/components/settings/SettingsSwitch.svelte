<script lang="ts">
  interface Props { checked: boolean; onChange: (checked: boolean) => void; id?: string; label?: string; labelledby?: string; describedby?: string; disabled?: boolean }
  let { checked, onChange, id, label, labelledby, describedby, disabled = false }: Props = $props();
</script>
<!-- Controlled switch: the parent owns the value, so a rejected change leaves the control as it was. -->
<button type="button" role="switch" {id} class="switch" aria-checked={checked} aria-label={label} aria-labelledby={label ? undefined : labelledby}
  aria-describedby={describedby} {disabled} onclick={() => onChange(!checked)}><span class="knob" aria-hidden="true"></span></button>
<style>
  .switch { position:relative; flex:none; box-sizing:border-box; width:36px; height:20px; padding:0; border:1px solid rgb(255 255 255 / 16%); border-radius:999px; background:rgb(255 255 255 / 14%); cursor:pointer; transition:background-color 140ms ease-out, border-color 140ms ease-out; }
  .switch[aria-checked='true'] { border-color:color-mix(in srgb, var(--sideb-highlight, #d06c70) 55%, transparent); background:var(--sideb-accent, #a33d45); }
  .switch:hover:not(:disabled) { border-color:rgb(255 255 255 / 30%); }
  .knob { position:absolute; top:1px; left:1px; width:16px; height:16px; border-radius:50%; background:#fff; box-shadow:0 1px 2px rgb(0 0 0 / 35%); transition:transform 140ms ease-out; }
  .switch[aria-checked='true'] .knob { transform:translateX(16px); }
  .switch:disabled { opacity:.4; cursor:default; }
  .switch:focus-visible { outline:2px solid var(--sideb-highlight, #d06c70); outline-offset:2px; }
  @media (prefers-reduced-motion:reduce) { .switch, .knob { transition:none; } }
</style>
