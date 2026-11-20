// Check the SDK's existing browser minimum before starting Flutter or KDF.
// This probe never reads, changes, clears or migrates wallet storage.
(function (root) {
  'use strict';

  function createBrowserSupport(environment, { timeoutMs = 3000 } = {}) {
    let allowStartup;
    const ready = new Promise(resolve => { allowStartup = resolve; });
    let checking = null;
    let supported = false;
    const onDocumentReady = action => {
      if (environment.document.readyState === 'loading') {
        environment.document.addEventListener('DOMContentLoaded', action, { once: true });
      } else action();
    };
    const showUnavailable = () => onDocumentReady(() => {
      if (supported) return;
      const document = environment.document;
      document.getElementById('loading')?.setAttribute('hidden', '');
      if (document.getElementById('browser-support')) return;
      const panel = document.createElement('main');
      panel.id = 'browser-support';
      panel.setAttribute('role', 'alert');
      panel.setAttribute('aria-live', 'polite');
      const card = document.createElement('section');
      const heading = document.createElement('h1');
      heading.textContent = 'This browser cannot safely open local wallets';
      const instructions = document.createElement('p');
      instructions.textContent = 'Use an updated browser with local site storage enabled and a secure HTTPS connection, then try again. This check has not changed your wallet data.';
      const recovery = document.createElement('p');
      recovery.textContent = 'If your wallet was created in another browser profile, reopen it there. To use a different browser or device, restore with your recovery phrase, or your encrypted wallet file and its password.';
      const retry = document.createElement('button');
      retry.type = 'button';
      retry.textContent = 'Try again';
      retry.addEventListener('click', async () => {
        retry.disabled = true;
        retry.textContent = 'Checking…';
        try { await check(); } finally { retry.disabled = false; retry.textContent = 'Try again'; }
      });
      card.append(heading, instructions, recovery, retry);
      panel.append(card);
      document.body.append(panel);
    });
    const check = () => {
      if (checking) return checking;
      checking = (async () => {
        let timer;
        try {
          if (!environment.isSecureContext || !environment.indexedDB ||
              !environment.crypto?.subtle ||
              typeof environment.navigator?.locks?.request !== 'function') return false;
          // Probe API availability, never the wallet catalog or a storage row.
          // A held probe lock is also evidence of a usable lock manager; this
          // non-queuing callback deliberately performs no protected operation.
          const usable = await Promise.race([
            environment.navigator.locks.request('gleec-browser-capability-probe',
              { mode: 'exclusive', ifAvailable: true }, () => true),
            new Promise(resolve => { timer = setTimeout(() => resolve(false), timeoutMs); }),
          ]);
          return usable === true;
        } catch (_) {
          // Platform details may contain profile/provider information.
          return false;
        } finally { clearTimeout(timer); }
      })().then(result => {
        supported = result;
        if (result) {
          environment.document.getElementById('browser-support')?.remove();
          environment.document.getElementById('loading')?.removeAttribute('hidden');
          allowStartup();
        } else showUnavailable();
        return result;
      }).finally(() => { checking = null; });
      return checking;
    };
    void check();
    return Object.freeze({ ready, check });
  }

  if (typeof module !== 'undefined' && module.exports) {
    module.exports = { createBrowserSupport };
  } else {
    root.gleecWalletBrowserSupport = createBrowserSupport(root);
  }
})(globalThis);
