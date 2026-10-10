<script lang="ts">
  import { t } from '$lib/i18n';
</script>
<span class="explicit-badge" role="img" aria-label={$t('home.explicit_content')} title={$t('home.explicit_content')}>
  <svg viewBox="0 0 10 12" aria-hidden="true" focusable="false"><path d="M1 1h8v2H3v2h5v2H3v2h6v2H1z" /></svg>
</span>

<style>
  .explicit-badge { display:inline-flex; flex:0 0 14px; align-items:center; justify-content:center; box-sizing:border-box; width:14px; height:14px; padding:0; border:1px solid #ffffff14; border-radius:3px; background:#000; color:#f2f2f2; vertical-align:middle; line-height:1; }
  svg { display:block; flex:none; width:8px; height:10px; fill:currentColor; }
</style>
