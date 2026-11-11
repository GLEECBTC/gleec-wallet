// This page turns a base64 query parameter into an iframe `src`, which
// means whoever controls that parameter chooses what loads inside the
// wallet's own origin. Anything reaching `iframe.src` from here therefore
// has to be proven to belong to an approved payment provider first.
//
// The check lives in this file rather than only in the Dart caller because
// the deployed copy of this asset is fetched directly from production by
// desktop and mobile builds that are already in users' hands.

// KEEP IN SYNC with lib/bloc/fiat/fiat_checkout_url_allowlist.dart.
// test_units/tests/fiat/fiat_checkout_url_allowlist_test.dart fails if
// these lists and the Dart ones drift apart.
var KOMODO_ALLOWED_CHECKOUT_HOSTS = [
  'komodo.banxa.com',
  'komodo.banxa-sandbox.com',
  'app.ramp.network',
  'app.demo.ramp.network'
];
var KOMODO_ALLOWED_CHECKOUT_DOMAINS = [
  'banxa.com',
  'banxa-sandbox.com',
  'ramp.network'
];

window.addEventListener('message', _komodoOnMessageHandler, false);
window.addEventListener('load', function () {
  _komodoSetIframeUrlFromParams();
});

/**
 * Initialize the iframe URL based on URL parameters
 */
function _komodoSetIframeUrlFromParams() {
  const urlParam = _komodoGetUrlParameter('fiatUrl');
  if (!urlParam) {
    console.error('No URL parameter provided');
    _komodoShowBlockedMessage();
    return;
  }

  let targetUrl = null;
  try {
    targetUrl = _komodoDecodeUrlParameter(urlParam);
  } catch (error) {
    console.error('Error decoding base64 url parameter', error);
  }

  const approvedUrl = targetUrl ? _komodoApprovedCheckoutUrl(targetUrl) : null;
  if (!approvedUrl) {
    console.error('Blocked a checkout URL that is not an approved fiat provider');
    _komodoShowBlockedMessage();
    return;
  }

  // Assign the re-serialized URL rather than the decoded string, so the
  // value that was validated is exactly the value that gets loaded.
  document.getElementById('fiat-onramp-iframe').src = approvedUrl;
}

/**
 * Validate a decoded checkout URL.
 *
 * @param {string} rawUrl - The decoded `fiatUrl` parameter
 * @returns {string|null} - The normalized URL to load, or null when the URL
 *   does not belong to an approved fiat provider
 */
function _komodoApprovedCheckoutUrl(rawUrl) {
  // Backslashes, raw whitespace and control characters are treated
  // differently by different URL parsers, which is how a URL that reads as
  // the provider's but resolves somewhere else is built. Nothing
  // legitimate needs them.
  if (/[\\\s\u0000-\u001f\u007f]/.test(rawUrl)) {
    return null;
  }

  let parsed;
  try {
    // Deliberately no base argument: a relative URL has to fail here
    // rather than resolve against this page's own (wallet) origin.
    parsed = new URL(rawUrl);
  } catch (error) {
    return null;
  }

  // Blocks javascript:, data:, blob:, file: and plain http:.
  if (parsed.protocol !== 'https:') {
    return null;
  }

  // `https://komodo.banxa.com@attacker.example/` authenticates to
  // `attacker.example` while reading as the provider.
  if (parsed.username || parsed.password) {
    return null;
  }

  return _komodoIsAllowedCheckoutHost(parsed.hostname) ? parsed.href : null;
}

/**
 * Check a host against the approved fiat provider lists
 *
 * @param {string} hostname
 * @returns {boolean}
 */
function _komodoIsAllowedCheckoutHost(hostname) {
  let host = String(hostname).toLowerCase();
  // A trailing dot is the fully-qualified form of the same host.
  while (host.charAt(host.length - 1) === '.') {
    host = host.slice(0, -1);
  }
  if (!host) {
    return false;
  }

  if (KOMODO_ALLOWED_CHECKOUT_HOSTS.indexOf(host) !== -1) {
    return true;
  }

  for (let i = 0; i < KOMODO_ALLOWED_CHECKOUT_DOMAINS.length; i++) {
    const domain = KOMODO_ALLOWED_CHECKOUT_DOMAINS[i];
    // The leading dot matters: without it `notbanxa.com` would match
    // `banxa.com`.
    if (host === domain || host.slice(-(domain.length + 1)) === '.' + domain) {
      return true;
    }
  }

  return false;
}

/**
 * Decode the `fiatUrl` parameter.
 *
 * Current builds percent-encode standard base64. Older clients leave `+`
 * unescaped, so URLSearchParams turns it into a space. Accept that legacy
 * form and base64url as well.
 *
 * @param {string} value - The raw `fiatUrl` parameter value
 * @returns {string} - The decoded URL
 */
function _komodoDecodeUrlParameter(value) {
  let normalized = value.replace(/ /g, '+').replace(/-/g, '+').replace(/_/g, '/');
  while (normalized.length % 4 !== 0) {
    normalized += '=';
  }

  const binary = atob(normalized);
  if (typeof TextDecoder === 'undefined' || typeof Uint8Array === 'undefined') {
    return binary;
  }

  // The Dart side base64-encodes UTF-8 bytes, so decode them as UTF-8
  // rather than leaving `atob`'s raw byte string.
  const bytes = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i++) {
    bytes[i] = binary.charCodeAt(i);
  }
  return new TextDecoder('utf-8').decode(bytes);
}

/**
 * Replace the iframe with a visible explanation when a URL is rejected, so
 * a blocked link does not just render as a blank page.
 */
function _komodoShowBlockedMessage() {
  const iframe = document.getElementById('fiat-onramp-iframe');
  if (iframe) {
    iframe.removeAttribute('src');
    iframe.style.display = 'none';
  }

  const blocked = document.getElementById('fiat-onramp-blocked');
  if (blocked) {
    blocked.style.display = 'block';
  }
}

/**
 * Get URL parameter by name
 *
 * @param {string} name - The name of the URL parameter to retrieve
 * @returns {string|null} - The value of the URL parameter or null if not found
 */
function _komodoGetUrlParameter(name) {
  const params = new URLSearchParams(window.location.search);
  return params.get(name);
}

/**
 * Handle messages from the iframe
 *
 * @param {MessageEvent} messageEvent
 */
function _komodoOnMessageHandler(messageEvent) {
  // Only the payment provider is allowed to report payment status. Without
  // this, any window with a handle to this one could post a forged
  // "payment succeeded" event straight through to the wallet.
  if (!_komodoIsAllowedMessageOrigin(messageEvent.origin)) {
    return;
  }

  let messageData;
  try {
    messageData = typeof messageEvent.data === 'string' ? JSON.parse(messageEvent.data) : messageEvent.data;
  } catch (parseError) {
    messageData = messageEvent.data;
  }

  try {
    _komodoPostMessageToParent(messageData);
  } catch (postError) {
    console.error('Error posting message', postError);
  }
}

/**
 * Check whether a `MessageEvent` origin belongs to an approved provider.
 * Providers nest iframes of their own, so this matches the same provider
 * domains as the checkout URL rather than one exact origin.
 *
 * @param {string} origin
 * @returns {boolean}
 */
function _komodoIsAllowedMessageOrigin(origin) {
  // An opaque origin arrives as the string "null" and fails to parse.
  try {
    const parsed = new URL(origin);
    // The scheme matters as much as the host: the framed provider can
    // navigate itself after the first load, and an `http:` page on a
    // provider host is not the provider.
    return parsed.protocol === 'https:'
      && _komodoIsAllowedCheckoutHost(parsed.hostname);
  } catch (error) {
    return false;
  }
}

/**
 * Post a message to the parent window
 *
 * @param {string|object} messageData
 */
function _komodoPostMessageToParent(messageData) {
  const messageString = (typeof messageData === 'object') ? JSON.stringify(messageData) : String(messageData);

  // flutter_inappwebview
  console.log(messageString);

  // The opener and the parent are always the wallet app, which serves this
  // page, so pin the target origin instead of broadcasting with "*".
  const walletOrigin = window.location.origin;

  // universal_url opener
  if (window.opener) {
    return window.opener.postMessage(messageString, walletOrigin);
  }

  if (window.parent && window.parent !== window) {
    return window.parent.postMessage(messageString, walletOrigin);
  }

  // Windows WebView2 (desktop_webview_window)
  // https://learn.microsoft.com/en-us/microsoft-edge/webview2/how-to/communicate-btwn-web-native
  if (window.chrome && window.chrome.webview) {
    return window.chrome.webview.postMessage(messageString);
  }

  console.error('No valid postMessage target found');
}
