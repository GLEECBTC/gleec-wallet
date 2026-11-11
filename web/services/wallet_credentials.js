/* Gleec's local credential vault. No accounts, cloud backups, or telemetry.
 * A browserLocal key is deliberately unattended: encryption here is not an
 * authentication boundary. passkeyPrf records require a fresh WebAuthn PRF.
 */
(function (root) {
  'use strict';

  const SCHEMA = 1;
  const DB_NAME = 'gleec-wallet-credentials-v1';
  const STORE_NAME = 'credentials';
  const LOCK_NAME = 'gleec-wallet-credentials-v1';
  const EVENT_NAME = 'gleecWalletProtectionChanged';
  const encoder = new TextEncoder();
  const decoder = new TextDecoder('utf-8', { fatal: true });

  class VaultError extends Error {
    constructor(code) {
      super(code);
      this.name = 'WalletCredentialError';
      this.code = code;
    }
  }

  const fail = (code) => { throw new VaultError(code); };
  const bytes = (value) => {
    if (value instanceof ArrayBuffer) return new Uint8Array(value);
    if (ArrayBuffer.isView(value)) {
      return new Uint8Array(value.buffer, value.byteOffset, value.byteLength);
    }
    return fail('invalidResponse');
  };
  const equal = (left, right) => {
    const a = bytes(left), b = bytes(right);
    if (a.length !== b.length) return false;
    let difference = 0;
    for (let i = 0; i < a.length; i++) difference |= a[i] ^ b[i];
    return difference === 0;
  };
  const concat = (...arrays) => {
    const output = new Uint8Array(arrays.reduce((n, a) => n + a.length, 0));
    let offset = 0;
    for (const array of arrays) { output.set(array, offset); offset += array.length; }
    return output;
  };
  const base64url = (value) => {
    let binary = '';
    for (const byte of bytes(value)) binary += String.fromCharCode(byte);
    return btoa(binary).replaceAll('+', '-').replaceAll('/', '_').replace(/=+$/, '');
  };
  const fromBase64url = (value) => {
    if (typeof value !== 'string' || !/^[A-Za-z0-9_-]+$/.test(value)) {
      return fail('invalidResponse');
    }
    try {
      return Uint8Array.from(atob(value.replaceAll('-', '+').replaceAll('_', '/')),
        (character) => character.charCodeAt(0));
    } catch (_) { return fail('invalidResponse'); }
  };
  const safeError = (error) => {
    if (error instanceof VaultError) return error;
    if (error?.name === 'AbortError') return new VaultError('aborted');
    // Browsers intentionally do not distinguish cancellation, timeout, missing
    // credentials and policy rejection. Do not claim a passkey was deleted.
    if (error?.name === 'NotAllowedError') return new VaultError('notCompleted');
    if (error?.name === 'NotSupportedError') return new VaultError('unsupported');
    if (error?.name === 'SecurityError') return new VaultError('unavailable');
    return new VaultError('storageFailed');
  };
  const keyString = (key) => {
    if (typeof key !== 'string' || key.length === 0 || key.length > 512) {
      return fail('invalidResponse');
    }
    return key;
  };
  const secretString = (value) => {
    if (typeof value !== 'string' || value.length === 0 || value.length > 16384) {
      return fail('invalidResponse');
    }
    return value;
  };

  function indexedDbStore(environment) {
    let database;
    async function open() {
      if (!database) database = new Promise((resolve, reject) => {
        if (!environment.indexedDB) return reject(new VaultError('unavailable'));
        const request = environment.indexedDB.open(DB_NAME, 1);
        request.onupgradeneeded = () => {
          const store = request.result.createObjectStore(STORE_NAME, { keyPath: 'slot' });
          store.createIndex('walletKey', 'walletKey');
        };
        request.onerror = () => reject(new VaultError('storageFailed'));
        request.onblocked = () => reject(new VaultError('busy'));
        request.onsuccess = () => {
          request.result.onversionchange = () => { request.result.close(); database = null; };
          resolve(request.result);
        };
      }).catch((error) => { database = null; throw error; });
      return database;
    }
    async function transaction(mode, action) {
      const db = await open();
      return new Promise((resolve, reject) => {
        let tx;
        try { tx = db.transaction(STORE_NAME, mode, { durability: 'strict' }); }
        catch (_) { tx = db.transaction(STORE_NAME, mode); }
        let result, failure;
        const abort = (code) => { failure = code; tx.abort(); };
        action(tx.objectStore(STORE_NAME), (value) => { result = value; }, abort);
        tx.oncomplete = () => resolve(result);
        tx.onabort = tx.onerror = () => reject(new VaultError(failure ?? 'storageFailed'));
      });
    }
    async function getSlot(slot) {
      return transaction('readonly', (store, resolve) => {
        const request = store.get(slot);
        request.onsuccess = () => resolve(request.result?.record ?? null);
      });
    }
    return {
      get: (key) => getSlot(`active:${key}`),
      getStaged: getSlot,
      async stage(record, stageId) {
        const slot = `staged:${stageId}`;
        await transaction('readwrite', (store) => {
          store.add({ slot, walletKey: record.key, record });
        });
        return slot;
      },
      async discardStage(slot) {
        if (!slot.startsWith('staged:')) fail('invalidResponse');
        await transaction('readwrite', (store) => store.delete(slot));
      },
      async promote(key, expectedRevision, stageSlot, stagedRevision) {
        return transaction('readwrite', (store, _, abort) => {
          const current = store.get(`active:${key}`);
          current.onsuccess = () => {
            if ((current.result?.record?.revision ?? null) !== expectedRevision) {
              abort('staleOperation'); return;
            }
            const staged = store.get(stageSlot);
            staged.onsuccess = () => {
              const row = staged.result;
              if (!row || row.walletKey !== key || row.record.revision !== stagedRevision) {
                abort('staleOperation'); return;
              }
              // Readback/decryption already passed. Promote the exact stored
              // row and erase every staged copy in the same atomic commit.
              const rows = store.index('walletKey').getAllKeys(key);
              rows.onsuccess = () => {
                for (const slot of rows.result) store.delete(slot);
                store.put({ slot: `active:${key}`, walletKey: key, record: row.record });
              };
            };
          };
        });
      },
      async remove(key, expectedRevision) {
        return transaction('readwrite', (store, _, abort) => {
          const current = store.get(`active:${key}`);
          current.onsuccess = () => {
            if ((current.result?.record?.revision ?? null) !== expectedRevision) {
              abort('staleOperation'); return;
            }
            const rows = store.index('walletKey').getAllKeys(key);
            rows.onsuccess = () => { for (const slot of rows.result) store.delete(slot); };
          };
        });
      },
    };
  }

  // WebAuthn ES256 signatures use ASN.1 DER; WebCrypto consumes IEEE P1363.
  // This is a strict encoding conversion, not a signature implementation.
  function es256Signature(signature) {
    const input = bytes(signature);
    if (input.length < 8 || input.length > 72 || input[0] !== 0x30 ||
        input[1] !== input.length - 2) return fail('invalidResponse');
    const output = new Uint8Array(64);
    let offset = 2;
    for (let part = 0; part < 2; part++) {
      if (input[offset++] !== 0x02) return fail('invalidResponse');
      const length = input[offset++];
      if (!length || length > 33 || offset + length > input.length ||
          (input[offset] & 0x80)) return fail('invalidResponse');
      let integer = input.slice(offset, offset + length);
      offset += length;
      if (integer.length > 1 && integer[0] === 0) {
        if (!(integer[1] & 0x80)) return fail('invalidResponse');
        integer = integer.slice(1);
      }
      if (integer.length > 32) return fail('invalidResponse');
      output.set(integer, part * 32 + 32 - integer.length);
    }
    if (offset !== input.length) return fail('invalidResponse');
    return output;
  }

  function createWalletCredentials(environment, testOptions = {}) {
    const store = testOptions.store ?? indexedDbStore(environment);
    const crypto = environment.crypto;
    let generation = 0;
    let operation = null;
    let requestedPersistence = false;
    // Deletion authorization stays in this process only. It contains no wallet
    // credential, survives no lock/reload, and is consumed before the CAS erase.
    const deletionPermits = new Map();
    let pendingDeletion = null;
    const subscribers = new Set();
    const channel = environment.BroadcastChannel
      ? new environment.BroadcastChannel(LOCK_NAME) : null;
    const random = (length) => crypto.getRandomValues(new Uint8Array(length));
    const identifier = () => base64url(random(18));
    const nextRevision = (previous) => (previous?.revision ?? 0) + 1;
    const context = () => {
      const location = environment.location;
      const local = ['localhost', '127.0.0.1', '[::1]'].includes(location?.hostname);
      if (!environment.isSecureContext || !crypto?.subtle ||
          (location?.protocol !== 'https:' && !(local && location?.protocol === 'http:')) ||
          (environment.top && environment.self && environment.top !== environment.self)) {
        return fail('unavailable');
      }
      return { origin: location.origin, rpId: location.hostname };
    };
    const assertVisible = () => {
      if (environment.document?.visibilityState === 'hidden') fail('aborted');
    };
    const assertOperation = (token) => {
      if (token !== generation || operation?.signal.aborted) fail('staleOperation');
      assertVisible();
    };
    const notify = (record, key) => {
      deletionPermits.clear();
      pendingDeletion = null;
      const message = { key, revision: record?.revision ?? null,
        protection: record?.protection ?? null };
      const detail = Object.freeze({ ...message, external: false });
      channel?.postMessage(message);
      for (const subscriber of subscribers) subscriber(detail);
      if (environment.CustomEvent && environment.dispatchEvent) {
        environment.dispatchEvent(new environment.CustomEvent(EVENT_NAME, { detail }));
      }
    };
    const cancel = () => {
      generation++;
      deletionPermits.clear();
      pendingDeletion = null;
      operation?.abort();
    };
    if (channel) channel.onmessage = (event) => {
      const data = event.data;
      if (!data || typeof data.key !== 'string' ||
          (data.revision !== null && !Number.isSafeInteger(data.revision)) ||
          ![null, 'browserLocal', 'passkeyPrf'].includes(data.protection)) return;
      cancel();
      const detail = Object.freeze({ key: data.key, revision: data.revision,
        protection: data.protection, external: true });
      for (const subscriber of subscribers) subscriber(detail);
      if (environment.CustomEvent && environment.dispatchEvent) {
        environment.dispatchEvent(new environment.CustomEvent(EVENT_NAME, { detail }));
      }
    };
    environment.document?.addEventListener('visibilitychange', () => {
      if (environment.document.visibilityState === 'hidden') cancel();
    });
    environment.addEventListener?.('pagehide', cancel);

    const exclusive = async (callback, automatic = false) => {
      if (operation) return fail('busy');
      if (automatic && (!environment.navigator?.locks ||
          environment.document?.hasFocus?.() === false)) return fail('notCompleted');
      operation = new AbortController();
      const controller = operation;
      const token = generation;
      const run = async () => {
        assertOperation(token);
        return callback(token, controller.signal);
      };
      try {
        if (environment.navigator?.locks) {
          return await environment.navigator.locks.request(LOCK_NAME,
            { mode: 'exclusive', ifAvailable: true }, (lock) => lock ? run() : fail('busy'));
        }
        // IDB compare-and-set still makes mutations atomic without Web Locks.
        // Automatic ceremonies are disabled above; explicit attempts may race
        // but a loser cannot replace the winning envelope.
        return await run();
      } catch (error) { throw safeError(error); }
      finally { if (operation === controller) operation = null; }
    };

    const deletionPermit = (record, token) => {
      if (!environment.performance?.now) fail('unavailable');
      const authorization = identifier();
      deletionPermits.clear();
      deletionPermits.set(authorization, { key: record.key, revision: record.revision,
        generation: token, expires: environment.performance.now() + 60000 });
      return authorization;
    };
    const validDeletionPermit = (permit, record, token) => permit &&
      permit.key === record.key && permit.revision === record.revision &&
      permit.generation === token && environment.performance?.now &&
      environment.performance.now() < permit.expires;

    const validateRecord = (record, key) => {
      if (!record || record.schema !== SCHEMA || record.key !== key ||
          !Number.isSafeInteger(record.revision) || record.revision < 1 || record.origin !== context().origin ||
          !['browserLocal', 'passkeyPrf'].includes(record.protection)) fail('envelopeCorrupt');
      return record;
    };
    const aad = (record) => encoder.encode(JSON.stringify([
      SCHEMA, record.key, record.protection, record.origin,
      record.rpId ?? '', record.credentialId ?? '', record.enrollmentId ?? '',
    ]));
    const encrypt = async (record, key, value) => {
      const plaintext = encoder.encode(value);
      const iv = random(12);
      try {
        const ciphertext = await crypto.subtle.encrypt({ name: 'AES-GCM', iv,
          additionalData: aad(record), tagLength: 128 }, key, plaintext);
        return { ...record, iv, ciphertext };
      } finally { plaintext.fill(0); }
    };
    const decrypt = async (record, key) => {
      try {
        if (bytes(record.iv).length !== 12 || bytes(record.ciphertext).length < 17) {
          fail('envelopeCorrupt');
        }
        const plaintext = new Uint8Array(await crypto.subtle.decrypt({ name: 'AES-GCM',
          iv: record.iv, additionalData: aad(record), tagLength: 128 }, key, record.ciphertext));
        try { return secretString(decoder.decode(plaintext)); }
        finally { plaintext.fill(0); }
      } catch (_) { return fail('envelopeCorrupt'); }
    };
    const checkClient = (response, type, challenge, expected) => {
      const raw = bytes(response.clientDataJSON);
      if (raw.length > 16384) return fail('invalidResponse');
      let data;
      try { data = JSON.parse(decoder.decode(raw)); } catch (_) { fail('invalidResponse'); }
      if (data.type !== type || data.origin !== expected.origin || data.crossOrigin === true ||
          (data.topOrigin !== undefined && data.topOrigin !== expected.origin) ||
          !equal(fromBase64url(data.challenge), challenge)) fail('invalidResponse');
      return raw;
    };
    const checkAuthenticator = async (authenticatorData, expected) => {
      const data = bytes(authenticatorData);
      if (data.length < 37 || (data[32] & 0x05) !== 0x05 ||
          !equal(data.slice(0, 32), await crypto.subtle.digest('SHA-256', encoder.encode(expected.rpId)))) {
        fail('invalidResponse');
      }
      return data;
    };
    const importPublicKey = async (spki, algorithm) => {
      if (algorithm !== -7 && algorithm !== -257) fail('invalidResponse');
      try {
        return await crypto.subtle.importKey('spki', spki,
          algorithm === -7 ? { name: 'ECDSA', namedCurve: 'P-256' }
            : { name: 'RSASSA-PKCS1-v1_5', hash: 'SHA-256' }, false, ['verify']);
      } catch (_) { return fail('invalidResponse'); }
    };
    const prfKey = async (record, token, signal, expectedPrf = null) => {
      assertOperation(token);
      const expected = context();
      if (record.rpId !== expected.rpId) fail('invalidResponse');
      const challenge = random(32);
      const credential = await environment.navigator.credentials.get({
        publicKey: { challenge, rpId: expected.rpId, userVerification: 'required',
          timeout: 60000, allowCredentials: [{ type: 'public-key',
            id: fromBase64url(record.credentialId) }],
          extensions: { prf: { eval: { first: record.prfInput } } } }, signal,
      });
      assertOperation(token);
      if (!credential || credential.type !== 'public-key' ||
          !equal(credential.rawId, fromBase64url(record.credentialId))) fail('invalidResponse');
      if (credential.response.userHandle != null &&
          !equal(credential.response.userHandle, record.userHandle)) fail('invalidResponse');
      const client = checkClient(credential.response, 'webauthn.get', challenge, expected);
      const authenticator = await checkAuthenticator(credential.response.authenticatorData, expected);
      const publicKey = await importPublicKey(record.publicKey, record.algorithm);
      const signature = record.algorithm === -7
        ? es256Signature(credential.response.signature) : bytes(credential.response.signature);
      const valid = await crypto.subtle.verify(record.algorithm === -7
        ? { name: 'ECDSA', hash: 'SHA-256' } : { name: 'RSASSA-PKCS1-v1_5' }, publicKey,
      signature, concat(authenticator, new Uint8Array(await crypto.subtle.digest('SHA-256', client))));
      if (!valid) fail('invalidResponse');
      const result = credential.getClientExtensionResults?.().prf?.results?.first;
      if (!result) fail('prfUnavailable');
      const raw = bytes(result);
      try {
        if (raw.length !== 32) fail('prfUnavailable');
        if (expectedPrf && !equal(raw, expectedPrf)) fail('prfUnavailable');
        return await crypto.subtle.importKey('raw', raw, 'AES-GCM', false, ['encrypt', 'decrypt']);
      }
      finally { raw.fill(0); }
    };
    const unlockRecord = async (record, token, signal) => {
      validateRecord(record, record.key);
      if (record.protection === 'browserLocal') {
        if (!record.unattendedKey) fail('envelopeCorrupt');
        return { value: await decrypt(record, record.unattendedKey), key: record.unattendedKey };
      }
      const key = await prfKey(record, token, signal);
      return { value: await decrypt(record, key), key };
    };
    const commit = async (previous, next, secret, encryptionKey, token) => {
      assertOperation(token);
      const stageSlot = await store.stage(next, identifier());
      try {
        const persisted = validateRecord(await store.getStaged(stageSlot), next.key);
        if (persisted.revision !== next.revision || await decrypt(persisted, encryptionKey) !== secret) {
          fail('storageFailed');
        }
        assertOperation(token);
        await store.promote(next.key, previous?.revision ?? null, stageSlot, next.revision);
        // Promotion has already invalidated the old path, even if the active
        // readback below encounters a storage error. Revoke other tabs now.
        notify(next, next.key);
        // Verify the active record with the key already authorized by this
        // ceremony. A second credentials.get() would only repeat the OS prompt.
        const active = validateRecord(await store.get(next.key), next.key);
        if (active.revision !== next.revision ||
            active.protection !== next.protection ||
            await decrypt(active, encryptionKey) !== secret) fail('storageFailed');
        // No unattended or abandoned staging copy survives successful promotion.
        // A crash after promotion still has the verified new unlock path.
        assertOperation(token);
      } finally {
        // Staged records are never an unlock fallback. A later promotion/delete
        // also removes them atomically if a process died before this cleanup.
        await store.discardStage(stageSlot).catch(() => {});
      }
    };

    const registerPasskey = async (key, value, label, previous, token, signal) => {
      const expected = context();
      if (!environment.PublicKeyCredential || !environment.navigator?.credentials) fail('unsupported');
      if (!environment.navigator?.locks) fail('unavailable');
      const challenge = random(32), prfInput = random(32), userHandle = random(32);
      const enrollmentId = identifier();
      const displayName = String(label).slice(0, 64);
      assertOperation(token);
      const credential = await environment.navigator.credentials.create({ publicKey: {
        challenge, rp: { id: expected.rpId, name: 'Gleec Wallet' },
        user: { id: userHandle, name: `${displayName} · ${enrollmentId.slice(0, 8)}`, displayName },
        pubKeyCredParams: [{ type: 'public-key', alg: -7 }, { type: 'public-key', alg: -257 }],
        authenticatorSelection: { residentKey: 'required', userVerification: 'required' },
        attestation: 'none', timeout: 60000,
        extensions: { prf: { eval: { first: prfInput } } },
      }, signal });
      assertOperation(token);
      if (!credential || credential.type !== 'public-key' || bytes(credential.rawId).length === 0) {
        fail('invalidResponse');
      }
      checkClient(credential.response, 'webauthn.create', challenge, expected);
      if (!credential.response.getAuthenticatorData || !credential.response.getPublicKey ||
          !credential.response.getPublicKeyAlgorithm) fail('unsupported');
      const authenticator = await checkAuthenticator(credential.response.getAuthenticatorData(), expected);
      if (!(authenticator[32] & 0x40) || authenticator.length < 55) fail('invalidResponse');
      const length = (authenticator[53] << 8) | authenticator[54];
      if (!length || authenticator.length < 55 + length ||
          !equal(authenticator.slice(55, 55 + length), credential.rawId)) fail('invalidResponse');
      const creationPrf = credential.getClientExtensionResults?.().prf;
      if (creationPrf?.enabled !== true) fail('prfUnavailable');
      const creationOutput = creationPrf.results?.first ? bytes(creationPrf.results.first) : null;
      if (creationOutput && creationOutput.length !== 32) fail('prfUnavailable');
      const publicKey = credential.response.getPublicKey();
      const algorithm = credential.response.getPublicKeyAlgorithm();
      if (!publicKey) fail('unsupported');
      await importPublicKey(publicKey, algorithm);
      const record = { schema: SCHEMA, key, revision: nextRevision(previous), protection: 'passkeyPrf',
        origin: expected.origin, rpId: expected.rpId, credentialId: base64url(credential.rawId),
        enrollmentId, userHandle, prfInput, publicKey, algorithm };
      // Registration alone never proves the return-unlock path works.
      let encryptionKey;
      try { encryptionKey = await prfKey(record, token, signal, creationOutput); }
      finally { creationOutput?.fill(0); }
      const next = await encrypt(record, encryptionKey, value);
      await commit(previous, next, value, encryptionKey, token);
      return { protection: 'passkeyPrf', revision: next.revision, enrolled: true };
    };

    const api = {
      async capabilities() {
        try {
          context();
          let passkeys = !!(environment.PublicKeyCredential && environment.navigator?.credentials &&
            environment.navigator?.locks && crypto?.subtle);
          if (passkeys && typeof environment.PublicKeyCredential.getClientCapabilities === 'function') {
            let capabilityTimer;
            try {
              const supported = await Promise.race([
                environment.PublicKeyCredential.getClientCapabilities(),
                new Promise(resolve => { capabilityTimer = setTimeout(() => resolve(null), 1000); }),
              ]);
              // An API existing is not proof of PRF. This controls new offers
              // only; enrolled credential readers never depend on this hint.
              if (supported != null) passkeys = supported['extension:prf'] === true;
            } catch (_) {
              // Older or temporarily unavailable detection remains a candidate;
              // the actual ceremony still must prove PRF output and decryption.
            } finally {
              clearTimeout(capabilityTimer);
            }
          }
          return { available: !!(environment.indexedDB || testOptions.store),
            protection: 'browserLocal', deviceAuthentication: false, passkeys,
            automaticPrompt: !!environment.navigator?.locks };
        } catch (_) {
          return { available: false, protection: 'browserLocal', deviceAuthentication: false,
            passkeys: false, automaticPrompt: false };
        }
      },
      async metadata({ key }) {
        try {
          keyString(key);
          const record = await store.get(key);
          if (!record) return null;
          validateRecord(record, key);
          return { protection: record.protection, revision: record.revision,
            enrolled: record.protection === 'passkeyPrf' };
        } catch (error) { throw safeError(error); }
      },
      async write({ key, value, requireAuthentication = false }) {
        keyString(key); secretString(value);
        return exclusive(async (token, signal) => {
          const expected = context();
          const previous = await store.get(key);
          if (previous) validateRecord(previous, key);
          if (previous?.protection === 'passkeyPrf') {
            if (!requireAuthentication) fail('invalidated');
            const unlocked = await unlockRecord(previous, token, signal);
            const next = await encrypt({ ...previous, revision: nextRevision(previous) }, unlocked.key, value);
            await commit(previous, next, value, unlocked.key, token);
            return;
          }
          if (requireAuthentication) fail('unavailable');
          const encryptionKey = await crypto.subtle.generateKey({ name: 'AES-GCM', length: 256 },
            false, ['encrypt', 'decrypt']);
          const record = await encrypt({ schema: SCHEMA, key, origin: expected.origin,
            protection: 'browserLocal', revision: nextRevision(previous), unattendedKey: encryptionKey }, encryptionKey, value);
          await commit(previous, record, value, encryptionKey, token);
          if (!previous && !requestedPersistence && environment.navigator?.storage?.persist) {
            requestedPersistence = true;
            // A storage grant reduces eviction risk; it is never recovery or a
            // backup guarantee. Keep any browser permission dialog serialized.
            try { await environment.navigator.storage.persist(); } catch (_) { /* Best effort. */ }
            assertOperation(token);
          }
        });
      },
      async read({ key, requireAuthentication = false, trigger = 'explicit', purpose }) {
        keyString(key);
        return exclusive(async (token, signal) => {
          context();
          const record = await store.get(key);
          if (!record) return null;
          validateRecord(record, key);
          if (requireAuthentication && record.protection !== 'passkeyPrf') fail('unavailable');
          const result = await unlockRecord(record, token, signal);
          assertOperation(token);
          if ((await store.get(key))?.revision !== record.revision) fail('staleOperation');
          // Credential verification for deletion and the following erase share
          // this one explicit, purpose-bound ceremony, never a normal unlock.
          if (purpose === 'delete' && trigger !== 'automatic') {
            pendingDeletion = deletionPermit(record, token);
          }
          return result.value;
        }, trigger === 'automatic');
      },
      async prepareDelete({ key }) {
        keyString(key);
        return exclusive(async (token, signal) => {
          const record = await store.get(key);
          if (!record) return null;
          validateRecord(record, key);
          const prepared = pendingDeletion;
          pendingDeletion = null;
          if (validDeletionPermit(deletionPermits.get(prepared), record, token)) return prepared;
          if (record.protection === 'passkeyPrf') {
            await unlockRecord(record, token, signal);
          }
          assertOperation(token);
          if ((await store.get(key))?.revision !== record.revision) fail('staleOperation');
          return deletionPermit(record, token);
        });
      },
      // The app must freshly verify the supplied password against the exact
      // engine wallet/session before these explicit recovery operations. This
      // bridge cannot verify that password without the old PRF and does not
      // pretend to: recovery authorizes destructive replacement/removal only,
      // never disclosure of the old credential or an unattended fallback.
      async prepareDeleteAfterPasswordVerification({ key, expectedRevision }) {
        keyString(key);
        if (!Number.isSafeInteger(expectedRevision) || expectedRevision < 1) fail('invalidResponse');
        return exclusive(async (token) => {
          if (!environment.navigator?.locks) fail('unavailable');
          const previous = await store.get(key);
          if (!previous) fail('walletUnavailable');
          validateRecord(previous, key);
          if (previous.protection !== 'passkeyPrf') fail('invalidated');
          if (previous.revision !== expectedRevision) fail('staleOperation');
          assertOperation(token);
          return deletionPermit(previous, token);
        });
      },
      async delete({ key, authorization }) {
        keyString(key);
        return exclusive(async (token) => {
          const previous = await store.get(key);
          const permit = deletionPermits.get(authorization);
          deletionPermits.delete(authorization);
          if (previous) validateRecord(previous, key);
          if (previous?.protection === 'passkeyPrf' &&
              !validDeletionPermit(permit, previous, token)) fail('staleOperation');
          assertOperation(token);
          await store.remove(key, previous?.revision ?? null);
          if (await store.get(key)) fail('storageFailed');
          notify(null, key);
        });
      },
      cancel,
      async enrollPasskey({ key, value, label = 'Gleec Wallet' }) {
        keyString(key); secretString(value);
        return exclusive(async (token, signal) => {
          const expected = context();
          if (!environment.PublicKeyCredential || !environment.navigator?.credentials) fail('unsupported');
          // Coordinate every new enrollment across tabs. Older environments
          // may still explicitly unlock an existing record; never strand it.
          if (!environment.navigator?.locks) fail('unavailable');
          const previous = await store.get(key);
          if (previous) {
            validateRecord(previous, key);
            const current = await unlockRecord(previous, token, signal);
            if (current.value !== value) fail('invalidResponse');
          }
          return registerPasskey(key, value, label, previous, token, signal);
        });
      },
      async replacePasskeyAfterPasswordVerification({ key, value, expectedRevision, label = 'Gleec Wallet' }) {
        keyString(key); secretString(value);
        if (!Number.isSafeInteger(expectedRevision) || expectedRevision < 1) fail('invalidResponse');
        return exclusive(async (token, signal) => {
          if (!environment.navigator?.locks) fail('unavailable');
          const previous = await store.get(key);
          if (!previous) fail('walletUnavailable');
          validateRecord(previous, key);
          if (previous.protection !== 'passkeyPrf') fail('invalidated');
          if (previous.revision !== expectedRevision) fail('staleOperation');
          return registerPasskey(key, value, label, previous, token, signal);
        });
      },
      async savePassword({ username, password, title = 'Gleec Wallet' }) {
        secretString(password);
        return exclusive(async () => {
          context();
          if (!environment.PasswordCredential || !environment.navigator?.credentials?.store) return 'unavailable';
          try {
            await environment.navigator.credentials.store(new environment.PasswordCredential({
              id: String(username), password, name: String(title),
            }));
            // A fulfilled store request is not reliable proof of the user's
            // provider save/synchronization decision across browsers.
            return 'unknown';
          } catch (error) {
            return ['NotAllowedError', 'AbortError'].includes(error?.name) ? 'declined' : 'failed';
          }
        });
      },
      subscribe(listener) { subscribers.add(listener); return () => subscribers.delete(listener); },
    };
    return Object.freeze(api);
  }

  if (typeof module !== 'undefined' && module.exports) {
    module.exports = { createWalletCredentials };
  } else {
    root.gleecWalletCredentials = createWalletCredentials(root);
  }
})(globalThis);
