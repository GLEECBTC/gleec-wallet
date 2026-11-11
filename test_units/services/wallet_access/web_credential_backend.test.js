'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const { readFileSync } = require('node:fs');
const path = require('node:path');
const { createHash } = require('node:crypto');
const { webcrypto: crypto } = require('node:crypto');
const { createWalletCredentials } = require('../../../web/services/wallet_credentials.js');
const { LocalBrowser } = require('./web_release_test_driver.js');
const text = new TextEncoder();
const secret = 'Unfunded-test-credential-42@';
const changedSecret = 'Rotated-unfunded-credential-84@';

test('hosted acceptance rejects production and verifies the independently approved PR bundle', async () => {
  const oldUrl = process.env.GLEEC_TEST_HOSTED_URL;
  const oldHash = process.env.GLEEC_TEST_EXPECTED_BUILD_SHA256;
  const oldFetch = global.fetch;
  const fixture = new LocalBrowser(path.resolve(__dirname, '../../..'));
  const bundle = Buffer.from('disposable-public-compiled-fixture');
  let requests = 0;
  global.fetch = async () => { requests++; return new Response(bundle); };
  process.env.GLEEC_TEST_EXPECTED_BUILD_SHA256 = createHash('sha256').update(bundle).digest('hex');
  try {
    for (const host of [
      'walletrc--pull-3612-merge-m7wcb5ap.web.app',
      'gleec-wallet-official--pull-3612-merge-2c51371-m7wcb5ap.web.app',
    ]) {
      process.env.GLEEC_TEST_HOSTED_URL = `https://${host}/`;
      await fixture.serve();
    }
    assert.equal(requests, 2);
    for (const url of [
      'https://dex.gleec.com/', 'https://walletrc.web.app/',
      'https://unrelated--pull-3612-merge-m7wcb5ap.web.app/',
      'https://walletrc--pull-3612-merge-m7wcb5ap.web.app.evil.example/',
      'http://walletrc--pull-3612-merge-m7wcb5ap.web.app/',
      'https://walletrc--pull-3612-merge-m7wcb5ap.web.app/wallet',
      'https://walletrc--pull-3612-merge-m7wcb5ap.web.app/?override=1',
      'https://user@walletrc--pull-3612-merge-m7wcb5ap.web.app/',
      'https://walletrc--pull-3612-merge-m7wcb5ap.web.app:8443/',
    ]) {
      process.env.GLEEC_TEST_HOSTED_URL = url;
      await assert.rejects(fixture.serve());
    }
    assert.equal(requests, 2, 'Reject unsafe targets before requesting any bytes');
    process.env.GLEEC_TEST_HOSTED_URL = 'https://walletrc--pull-3612-merge-m7wcb5ap.web.app/';
    delete process.env.GLEEC_TEST_EXPECTED_BUILD_SHA256;
    await assert.rejects(fixture.serve());
    assert.equal(requests, 2);
    process.env.GLEEC_TEST_EXPECTED_BUILD_SHA256 = '0'.repeat(64);
    await assert.rejects(fixture.serve(), /approved build/);
  } finally {
    global.fetch = oldFetch;
    if (oldUrl === undefined) delete process.env.GLEEC_TEST_HOSTED_URL;
    else process.env.GLEEC_TEST_HOSTED_URL = oldUrl;
    if (oldHash === undefined) delete process.env.GLEEC_TEST_EXPECTED_BUILD_SHA256;
    else process.env.GLEEC_TEST_EXPECTED_BUILD_SHA256 = oldHash;
    await fixture.cleanup();
  }
});

test('wallet HTML and hosting policy exclude external and arbitrary inline scripts', () => {
  const root = path.resolve(__dirname, '../../..');
  const html = readFileSync(path.join(root, 'web/index.html'), 'utf8');
  const hosting = JSON.parse(readFileSync(path.join(root, 'firebase.json'), 'utf8')).hosting;
  const policies = [
    html.match(/http-equiv="Content-Security-Policy"\s+content="([^"]+)"/)[1],
    hosting.headers.flatMap(rule => rule.headers).find(header => header.key === 'Content-Security-Policy').value,
  ];
  for (const policy of policies) {
    const script = policy.split(';').map(value => value.trim()).find(value => value.startsWith('script-src '));
    assert.ok(script.includes("'self'"));
    assert.ok(script.includes("'wasm-unsafe-eval'"));
    for (const source of script.split(/\s+/).slice(1)) {
      assert.ok(["'self'", "'wasm-unsafe-eval'"].includes(source) || /^'sha256-[\w+/]+=*'$/.test(source));
    }
    for (const match of html.matchAll(/<script\b([^>]*)>([\s\S]*?)<\/script>/g)) {
      const src = match[1].match(/\bsrc="([^"]+)"/);
      if (src) {
        assert.equal(new URL(src[1], 'https://dex.gleec.com').origin, 'https://dex.gleec.com');
      } else {
        const hash = createHash('sha256').update(match[2]).digest('base64');
        assert.ok(script.includes(`'sha256-${hash}'`), 'Inline data/scripts need an exact CSP hash');
      }
    }
  }
  assert.ok(!hosting.ignore.includes('**/.*'), 'Apple association must be deployed');
  assert.equal(hosting.appAssociation, 'NONE', 'Firebase must serve the bundled association, not replace it with generated applinks');
  assert.ok(hosting.headers.find(rule => rule.source === '/')?.headers.some(header =>
    header.key === 'Cache-Control' && header.value.includes('no-cache')),
  'The root HTML entry must revalidate when the credential bridge is introduced');
  assert.ok(hosting.headers.find(rule => rule.source === '/services/@(wallet_credentials.js|wallet_bootstrap.js|wallet_browser_support.js)')?.headers.some(header =>
    header.key === 'Cache-Control' && header.value.includes('no-cache')),
  'Wallet service bridges must revalidate with their compiled application caller');
  const association = JSON.parse(readFileSync(path.join(root, 'web/.well-known/apple-app-site-association'), 'utf8'));
  assert.deepEqual(association.webcredentials.apps, ['B52ZCS7TMQ.com.GleecDEX.wallet']);
});

test('hosting revalidates deep links and helper HTML while retaining the coin-icon cache', () => {
  const root = path.resolve(__dirname, '../../..');
  const hosting = JSON.parse(readFileSync(path.join(root, 'firebase.json'), 'utf8')).hosting;
  const defaults = hosting.headers.find(rule => rule.source === '**');
  const cache = rule => rule.headers.find(header => header.key === 'Cache-Control')?.value;
  assert.equal(cache(defaults), 'no-cache, max-age=0, must-revalidate',
    'Every SPA rewrite and packaged HTML response must inherit revalidation');
  const icons = hosting.headers.find(rule =>
    rule.source === '/assets/packages/komodo_defi_framework/assets/coin_icons/**');
  assert.equal(cache(icons), 'public, max-age=2592000');
  assert.ok(hosting.headers.indexOf(icons) > hosting.headers.indexOf(defaults),
    'The explicit icon cache must override the default');
  for (const rule of hosting.headers) {
    if (rule === icons || !cache(rule)) continue;
    assert.match(cache(rule), /(?:^|,\s*)max-age=0(?:,|$)/,
      `A non-icon cache override must not retain an obsolete shell: ${rule.source}`);
    assert.ok(cache(rule).includes('must-revalidate'));
  }
});

function join(...parts) {
  const output = new Uint8Array(parts.reduce((sum, part) => sum + part.length, 0));
  let offset = 0;
  for (const part of parts) { output.set(part, offset); offset += part.length; }
  return output;
}
const random = (length) => crypto.getRandomValues(new Uint8Array(length));
const b64 = (bytes) => Buffer.from(bytes).toString('base64url');

class MemoryStore {
  records = new Map();
  stages = new Map();
  failStage = false;
  corruptStage = false;
  failPromote = false;
  async get(key) { return structuredClone(this.records.get(key) ?? null); }
  async getStaged(slot) {
    const row = structuredClone(this.stages.get(slot));
    if (this.corruptStage) row.iv = random(12);
    return row;
  }
  async stage(record, id) {
    if (this.failStage) throw new Error('Canary storage failure details');
    const slot = `staged:${id}`;
    this.stages.set(slot, structuredClone(record));
    return slot;
  }
  async discardStage(slot) { this.stages.delete(slot); }
  async promote(key, expected, slot, revision) {
    if (this.failPromote) throw new Error('Canary promotion failure details');
    const row = this.stages.get(slot);
    if ((this.records.get(key)?.revision ?? null) !== expected || !row || row.revision !== revision) {
      const error = new Error('staleOperation'); error.code = 'staleOperation'; throw error;
    }
    for (const [stage, record] of this.stages) if (record.key === key) this.stages.delete(stage);
    this.records.set(key, structuredClone(row));
  }
  async remove(key, expected) {
    assert.equal(this.records.get(key)?.revision ?? null, expected);
    this.records.delete(key);
    for (const [stage, record] of this.stages) if (record.key === key) this.stages.delete(stage);
  }
}

function derSignature(raw) {
  const integer = (bytes) => {
    let offset = 0;
    while (offset < bytes.length - 1 && bytes[offset] === 0) offset++;
    let result = bytes.slice(offset);
    if (result[0] & 128) result = join(new Uint8Array([0]), result);
    return join(new Uint8Array([2, result.length]), result);
  };
  const content = join(integer(raw.slice(0, 32)), integer(raw.slice(32)));
  return join(new Uint8Array([0x30, content.length]), content);
}

async function environment(options = {}) {
  const page = new EventTarget();
  page.visibilityState = 'visible';
  page.hasFocus = () => true;
  const window = new EventTarget();
  const state = { creates: 0, gets: 0, createPrf: true, getPrf: true, mutateGet: null,
    mutateCreate: null, rejectGet: false, failSignature: false, pendingGet: null,
    invalidPrfLength: false, createResult: false, mismatchCreationPrf: false };
  const registered = new Map();
  const algorithm = options.algorithm ?? -7;
  const generateAlgorithm = algorithm === -7
    ? { name: 'ECDSA', namedCurve: 'P-256' }
    : { name: 'RSASSA-PKCS1-v1_5', modulusLength: 2048,
      publicExponent: new Uint8Array([1, 0, 1]), hash: 'SHA-256' };
  const keys = await crypto.subtle.generateKey(generateAlgorithm, true, ['sign', 'verify']);
  const spki = await crypto.subtle.exportKey('spki', keys.publicKey);
  const origin = options.origin ?? 'https://dex.gleec.com';
  const url = new URL(origin);
  const authData = async (rpId, credentialId) => {
    const hash = new Uint8Array(await crypto.subtle.digest('SHA-256', text.encode(rpId)));
    const header = join(hash, new Uint8Array([credentialId ? 0x45 : 0x05, 0, 0, 0, 0]));
    return credentialId ? join(header, new Uint8Array(16),
      new Uint8Array([credentialId.length >> 8, credentialId.length & 255]), credentialId,
      new Uint8Array([0xa0])) : header;
  };
  const clientData = (type, challenge) => text.encode(JSON.stringify({
    type, challenge: b64(challenge), origin, crossOrigin: false,
  }));
  const credentials = {
    async create({ publicKey, signal }) {
      assert.equal(publicKey.rp.id, url.hostname);
      assert.equal(publicKey.authenticatorSelection.userVerification, 'required');
      assert.equal(publicKey.authenticatorSelection.residentKey, 'required');
      assert.equal(publicKey.attestation, 'none');
      assert.equal(publicKey.user.id.length, 32);
      assert.equal(signal.aborted, false);
      state.creates++;
      const id = random(32), prfSecret = random(32);
      registered.set(b64(id), { id, prfSecret });
      const response = { clientDataJSON: clientData('webauthn.create', publicKey.challenge),
        getAuthenticatorData: () => authenticator,
        getPublicKey: () => spki, getPublicKeyAlgorithm: () => algorithm };
      const authenticator = await authData(publicKey.rp.id, id);
      const credential = { type: 'public-key', rawId: id, response,
        getClientExtensionResults: () => ({ prf: { enabled: state.createPrf,
          ...(state.createResult ? { results: { first: creationPrf } } : {}) } }) };
      const creationPrf = state.mismatchCreationPrf ? random(32)
        : new Uint8Array(await crypto.subtle.digest('SHA-256',
          join(prfSecret, new Uint8Array(publicKey.extensions.prf.eval.first))));
      state.mutateCreate?.(credential);
      return credential;
    },
    async get({ publicKey, signal }) {
      state.gets++;
      if (state.rejectGet) throw new DOMException('Canary private provider details', 'NotAllowedError');
      if (state.pendingGet) {
        await new Promise((resolve, reject) => {
          state.pendingGet.resolve = resolve;
          signal.addEventListener('abort', () => reject(new DOMException('', 'AbortError')));
        });
      }
      assert.equal(publicKey.userVerification, 'required');
      const id = publicKey.allowCredentials[0].id;
      const registration = registered.get(b64(id));
      if (!registration) throw new DOMException('', 'NotAllowedError');
      const authenticator = await authData(publicKey.rpId);
      const client = clientData('webauthn.get', publicKey.challenge);
      const signed = join(authenticator, new Uint8Array(await crypto.subtle.digest('SHA-256', client)));
      let signature = new Uint8Array(await crypto.subtle.sign(algorithm === -7
        ? { name: 'ECDSA', hash: 'SHA-256' } : { name: 'RSASSA-PKCS1-v1_5' }, keys.privateKey, signed));
      if (algorithm === -7) signature = derSignature(signature);
      if (state.failSignature) signature[signature.length - 1] ^= 1;
      const prf = new Uint8Array(await crypto.subtle.digest('SHA-256',
        join(registration.prfSecret, new Uint8Array(publicKey.extensions.prf.eval.first))));
      const credential = { type: 'public-key', rawId: id,
        response: { clientDataJSON: client, authenticatorData: authenticator, signature },
        getClientExtensionResults: () => state.getPrf
          ? { prf: { results: { first: state.invalidPrfLength ? prf.slice(0, 31) : prf } } } : {},
      };
      state.mutateGet?.(credential);
      return credential;
    },
  };
  const navigator = { credentials, locks: { async request(_, __, callback) { return callback({}); } } };
  const env = { crypto, navigator, document: page, location: url, isSecureContext: true,
    performance: { now: () => options.now?.() ?? performance.now() },
    BroadcastChannel: options.channelClass,
    PublicKeyCredential: class {}, addEventListener: window.addEventListener.bind(window),
    dispatchEvent: window.dispatchEvent.bind(window), CustomEvent,
  };
  env.top = env.self = env;
  const store = options.store ?? new MemoryStore();
  const api = createWalletCredentials(env, { store });
  return { env, api, state, store };
}

test('unattended browser credentials are encrypted, durable and honestly classified', async () => {
  const { api, store } = await environment();
  await api.write({ key: 'wallet-1', value: secret });
  assert.equal(await api.read({ key: 'wallet-1' }), secret);
  assert.deepEqual(await api.metadata({ key: 'wallet-1' }),
    { protection: 'browserLocal', revision: 1, enrolled: false });
  const record = store.records.get('wallet-1');
  assert.equal(record.unattendedKey.extractable, false);
  assert.equal(JSON.stringify(record).includes(secret), false);
  await assert.rejects(api.read({ key: 'wallet-1', requireAuthentication: true }), { code: 'unavailable' });
});

for (const algorithm of [-7, -257]) {
  test(`passkey enrollment verifies real ${algorithm === -7 ? 'ES256' : 'RS256'} signatures and removes unattended access`, async () => {
    const { api, store, state } = await environment({ algorithm });
    await api.write({ key: 'wallet-1', value: secret });
    const abandoned = structuredClone(store.records.get('wallet-1'));
    store.stages.set('staged:abandoned', abandoned);
    await api.enrollPasskey({ key: 'wallet-1', value: secret, label: 'Test wallet' });
    assert.equal(state.creates, 1);
    assert.equal(state.gets, 1);
    assert.deepEqual(await api.metadata({ key: 'wallet-1' }),
      { protection: 'passkeyPrf', revision: 2, enrolled: true });
    assert.equal(store.records.get('wallet-1').unattendedKey, undefined);
    assert.equal(store.stages.size, 0);
    assert.equal(await api.read({ key: 'wallet-1' }), secret);
    assert.equal(state.gets, 2, 'false requireAuthentication must still require stored passkey');
    state.rejectGet = true;
    await assert.rejects(api.read({ key: 'wallet-1' }), { code: 'notCompleted' });
  });
}

test('registration with enabled PRF but no creation output succeeds only through a fresh assertion', async () => {
  const { api, state } = await environment();
  await api.enrollPasskey({ key: 'wallet-1', value: secret });
  assert.equal(state.gets, 1);
  assert.equal(await api.read({ key: 'wallet-1' }), secret);
});

test('registration success without PRF never removes prior access', async () => {
  const { api, state } = await environment();
  await api.write({ key: 'wallet-1', value: secret });
  state.createPrf = false;
  await assert.rejects(api.enrollPasskey({ key: 'wallet-1', value: secret }), { code: 'prfUnavailable' });
  assert.equal(state.gets, 0);
  assert.equal((await api.metadata({ key: 'wallet-1' })).enrolled, false);
  assert.equal(await api.read({ key: 'wallet-1' }), secret);
});

test('creation output cannot substitute for missing assertion PRF', async () => {
  const { api, state } = await environment();
  await api.write({ key: 'wallet-1', value: secret });
  state.createResult = true; state.getPrf = false;
  await assert.rejects(api.enrollPasskey({ key: 'wallet-1', value: secret }), { code: 'prfUnavailable' });
  assert.equal(await api.read({ key: 'wallet-1' }), secret);
});

test('creation and assertion PRF outputs must agree when both are returned', async () => {
  const { api, state } = await environment();
  await api.write({ key: 'wallet-1', value: secret });
  state.createResult = true; state.mismatchCreationPrf = true;
  await assert.rejects(api.enrollPasskey({ key: 'wallet-1', value: secret }), { code: 'prfUnavailable' });
  assert.equal(await api.read({ key: 'wallet-1' }), secret);
});

test('matching creation and assertion outputs enable durable protection', async () => {
  const { api, state } = await environment();
  state.createResult = true;
  await api.enrollPasskey({ key: 'wallet-1', value: secret });
  assert.equal(await api.read({ key: 'wallet-1' }), secret);
});

test('short PRF output cannot enable protection', async () => {
  const { api, state } = await environment();
  state.invalidPrfLength = true;
  await assert.rejects(api.enrollPasskey({ key: 'wallet-1', value: secret }), { code: 'prfUnavailable' });
  assert.equal(await api.metadata({ key: 'wallet-1' }), null);
});

test('corrupted staged ciphertext leaves the previous durable credential untouched', async () => {
  const { api, store } = await environment();
  await api.write({ key: 'wallet-1', value: secret });
  store.corruptStage = true;
  await assert.rejects(api.enrollPasskey({ key: 'wallet-1', value: secret }), { code: 'envelopeCorrupt' });
  assert.equal(await api.read({ key: 'wallet-1' }), secret);
  assert.equal((await api.metadata({ key: 'wallet-1' })).protection, 'browserLocal');
});

for (const point of ['failStage', 'failPromote']) {
  test(`${point} does not destroy the prior unlock path or leak errors`, async () => {
    const { api, store } = await environment();
    await api.write({ key: 'wallet-1', value: secret });
    store[point] = true;
    await assert.rejects(api.enrollPasskey({ key: 'wallet-1', value: secret }), (error) => {
      assert.equal(error.code, 'storageFailed');
      assert.equal(error.message.includes('Canary'), false);
      return true;
    });
    assert.equal(await api.read({ key: 'wallet-1' }), secret);
  });
}

test('protected records cannot be silently downgraded by write(false)', async () => {
  const { api } = await environment();
  await api.enrollPasskey({ key: 'wallet-1', value: secret });
  await assert.rejects(api.write({ key: 'wallet-1', value: changedSecret }), { code: 'invalidated' });
  assert.equal(await api.read({ key: 'wallet-1' }), secret);
});

test('protected rotation requires another assertion and survives a new bridge instance', async () => {
  const { api, store, env } = await environment();
  await api.enrollPasskey({ key: 'wallet-1', value: secret });
  await api.write({ key: 'wallet-1', value: changedSecret, requireAuthentication: true });
  const restarted = createWalletCredentials(env, { store });
  assert.equal(await restarted.read({ key: 'wallet-1' }), changedSecret);
  assert.equal((await restarted.metadata({ key: 'wallet-1' })).revision, 2);
});

const malformed = {
  userHandle: (credential) => { credential.response.userHandle = random(32); },
  credential: (credential) => { credential.rawId = random(32); },
  origin: (credential) => {
    const data = JSON.parse(new TextDecoder().decode(credential.response.clientDataJSON));
    data.origin = 'https://other.gleec.com';
    credential.response.clientDataJSON = text.encode(JSON.stringify(data));
  },
  challenge: (credential) => {
    const data = JSON.parse(new TextDecoder().decode(credential.response.clientDataJSON));
    data.challenge = b64(random(32));
    credential.response.clientDataJSON = text.encode(JSON.stringify(data));
  },
  rpHash: (credential) => { credential.response.authenticatorData[0] ^= 1; },
  userVerification: (credential) => { credential.response.authenticatorData[32] &= ~4; },
  userPresence: (credential) => { credential.response.authenticatorData[32] &= ~1; },
  signatureEncoding: (credential) => { credential.response.signature = new Uint8Array(64); },
};
for (const [name, mutation] of Object.entries(malformed)) {
  test(`rejects malformed assertion: ${name}`, async () => {
    const { api, state } = await environment();
    await api.enrollPasskey({ key: 'wallet-1', value: secret });
    state.mutateGet = mutation;
    await assert.rejects(api.read({ key: 'wallet-1' }), { code: 'invalidResponse' });
  });
}

test('rejects a cryptographically invalid signature', async () => {
  const { api, state } = await environment();
  await api.enrollPasskey({ key: 'wallet-1', value: secret });
  state.failSignature = true;
  await assert.rejects(api.read({ key: 'wallet-1' }), { code: 'invalidResponse' });
});

test('authenticated envelope binds wallet identity, credential and origin', async () => {
  const { api, store } = await environment();
  await api.enrollPasskey({ key: 'wallet-1', value: secret });
  const copied = structuredClone(store.records.get('wallet-1'));
  copied.key = 'wallet-2'; store.records.set('wallet-2', copied);
  await assert.rejects(api.read({ key: 'wallet-2' }), { code: 'envelopeCorrupt' });
});

test('enrollment cancel releases busy state and preserves previous access', async () => {
  const { api, state } = await environment();
  await api.write({ key: 'wallet-1', value: secret });
  state.pendingGet = {};
  const pending = api.enrollPasskey({ key: 'wallet-1', value: secret });
  while (!state.pendingGet.resolve) await new Promise(setImmediate);
  await assert.rejects(api.read({ key: 'wallet-1' }), { code: 'busy' });
  api.cancel();
  await assert.rejects(pending, { code: 'aborted' });
  assert.equal(await api.read({ key: 'wallet-1' }), secret);
});

test('backgrounding aborts a pending ceremony without changing protection', async () => {
  const { api, env, state } = await environment();
  await api.write({ key: 'wallet-1', value: secret });
  state.pendingGet = {};
  const pending = api.enrollPasskey({ key: 'wallet-1', value: secret });
  while (!state.pendingGet.resolve) await new Promise(setImmediate);
  env.document.visibilityState = 'hidden';
  env.document.dispatchEvent(new Event('visibilitychange'));
  await assert.rejects(pending, { code: 'aborted' });
  env.document.visibilityState = 'visible';
  assert.equal(await api.read({ key: 'wallet-1' }), secret);
});

test('no queued surprise prompt when another tab owns the ceremony lock', async () => {
  const { api, env, state } = await environment();
  env.navigator.locks.request = async (_, options, callback) => {
    assert.equal(options.ifAvailable, true); return callback(null);
  };
  await assert.rejects(api.enrollPasskey({ key: 'wallet-1', value: secret }), { code: 'busy' });
  assert.equal(state.creates, 0);
});

test('automatic prompting requires focus and cross-tab lock support', async () => {
  const { api, env } = await environment();
  await api.write({ key: 'wallet-1', value: secret });
  env.navigator.locks = undefined;
  await assert.rejects(api.read({ key: 'wallet-1', trigger: 'automatic' }), { code: 'notCompleted' });
  assert.equal(await api.read({ key: 'wallet-1' }), secret);
});

test('missing local wallet cannot be restored by an existing passkey', async () => {
  const { api } = await environment();
  assert.equal(await api.read({ key: 'missing-wallet', requireAuthentication: true }), null);
});

test('insecure origins and embedded frames cannot enroll or access credentials', async () => {
  const { api, env } = await environment();
  env.self = {};
  assert.equal((await api.capabilities()).available, false);
  await assert.rejects(api.write({ key: 'wallet-1', value: secret }), { code: 'unavailable' });
});

test('password-manager storage reports unknown rather than assuming a durable save', async () => {
  const { api, env } = await environment();
  env.PasswordCredential = class { constructor(value) { Object.assign(this, value); } };
  env.navigator.credentials.store = async () => {};
  assert.equal(await api.savePassword({ username: 'wallet-id', password: secret }), 'unknown');
});

test('deletion removes active and abandoned records without notifying secrets', async () => {
  const { api, store } = await environment();
  const notifications = [];
  api.subscribe((message) => notifications.push(message));
  await api.write({ key: 'wallet-1', value: secret });
  store.stages.set('staged:abandoned', structuredClone(store.records.get('wallet-1')));
  await api.delete({ key: 'wallet-1' });
  assert.equal(await api.metadata({ key: 'wallet-1' }), null);
  assert.equal(store.stages.size, 0);
  assert.equal(JSON.stringify(notifications).includes(secret), false);
  assert.equal(notifications.every((event) => event.external === false), true);
});

test('protected deletion requires fresh one-use authorization without a second prompt', async () => {
  const { api, state, store } = await environment();
  await api.enrollPasskey({ key: 'wallet-1', value: secret });
  await assert.rejects(api.delete({ key: 'wallet-1' }), { code: 'staleOperation' });
  const gets = state.gets;
  const authorization = await api.prepareDelete({ key: 'wallet-1' });
  assert.equal(typeof authorization, 'string');
  assert.equal(state.gets, gets + 1);
  await api.delete({ key: 'wallet-1', authorization });
  assert.equal(state.gets, gets + 1);
  assert.equal(store.records.size, 0);
  await api.enrollPasskey({ key: 'wallet-1', value: secret });
  await assert.rejects(api.delete({ key: 'wallet-1', authorization }), { code: 'staleOperation' });
});

for (const reason of ['lock', 'expiry', 'rotation', 'other-wallet']) {
  test(`protected deletion rejects authorization after ${reason}`, async () => {
    let now = 0;
    const { api } = await environment({ now: () => now });
    await api.enrollPasskey({ key: 'wallet-1', value: secret });
    if (reason === 'other-wallet') await api.enrollPasskey({ key: 'wallet-2', value: secret });
    const authorization = await api.prepareDelete({ key: 'wallet-1' });
    if (reason === 'lock') api.cancel();
    if (reason === 'expiry') now = 60000;
    if (reason === 'rotation') await api.write({ key: 'wallet-1', value: changedSecret, requireAuthentication: true });
    const key = reason === 'other-wallet' ? 'wallet-2' : 'wallet-1';
    await assert.rejects(api.delete({ key, authorization }), { code: 'staleOperation' });
    assert.ok(await api.metadata({ key }));
  });
}

test('deletion authorization cancellation preserves the protected envelope', async () => {
  const { api, state } = await environment();
  await api.enrollPasskey({ key: 'wallet-1', value: secret });
  state.rejectGet = true;
  await assert.rejects(api.prepareDelete({ key: 'wallet-1' }), { code: 'notCompleted' });
  assert.equal((await api.metadata({ key: 'wallet-1' })).protection, 'passkeyPrf');
});

test('persistent storage denial does not create a false backup guarantee or lose access', async () => {
  const { api, env } = await environment();
  let requests = 0;
  env.navigator.storage = { async persist() { requests++; return false; } };
  await api.write({ key: 'wallet-1', value: secret });
  assert.equal(await api.read({ key: 'wallet-1' }), secret);
  assert.equal((await api.metadata({ key: 'wallet-1' })).protection, 'browserLocal');
  await api.write({ key: 'wallet-2', value: secret });
  assert.equal(requests, 1);
});

test('deletion-purpose credential verification reuses exactly one fresh ceremony', async () => {
  const { api, state } = await environment();
  await api.enrollPasskey({ key: 'wallet-1', value: secret });
  const gets = state.gets;
  assert.equal(await api.read({ key: 'wallet-1', requireAuthentication: true, purpose: 'delete' }), secret);
  const authorization = await api.prepareDelete({ key: 'wallet-1' });
  assert.equal(state.gets, gets + 1);
  await api.delete({ key: 'wallet-1', authorization });
  assert.equal(state.gets, gets + 1);
});

test('another tab loses unattended access and receives only revision events after protection', async () => {
  const channels = new Set();
  const messages = [];
  class Channel {
    constructor() { channels.add(this); }
    postMessage(message) {
      messages.push(structuredClone(message));
      for (const channel of channels) if (channel !== this) {
        queueMicrotask(() => channel.onmessage?.({ data: structuredClone(message) }));
      }
    }
  }
  const store = new MemoryStore();
  const first = await environment({ store, channelClass: Channel });
  const second = await environment({ store, channelClass: Channel });
  second.env.navigator.credentials = first.env.navigator.credentials;
  const events = [];
  second.api.subscribe(event => events.push(event));
  await first.api.write({ key: 'wallet-1', value: secret });
  assert.equal(await second.api.read({ key: 'wallet-1' }), secret);
  await first.api.enrollPasskey({ key: 'wallet-1', value: secret });
  const gets = first.state.gets;
  first.state.rejectGet = true;
  await assert.rejects(second.api.read({ key: 'wallet-1', requireAuthentication: false }), { code: 'notCompleted' });
  assert.equal(first.state.gets, gets + 1);
  assert.equal(events.at(-1).protection, 'passkeyPrf');
  assert.equal(events.at(-1).external, true);
  assert.ok(messages.every(message => Object.keys(message).sort().join(',') === 'key,protection,revision'));
  assert.equal(JSON.stringify(messages).includes(secret), false);
  assert.equal(store.records.get('wallet-1').unattendedKey, undefined);
});

test('missing Web Locks disables new enrollment without stranding an existing passkey', async () => {
  const { api, env } = await environment();
  await api.enrollPasskey({ key: 'wallet-1', value: secret });
  env.navigator.locks = undefined;
  assert.equal((await api.capabilities()).passkeys, false);
  await assert.rejects(api.enrollPasskey({ key: 'wallet-2', value: secret }), { code: 'unavailable' });
  assert.equal(await api.read({ key: 'wallet-1' }), secret);
  assert.equal(await api.metadata({ key: 'wallet-2' }), null);
});

// The production caller must freshly verify the password with the wallet SDK.
// These tests exercise the bridge's destructive-change boundary, never claim
// that JavaScript validates the previous vault's password or releases its secret.
async function lostProviderFixture(options={}) {
  const original=await environment();
  await original.api.write({key:'wallet-1',value:secret});
  await original.api.enrollPasskey({key:'wallet-1',value:secret});
  const replacement=await environment({...options,store:original.store});
  return {...replacement,original,previous:structuredClone(original.store.records.get('wallet-1'))};
}

test('explicit password-verified replacement establishes a new PRF without releasing the old credential',async()=>{
  const {api,state,store,original,previous}=await lostProviderFixture();
  await assert.rejects(api.read({key:'wallet-1'}),{code:'notCompleted'});
  const metadata=await api.replacePasskeyAfterPasswordVerification({key:'wallet-1',value:secret,expectedRevision:2,label:'Recovered wallet'});
  assert.deepEqual(metadata,{protection:'passkeyPrf',revision:3,enrolled:true});
  assert.equal(state.creates,1);assert.equal(state.gets,2); // failed old read + new assertion
  assert.equal(await api.read({key:'wallet-1'}),secret);
  await assert.rejects(original.api.read({key:'wallet-1'}),{code:'notCompleted'});
  const current=store.records.get('wallet-1');
  assert.notEqual(current.credentialId,previous.credentialId);
  assert.notEqual(current.enrollmentId,previous.enrollmentId);
  assert.equal(current.unattendedKey,undefined);assert.equal(store.stages.size,0);
  assert.equal(JSON.stringify(metadata).includes(secret),false);
});

for(const method of ['replacePasskeyAfterPasswordVerification','prepareDeleteAfterPasswordVerification']){
  for(const [label,args,code] of [
    ['missing revision',{},'invalidResponse'],
    ['fractional revision',{expectedRevision:2.5},'invalidResponse'],
    ['stale revision',{expectedRevision:1},'staleOperation'],
    ['another wallet',{key:'wallet-other',expectedRevision:2},'walletUnavailable'],
  ])test(`${method} rejects ${label} before any ceremony`,async()=>{
    const {api,state,store,previous}=await lostProviderFixture();
    await assert.rejects(api[method]({key:'wallet-1',value:secret,...args}),{code});
    assert.equal(state.creates,0);assert.equal(state.gets,0);
    assert.deepEqual(store.records.get('wallet-1'),previous);
  });
  test(`${method} requires Web Locks and an existing protected record`,async()=>{
    const {api,env,store,state,previous}=await lostProviderFixture();
    delete env.navigator.locks;
    await assert.rejects(api[method]({key:'wallet-1',value:secret,expectedRevision:2}),{code:'unavailable'});
    assert.deepEqual(store.records.get('wallet-1'),previous);assert.equal(state.creates,0);
    const unprotected=await environment();
    await unprotected.api.write({key:'wallet-1',value:secret});
    await assert.rejects(unprotected.api[method]({key:'wallet-1',value:secret,expectedRevision:1}),{code:'invalidated'});
    assert.equal(await unprotected.api.read({key:'wallet-1'}),secret);
  });
}

for(const failure of ['createPrf','getPrf','rejectGet','failSignature','corruptStage','failStage','failPromote','wrongChallenge']){
  test(`password-verified passkey replacement preserves prior protection on ${failure}`,async()=>{
    const {api,state,store,previous}=await lostProviderFixture();
    if(failure==='createPrf'||failure==='getPrf')state[failure]=false;
    else if(failure==='wrongChallenge')state.mutateGet=credential=>{
      const client=JSON.parse(new TextDecoder().decode(credential.response.clientDataJSON));
      credential.response.clientDataJSON=text.encode(JSON.stringify({...client,challenge:b64(random(32))}));
    };
    else if(['corruptStage','failStage','failPromote'].includes(failure))store[failure]=true;
    else state[failure]=true;
    await assert.rejects(api.replacePasskeyAfterPasswordVerification({key:'wallet-1',value:secret,expectedRevision:2}));
    assert.deepEqual(store.records.get('wallet-1'),previous);
    assert.equal(store.stages.size,0);assert.equal(previous.unattendedKey,undefined);
  });
}

test('canceling password-verified replacement discards a pending assertion and preserves the old record',async()=>{
  const {api,state,store,previous}=await lostProviderFixture();
  state.pendingGet={};
  const pending=api.replacePasskeyAfterPasswordVerification({key:'wallet-1',value:secret,expectedRevision:2});
  const rejection=assert.rejects(pending,{code:'aborted'});
  while(!state.pendingGet.resolve)await new Promise(resolve=>setImmediate(resolve));
  api.cancel();await rejection;
  assert.deepEqual(store.records.get('wallet-1'),previous);assert.equal(store.stages.size,0);
});

test('a changed stored revision cannot be overwritten after replacement assertion',async()=>{
  const {api,state,store,previous}=await lostProviderFixture();
  state.mutateGet=()=>store.records.set('wallet-1',{...previous,revision:3});
  await assert.rejects(api.replacePasskeyAfterPasswordVerification({key:'wallet-1',value:secret,expectedRevision:2}));
  assert.deepEqual(store.records.get('wallet-1'),{...previous,revision:3});
  assert.equal(store.stages.size,0);
});

test('explicit password-verified deletion grants no secret and consumes a single matching permit',async()=>{
  const {api,state,store}=await lostProviderFixture();
  const authorization=await api.prepareDeleteAfterPasswordVerification({key:'wallet-1',expectedRevision:2});
  assert.equal(typeof authorization,'string');assert.notEqual(authorization,secret);
  assert.equal(state.creates,0);assert.equal(state.gets,0);
  await api.delete({key:'wallet-1',authorization});
  assert.equal(store.records.size,0);assert.equal(store.stages.size,0);
  await api.write({key:'wallet-1',value:secret});
  await api.enrollPasskey({key:'wallet-1',value:secret});
  await assert.rejects(api.delete({key:'wallet-1',authorization}),{code:'staleOperation'});
});

for(const invalidation of ['lock','expiry','otherWallet','revision'])test(`password-verified delete permit rejects ${invalidation}`,async()=>{
  let now=100;
  const {api,store,previous}=await lostProviderFixture({now:()=>now});
  const authorization=await api.prepareDeleteAfterPasswordVerification({key:'wallet-1',expectedRevision:2});
  let key='wallet-1';
  if(invalidation==='lock')api.cancel();
  if(invalidation==='expiry')now+=60001;
  if(invalidation==='otherWallet'){key='wallet-other';store.records.set(key,{...previous,key});}
  if(invalidation==='revision')store.records.set(key,{...previous,revision:3});
  await assert.rejects(api.delete({key,authorization}),{code:'staleOperation'});
  assert.equal(store.records.get('wallet-1').protection,'passkeyPrf');
});

test('external revision notification cancels password-verified replacement before promotion',async()=>{
  let channel;
  class Channel{constructor(){channel=this;}postMessage(){}}
  const {api,state,store,previous}=await lostProviderFixture({channelClass:Channel});
  state.pendingGet={};
  const pending=api.replacePasskeyAfterPasswordVerification({key:'wallet-1',value:secret,expectedRevision:2});
  const rejection=assert.rejects(pending,{code:'aborted'});
  while(!state.pendingGet.resolve)await new Promise(resolve=>setImmediate(resolve));
  channel.onmessage({data:{key:'wallet-1',revision:3,protection:'passkeyPrf'}});
  await rejection;assert.deepEqual(store.records.get('wallet-1'),previous);assert.equal(store.stages.size,0);
});

test('external revision notification revokes a password-verified deletion permit',async()=>{
  let channel;
  class Channel{constructor(){channel=this;}postMessage(){}}
  const {api,store,previous}=await lostProviderFixture({channelClass:Channel});
  const authorization=await api.prepareDeleteAfterPasswordVerification({key:'wallet-1',expectedRevision:2});
  channel.onmessage({data:{key:'wallet-1',revision:3,protection:'passkeyPrf'}});
  await assert.rejects(api.delete({key:'wallet-1',authorization}),{code:'staleOperation'});
  assert.deepEqual(store.records.get('wallet-1'),previous);
});

// Kept in this CI-aggregated suite so the pre-SDK browser gate always runs.
const {createBrowserSupport}=require('../../../web/services/wallet_browser_support.js');
function startupEnvironment(){
  let storageOpens=0;
  const environment={isSecureContext:true,indexedDB:{open(){storageOpens++;}},
    crypto:{subtle:{}},navigator:{locks:{async request(name,options,callback){
      assert.equal(name,'gleec-browser-capability-probe');assert.equal(options.ifAvailable,true);return callback(null);
    }}},document:{readyState:'loading',getElementById(){return null;},addEventListener(){}}};
  return {environment,storageOpens:()=>storageOpens};
}

test('browser startup minimum is independent of passkeys and never opens wallet storage',async()=>{
  const fixture=startupEnvironment();
  const support=createBrowserSupport(fixture.environment);
  assert.equal(await support.check(),true);await support.ready;
  assert.equal(fixture.storageOpens(),0);
});
for(const missing of ['secureContext','indexedDB','webCrypto','webLocks','usableLocks']){
  test(`browser startup blocks missing ${missing} before SDK work`,async()=>{
    const fixture=startupEnvironment();const environment=fixture.environment;
    if(missing==='secureContext')environment.isSecureContext=false;
    if(missing==='indexedDB')delete environment.indexedDB;
    if(missing==='webCrypto')environment.crypto={};
    if(missing==='webLocks')environment.navigator.locks=undefined;
    if(missing==='usableLocks')environment.navigator.locks.request=async()=>{throw new DOMException('Private profile details','SecurityError');};
    const support=createBrowserSupport(environment);let started=false;support.ready.then(()=>{started=true;});
    assert.equal(await support.check(),false);assert.equal(started,false);assert.equal(fixture.storageOpens(),0);
  });
}

test('browser retry only rechecks capability and starts once it is available',async()=>{
  const fixture=startupEnvironment();const locks=fixture.environment.navigator.locks;
  fixture.environment.navigator.locks=undefined;
  const support=createBrowserSupport(fixture.environment);let starts=0;support.ready.then(()=>starts++);
  assert.equal(await support.check(),false);assert.equal(starts,0);
  fixture.environment.navigator.locks=locks;
  assert.equal(await support.check(),true);await support.ready;assert.equal(starts,1);
  assert.equal(await support.check(),true);assert.equal(starts,1);assert.equal(fixture.storageOpens(),0);
});

test('unresponsive browser lock capability cannot leave an unexplained startup spinner',async()=>{
  const fixture=startupEnvironment();fixture.environment.navigator.locks.request=()=>new Promise(()=>{});
  const support=createBrowserSupport(fixture.environment,{timeoutMs:5});
  assert.equal(await support.check(),false);assert.equal(fixture.storageOpens(),0);
});

test('Flutter and optional KDF preload both wait for the browser capability gate',()=>{
  const root=path.resolve(__dirname,'../../..');
  const html=readFileSync(path.join(root,'web/index.html'),'utf8');
  const flutter=readFileSync(path.join(root,'web/flutter_bootstrap.js'),'utf8');
  const preload=readFileSync(path.join(root,'web/services/wallet_bootstrap.js'),'utf8');
  assert.ok(html.indexOf('services/wallet_browser_support.js')<html.indexOf('src="flutter_bootstrap.js"'));
  assert.ok(flutter.indexOf('gleecWalletBrowserSupport.ready')<flutter.indexOf('_flutter.loader.load'));
  assert.ok(preload.indexOf('gleecWalletBrowserSupport.ready')<preload.indexOf('initialize()'));
});
