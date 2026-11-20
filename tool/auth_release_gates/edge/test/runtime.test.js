import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {fileURLToPath} from 'node:url';
import {after, before, test} from 'node:test';
import {Miniflare, convertV4MiniflareOptions} from 'miniflare';

// All origin traffic stays inside this local workerd fixture. No wallet,
// Cloudflare account, Firebase project or external application is contacted.
const origin = `export default {
  async fetch(request) {
    const url = new URL(request.url);
    if (url.pathname === '/events') {
      const pair = new WebSocketPair();
      pair[1].accept();
      pair[1].addEventListener('message', event => pair[1].send(event.data));
      return new Response(null, {status:101, webSocket:pair[0]});
    }
    if (url.pathname === '/open-stream') {
      let timer;
      return new Response(new ReadableStream({start(controller) {
        controller.enqueue(new TextEncoder().encode('first chunk'));
        timer = setTimeout(() => controller.close(), 250);
      },cancel() { clearTimeout(timer); }}),
      {headers:{'Content-Type':'text/event-stream','Cache-Control':'no-cache'}});
    }
    if (url.pathname === '/redirect') {
      return new Response(null, {status:307, headers:{Location:'/target?keep=1',
        'Cache-Control':'private, no-store','Set-Cookie':'fixture=synthetic; Secure'}});
    }
    if (url.pathname === '/not-modified') return new Response(null, {status:304,headers:{ETag:'test-etag'}});
    if (url.pathname.endsWith('.wasm')) {
      return new Response(new Uint8Array([0,97,115,109,1,0,0,0]), {status:206, headers:{
        'Content-Type':'application/wasm', 'Content-Range':'bytes 0-7/8',
        'Cache-Control':'public, max-age=31536000, immutable', ETag:'wasm-test-etag'}});
    }
    if (url.pathname === '/.well-known/apple-app-site-association') {
      return new Response('{"webcredentials":{"apps":["TEST.app"]}}', {
        headers:{'Content-Type':'application/json','Cache-Control':'public, max-age=3600'}});
    }
    return Response.json({url:request.url, method:request.method,
      headers:Object.fromEntries(request.headers), body:Array.from(new Uint8Array(await request.arrayBuffer()))},
      {status:201,headers:{'Cache-Control':'no-store','X-Origin-Fixture':'unchanged'}});
  }
};`;

let runtime;
before(async () => {
  const config = JSON.parse(readFileSync(new URL('../wrangler.jsonc', import.meta.url)));
  runtime = new Miniflare(convertV4MiniflareOptions({workers: [
    {name: 'reserved-filter', modules: true,
      scriptPath: fileURLToPath(new URL('../src/worker.js', import.meta.url)),
      compatibilityDate: config.compatibility_date, compatibilityFlags: config.compatibility_flags,
      outboundService: 'origin-fixture'},
    {name: 'origin-fixture', modules: true, script: origin,
      compatibilityDate: config.compatibility_date},
  ]}));
  await runtime.ready;
});
after(async () => { await runtime?.dispose(); });

test('workerd denies encoded reserved endpoints for every relevant method', async () => {
  for (const path of ['/__/auth/handler', '/%255f%255f/auth/iframe',
    '/%2f__/firebase/init.js', '/wallet/%252e%252e/%255f%255f/firebase/init.js',
    '/%253f/%252e%252e/__/auth/handler', '/%2523/%252e%252e/__/auth/handler',
    '/safe%253fpart/%252e%252e/%255f%255f/auth/handler',
    '/safe%2523part/%252e%252e/%255f%255f/auth/handler',
    '/safe/%252e%252e/%255f%255f%253fignored/ordinary/%252e%252e/%252e%252e',
    '/%253f/%252e%252e/__%3f/ordinary/%252e%252e/%252e%252e',
    '/safe/%252e%252e/__/%25252e%25252e/ordinary']) {
    for (const method of ['GET', 'HEAD', 'POST', 'OPTIONS']) {
      const response = await runtime.dispatchFetch(`https://dex.gleec.com${path}`, {method});
      assert.equal(response.status, 404);
      assert.equal(response.headers.get('Cache-Control'), 'no-store');
      assert.equal(response.headers.get('X-Content-Type-Options'), 'nosniff');
      assert.match(response.headers.get('Content-Security-Policy'), /default-src 'none'/);
      assert.equal(await response.text(), method === 'HEAD' ? '' : 'Not found.\n');
    }
  }
});

test('workerd preserves AASA body/type/cache and WASM bytes/range/cache', async () => {
  const aasa = await runtime.dispatchFetch('https://dex.gleec.com/.well-known/apple-app-site-association');
  assert.equal(aasa.status, 200);
  assert.equal(aasa.headers.get('Content-Type'), 'application/json');
  assert.equal(aasa.headers.get('Cache-Control'), 'public, max-age=3600');
  assert.equal(await aasa.text(), '{"webcredentials":{"apps":["TEST.app"]}}');
  const wasm = await runtime.dispatchFetch('https://dex.gleec.com/kdf/kdflib_bg.wasm',
    {headers: {Range: 'bytes=0-7'}});
  assert.equal(wasm.status, 206);
  assert.equal(wasm.headers.get('Content-Type'), 'application/wasm');
  assert.equal(wasm.headers.get('Content-Range'), 'bytes 0-7/8');
  assert.equal(wasm.headers.get('Cache-Control'), 'public, max-age=31536000, immutable');
  assert.equal(wasm.headers.get('ETag'), 'wasm-test-etag');
  assert.deepEqual(new Uint8Array(await wasm.arrayBuffer()), new Uint8Array([0, 97, 115, 109, 1, 0, 0, 0]));
});

test('workerd forwards original URL, method, binary body and headers', async () => {
  const url = 'https://dex.gleec.com/ordinary%2Fpath?next=%2F__%2Fauth&amount=1';
  const response = await runtime.dispatchFetch(url, {method: 'PATCH',
    headers: {'Content-Type': 'application/octet-stream', Authorization: 'Synthetic-only',
      'If-Match': 'unchanged-tag', 'Cache-Control': 'no-cache'},
    body: new Uint8Array([0, 255, 65]),
  });
  assert.equal(response.status, 201);
  const received = await response.json();
  assert.equal(received.url, url);
  assert.equal(received.method, 'PATCH');
  assert.deepEqual(received.body, [0, 255, 65]);
  assert.equal(received.headers.authorization, 'Synthetic-only');
  assert.equal(received.headers['if-match'], 'unchanged-tag');
  assert.equal(received.headers['cache-control'], 'no-cache');
});

test('workerd preserves origin redirect and 304 status without following', async () => {
  const redirect = await runtime.dispatchFetch('https://dex.gleec.com/redirect', {redirect: 'manual'});
  assert.equal(redirect.status, 307);
  assert.equal(redirect.headers.get('Location'), '/target?keep=1');
  assert.equal(redirect.headers.get('Set-Cookie'), 'fixture=synthetic; Secure');
  assert.equal(redirect.headers.get('Cache-Control'), 'private, no-store');
  const cached = await runtime.dispatchFetch('https://dex.gleec.com/not-modified');
  assert.equal(cached.status, 304);
  assert.equal(cached.headers.get('ETag'), 'test-etag');
});

test('workerd forwards the first chunk before an open stream ends', async () => {
  const response = await runtime.dispatchFetch('https://dex.gleec.com/open-stream');
  const reader = response.body.getReader();
  const chunk = await reader.read();
  assert.equal(new TextDecoder().decode(chunk.value), 'first chunk');
  assert.equal(chunk.done, false);
  await reader.cancel();
});

test('workerd preserves WebSocket upgrade and bidirectional frames', async () => {
  const response = await runtime.dispatchFetch('https://dex.gleec.com/events',
    {headers: {Upgrade: 'websocket'}});
  assert.equal(response.status, 101);
  const client = response.webSocket;
  assert.ok(client);
  client.accept();
  const echoed = new Promise(resolve => client.addEventListener('message', event => resolve(event.data), {once: true}));
  client.send('synthetic-frame');
  assert.equal(await echoed, 'synthetic-frame');
  client.close(1000);
});

test('workerd retains other-host behavior even for reserved paths', async () => {
  const response = await runtime.dispatchFetch('https://preview.gleec.com/__/auth/handler');
  assert.equal(response.status, 201);
});
