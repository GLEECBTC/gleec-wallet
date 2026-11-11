{{flutter_js}}
{{flutter_build_config}}

// Renderer scripts run in the wallet's origin. Never import executable code
// from a CDN into the origin that owns encrypted wallet data.
window.gleecWalletBrowserSupport.ready.then(() => {
  _flutter.loader.load({
    config: {
      canvasKitBaseUrl: new URL('canvaskit/', document.baseURI).href,
    },
  });
});
