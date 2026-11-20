const WALLET_HOST = 'dex.gleec.com';
const DENY_HEADERS = Object.freeze({
  'Content-Type': 'text/plain; charset=utf-8',
  'Cache-Control': 'no-store',
  'X-Content-Type-Options': 'nosniff',
  'Content-Security-Policy': "default-src 'none'; base-uri 'none'; form-action 'none'; frame-ancestors 'none'",
});

/** @param {string} character */
function hex(character) {
  const code = character.charCodeAt(0);
  if (code >= 48 && code <= 57) return code - 48;
  if (code >= 65 && code <= 70) return code - 55;
  if (code >= 97 && code <= 102) return code - 87;
  return -1;
}

/**
 * Classification only: repeatedly percent-decode bytes in linear time. Each
 * reduction consumes two characters, including escapes formed across adjacent
 * escapes. No recursion, decoding-depth limit or decodeURIComponent exception.
 * The original Request is never rebuilt from this conservative interpretation.
 * @param {string} path
 */
export function decodePathForClassification(path) {
  /** @type {string[]} */
  const stack = [];
  for (const character of path) {
    stack.push(character);
    while (stack.length >= 3 && stack[stack.length - 3] === '%') {
      const high = hex(stack[stack.length - 2]);
      const low = hex(stack[stack.length - 1]);
      if (high < 0 || low < 0) break;
      stack.length -= 3;
      stack.push(String.fromCharCode(high * 16 + low));
    }
  }
  return stack.join('');
}

/** @param {string} segment */
function reservedSegment(segment) {
  // Matrix parameters, control bytes and whitespace after the namespace are
  // ambiguous across HTTP stacks; they never get an origin fallback.
  return /^__(?:$|[;?#\u0000-\u0020\u007f])/.test(segment);
}

/** @param {string} path */
function normalizedPathIsReserved(path) {
  const segments = path.replaceAll('\\', '/').split('/');
  /** @type {string[]} */
  const resolved = [];
  for (const segment of segments) {
    // Consider matrix suffixes on traversal components as ambiguous too.
    const base = segment.split(';', 1)[0];
    if (base === '' || base === '.') continue;
    if (base === '..') resolved.pop();
    else resolved.push(segment);
    // Different escape depths may expose this root before a later traversal
    // becomes a dot segment. Once a decoded interpretation enters /__, deny
    // it even if a more aggressive normalization would subsequently leave it.
    if (reservedSegment(resolved[0] ?? '')) return true;
  }
  return reservedSegment(resolved[0] ?? '');
}

/** @param {string} path */
export function isReservedPath(path) {
  const decoded = decodePathForClassification(path);
  for (const candidate of [path, decoded, decoded.replace(/[\u0000-\u0020\u007f]/g, '')]) {
    // Check both before and after traversal normalization: a reserved-looking
    // request cannot escape by relying on different decoding orders downstream.
    // Decoded ?/# may remain literal pathname characters or become delimiters.
    // Evaluate both; truncating first would miss /%253f/../__/... variants.
    for (const interpretation of [candidate, candidate.split(/[?#]/, 1)[0]]) {
      const first = interpretation.replaceAll('\\', '/').split('/').find(Boolean) ?? '';
      if (reservedSegment(first) || normalizedPathIsReserved(interpretation)) return true;
    }
  }
  return false;
}

/**
 * @param {Request} request
 * @param {(request: Request) => Promise<Response>} forward
 * @returns {Promise<Response>}
 */
export async function handleRequest(request, forward = fetch) {
  const url = new URL(request.url);
  if (url.hostname === WALLET_HOST && isReservedPath(url.pathname)) {
    return new Response(request.method === 'HEAD' ? null : 'Not found.\n', {
      status: 404,
      headers: DENY_HEADERS,
    });
  }
  // Do not read/clone the request or response, follow redirects ourselves,
  // change headers/cache, or terminate upgrades. Origin streaming is retained.
  return forward(request);
}

/** @satisfies {ExportedHandler} */
export default {
  fetch(request) {
    return handleRequest(request);
  },
};
