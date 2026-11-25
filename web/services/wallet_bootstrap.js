// Self-hosted startup behavior: the wallet origin does not permit inline code.
(() => {
  'use strict';
  const requested = new URLSearchParams(window.location.search).get('brightness');
  const theme = requested === 'light' || requested === 'dark' ? requested
    : window.matchMedia('(prefers-color-scheme: dark)').matches ? 'dark' : 'light';
  document.body.classList.add(theme);

  window.addEventListener('DOMContentLoaded', async () => {
    await window.gleecWalletBrowserSupport.ready;
    const initialize = window.kdf?.init_wasm ?? window.init_wasm;
    if (!initialize || window.is_mm2_preload_busy) return;
    window.is_mm2_preload_busy = true;
    Promise.resolve(initialize()).then(() => {
      window.is_mm2_preloaded = true;
    }).catch(() => {
      // The app's normal startup path reports/retries initialization failures.
      // Never expose engine diagnostics in a browser console here.
    }).finally(() => {
      window.is_mm2_preload_busy = false;
    });
  });
})();
