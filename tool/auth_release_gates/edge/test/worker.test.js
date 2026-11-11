import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import test from 'node:test';
import {decodePathForClassification, handleRequest, isReservedPath} from '../src/worker.js';

const denied = [
  '/__', '/__/', '/__/auth/handler', '/__/auth/iframe', '/__/firebase/init.js',
  '/%5f%5f/auth/handler', '/%5F_/firebase/init.json', '/_%5f/auth/iframe',
  '/%255f%255f/auth/handler', '/%25%35%66%25%35%66/firebase/init.js',
  '/%2f__/auth/handler', '//__/auth/handler', '///__//firebase/init.js',
  '/%5c__/firebase/init.js', '/\\__/firebase/init.js',
  '/wallet/../__/auth/handler', '/wallet/%2e%2e/__/auth/iframe',
  '/wallet/%252e%252e/%255f%255f/firebase/init.js',
  '/wallet%2f..%2f__%2ffirebase%2finit.js',
  '/__%2ffirebase/init.js', '/__%5cfirebase/init.js',
  '/__%3fignored', '/__%23ignored', '/__;x/auth/handler',
  '/__%3bx/auth/handler', '/__%00suffix', '/_%00_/auth/handler',
  '/__%20/auth/handler', '/%09__/auth/handler',
  '/wallet/..;ambiguous/__/auth/handler',
  '/%255f%255f/%252e%252e/ordinary', '/__/%2f%2e%2e/ordinary',
  '/%253f/%252e%252e/__/auth/handler', '/%2523/%252e%252e/__/auth/handler',
  '/safe%253fpart/%252e%252e/%255f%255f/auth/handler',
  '/safe%2523part/%252e%252e/%255f%255f/auth/handler',
  '/safe/%252e%252e/%255f%255f%253fignored/ordinary/%252e%252e/%252e%252e',
  '/%253f/%252e%252e/__%3f/ordinary/%252e%252e/%252e%252e',
  '/safe/%252e%252e/__/%25252e%25252e/ordinary',
];
const allowed = [
  '/', '/wallet', '/wallet/coins/BTC', '/.well-known/apple-app-site-association',
  '/apple-app-site-association', '/.well-known/assetlinks.json', '/main.dart.js',
  '/main.dart.js_1.part.js', '/flutter_bootstrap.js', '/flutter_service_worker.js',
  '/assets/packages/komodo_defi_framework/assets/web/event_streaming_worker.js',
  '/packages/komodo_defi_framework/web/kdf/bin/kdflib_bg.wasm', '/canvaskit/canvaskit.wasm',
  '/assets/translations/en.json', '/__wallet', '/___/ordinary', '/__.json',
  '/wallet/__/ordinary', '/%5f%5fwallet', '/wallet/%25invalid', '/wallet/%FF',
  '/wallet/../ordinary', '/wallet/%252e%252e/ordinary',
];

for (const path of denied) test(`denies reserved interpretation ${path}`, async () => {
  assert.equal(isReservedPath(path), true);
  let called = false;
  // URL's standard dot normalization can erase raw dot segments before Worker
  // entry. Classifier cases above separately exercise the unnormalized input.
  const request = new Request(`https://dex.gleec.com${path}`);
  const response = await handleRequest(request, async () => {
    called = true;
    return new Response('origin');
  });
  assert.equal(called, false);
  assert.equal(response.status, 404);
  assert.equal(await response.text(), 'Not found.\n');
  assert.equal(response.headers.get('Content-Type'), 'text/plain; charset=utf-8');
  assert.equal(response.headers.get('X-Content-Type-Options'), 'nosniff');
  assert.equal(response.headers.get('Cache-Control'), 'no-store');
  assert.equal(response.headers.get('Content-Security-Policy'),
    "default-src 'none'; base-uri 'none'; form-action 'none'; frame-ancestors 'none'");
  assert.equal(response.headers.has('Location'), false);
  assert.equal(response.headers.has('Set-Cookie'), false);
});

for (const path of allowed) test(`preserves ordinary path ${path}`, async () => {
  assert.equal(isReservedPath(path), false);
  const request = new Request(`https://dex.gleec.com${path}?next=/__/auth/handler&encoded=%255f`);
  const origin = new Response('origin', {
    status: 206,
    headers: {'Cache-Control': 'public, max-age=123', 'ETag': 'synthetic-etag',
      'Content-Range': 'bytes 1-6/10', 'Content-Type': 'application/wasm'},
  });
  const response = await handleRequest(request, async received => {
    assert.equal(received, request, 'Original Request identity must be preserved');
    assert.equal(received.bodyUsed, false);
    return origin;
  });
  assert.equal(response, origin, 'Original Response identity must be preserved');
  assert.equal(response.bodyUsed, false);
});

test('scope excludes every other hostname, including previews and lookalikes', async () => {
  for (const host of ['gleec.com', 'preview.gleec.com', 'dex.gleec.com.example',
    'dex-gleec.web.app', 'localhost', 'dex.gleec.com.']) {
    let calls = 0;
    const response = await handleRequest(new Request(`https://${host}/__/auth/handler`), async () => {
      calls++;
      return new Response('other host');
    });
    assert.equal(calls, 1);
    assert.equal(await response.text(), 'other host');
  }
});

test('uppercase canonical host is still protected', async () => {
  const response = await handleRequest(new Request('https://DEX.GLEEC.COM/__/firebase/init.js'),
    async () => assert.fail('Must not reach origin'));
  assert.equal(response.status, 404);
});

test('HEAD denial has no body and POST/OPTIONS/upgrade cannot bypass policy', async () => {
  for (const method of ['HEAD', 'POST', 'PUT', 'DELETE', 'OPTIONS', 'PATCH']) {
    const response = await handleRequest(new Request('https://dex.gleec.com/__/auth/handler', {method}),
      async () => assert.fail('Must not reach origin'));
    assert.equal(response.status, 404);
    assert.equal(await response.text(), method === 'HEAD' ? '' : 'Not found.\n');
  }
  const response = await handleRequest(new Request('https://dex.gleec.com/__/socket',
    {headers: {'Upgrade': 'websocket'}}), async () => assert.fail('No upgrade for reserved paths'));
  assert.equal(response.status, 404);
});

test('POST body, auth/header bytes and redirect response are not consumed or rewritten', async () => {
  const request = new Request('https://dex.gleec.com/ordinary?next=%2F__', {
    method: 'POST', body: new Uint8Array([0, 1, 255, 0, 65]),
    headers: {'Content-Type': 'application/octet-stream', Authorization: 'Synthetic-test-only',
      'Cache-Control': 'no-cache', 'If-Match': 'test-tag'}, redirect: 'manual',
  });
  const response = new Response(null, {status: 307, headers: {Location: '/unchanged',
    'Cache-Control': 'private, no-store', 'Set-Cookie': 'test=synthetic; Secure'}});
  const result = await handleRequest(request, async received => {
    assert.equal(received, request);
    assert.equal(received.redirect, 'manual');
    assert.deepEqual(new Uint8Array(await received.arrayBuffer()), new Uint8Array([0, 1, 255, 0, 65]));
    return response;
  });
  assert.equal(result, response);
});

test('arbitrarily nested and split percent encoding cannot evade the filter', () => {
  const nested = (byte, depth) => `%${'25'.repeat(depth)}${byte}`;
  assert.equal(decodePathForClassification('%25%32%66'), '/');
  assert.equal(isReservedPath(`/${nested('5f', 10000)}${nested('5f', 10000)}/auth/handler`), true);
  assert.equal(isReservedPath(`/wallet/${nested('61', 10000)}`), false,
    'Deep ordinary paths are not rejected just because they are encoded');
});

test('origin errors cannot trigger an unfiltered fallback', async () => {
  const failure = new Error('Synthetic origin error');
  await assert.rejects(handleRequest(new Request('https://dex.gleec.com/ordinary'),
    async () => { throw failure; }), error => error === failure);
});

test('configuration has one exact-host route and no public preview surfaces', () => {
  const config = JSON.parse(readFileSync(new URL('../wrangler.jsonc', import.meta.url)));
  assert.deepEqual(config.routes, [{pattern: 'dex.gleec.com/*', zone_name: 'gleec.com'}]);
  assert.equal(config.workers_dev, false);
  assert.equal(config.preview_urls, false);
  assert.equal(config.observability.logs.invocation_logs, false);
  assert.equal(config.observability.traces.enabled, false);
  assert.equal('vars' in config, false);
});
