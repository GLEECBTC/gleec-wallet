// Integration test against a local Chromium DevTools endpoint. Creates and
// disposes its own isolated context and virtual authenticator; no real wallet.
// Serve this directory on localhost, start an isolated headless Chrome, then:
// node test_units/services/wallet_access/web_credential_backend.browser.test.js
'use strict';

const assert = require('node:assert/strict');

async function main() {
  const endpoint = process.env.GLEEC_TEST_CDP ?? 'http://127.0.0.1:9222';
  const base = process.env.GLEEC_TEST_FIXTURE_URL ?? 'http://localhost:18766/';
  const compiledFixture = process.env.GLEEC_TEST_COMPILED === 'true';
  const trace = (step) => { if (process.env.GLEEC_TEST_TRACE === 'true') console.log(step); };
  for (const address of [endpoint, base]) {
    assert.ok(['localhost', '127.0.0.1', '[::1]'].includes(new URL(address).hostname),
      'This fixture is restricted to localhost');
  }
  const version = await (await fetch(`${endpoint}/json/version`)).json();
  const socket = new WebSocket(version.webSocketDebuggerUrl);
  const pending = new Map();
  const listeners = new Set();
  let counter = 0;
  socket.addEventListener('message', ({ data }) => {
    const message = JSON.parse(data);
    if (message.id) {
      const request = pending.get(message.id);
      pending.delete(message.id);
      clearTimeout(request?.timer);
      if (message.error) request?.reject(new Error(`CDP ${message.error.code}`));
      else request?.resolve(message.result);
    } else {
      for (const listener of listeners) listener(message);
    }
  });
  await new Promise((resolve, reject) => {
    socket.addEventListener('open', resolve, { once: true });
    socket.addEventListener('error', reject, { once: true });
  });
  const command = (method, params = {}, sessionId) => new Promise((resolve, reject) => {
    const id = ++counter;
    const timer = setTimeout(() => {pending.delete(id);reject(new Error(`CDP timeout: ${method}`));}, 30000);
    pending.set(id, { resolve, reject, timer });
    socket.send(JSON.stringify({ id, method, params, ...(sessionId ? { sessionId } : {}) }));
  });
  const context = await command('Target.createBrowserContext');
  try {
    const target = await command('Target.createTarget', { url: 'about:blank',
      browserContextId: context.browserContextId });
    const attached = await command('Target.attachToTarget', { targetId: target.targetId, flatten: true });
    const sessionId = attached.sessionId;
    const send = (method, params) => command(method, params, sessionId);
    listeners.add((message) => {
      // The shared KDF preloader installs beforeunload protection even for the
      // unfunded fixture. This context owns no real wallet or ongoing work.
      if (message.sessionId === sessionId && message.method === 'Page.javascriptDialogOpening' &&
          message.params.type === 'beforeunload') {
        send('Page.handleJavaScriptDialog', { accept: true }).catch(() => {});
      }
    });
    const evaluate = async (expression) => {
      const result = await send('Runtime.evaluate', {
        expression, awaitPromise: true, returnByValue: true, userGesture: true,
      });
      assert.equal(result.exceptionDetails, undefined, 'Fixture JavaScript must complete');
      return result.result.value;
    };
    await send('Page.enable');
    await send('Runtime.enable');
    await send('Page.bringToFront');
    await send('Emulation.setFocusEmulationEnabled', { enabled: true });
    const ready = async () => {
      for (let attempt = 0; attempt < 200; attempt++) {
        try {
          if (await evaluate(`location.href.startsWith(${JSON.stringify(base)}) && document.readyState!=='loading' && window.gleecFixtureNavigating!==true`)) return;
        } catch (_) { /* Navigation may replace the execution context. */ }
        await new Promise(resolve => setTimeout(resolve, 100));
      }
      throw new Error('Fixture document timeout');
    };
    const navigation = await send('Page.navigate', { url: base });
    assert.equal(navigation.errorText, undefined, 'Local fixture navigation must succeed');
    await ready();
    trace('Document ready');
    await send('WebAuthn.enable');
    const virtual = await send('WebAuthn.addVirtualAuthenticator', { options: {
      protocol: 'ctap2', ctap2Version: 'ctap2_1', transport: 'internal',
      hasResidentKey: true, hasUserVerification: true, isUserVerified: true,
      hasPrf: true, hasHmacSecret: true, automaticPresenceSimulation: true,
    } });
    const loadBridge = () => compiledFixture ? evaluate(`(async()=>{
      for(let attempt=0;attempt<200;attempt++){
        if(typeof window.gleecCredentialSmoke==='function') return true;
        await new Promise(resolve=>setTimeout(resolve,100));
      }
      throw new Error('Compiled fixture startup timeout');
    })()`) : evaluate(`new Promise((resolve,reject) => {
      const script=document.createElement('script'); script.src='wallet_credentials.js';
      script.onload=()=>resolve(true); script.onerror=()=>reject(new Error('Bridge load failed'));
      document.head.appendChild(script);
    })`);
    await loadBridge();
    trace('Credential bridge ready');
    if (compiledFixture) {
      const adapter = await evaluate(`(async()=>({
        written:await gleecCredentialSmoke('write'),
        read:await gleecCredentialSmoke('read'),
        rejected:await gleecCredentialSmoke('authenticationRequired'),
        enrolled:await gleecCredentialSmoke('enroll'),
        protectedRead:await gleecCredentialSmoke('read'),
        deleted:await gleecCredentialSmoke('delete')
      }))()`);
      trace('Compiled adapter operations returned');
      assert.deepEqual(adapter, {written:'written',read:true,rejected:'unavailable',
        enrolled:'enrolled',protectedRead:true,deleted:'deleted'});
      const policy = await evaluate(`(async()=>{
        const blocked=[];
        const observe=event=>blocked.push(event.blockedURI);
        document.addEventListener('securitypolicyviolation',observe);
        const inline=document.createElement('script');
        inline.textContent='window.gleecCspCanary=true'; document.head.appendChild(inline);
        const external=document.createElement('script');
        external.src='https://invalid.example/gleec-csp-canary.js'; document.head.appendChild(external);
        for(let attempt=0;attempt<20 && blocked.length<2;attempt++)
          await new Promise(resolve=>setTimeout(resolve,50));
        document.removeEventListener('securitypolicyviolation',observe);
        inline.remove(); external.remove();
        return {inlineBlocked:!window.gleecCspCanary,blocked};
      })()`);
      assert.equal(policy.inlineBlocked,true);
      assert.ok(policy.blocked.includes('inline'));
      assert.ok(policy.blocked.some(uri=>uri.startsWith('https://invalid.example')));
      trace('CSP blocks unapproved scripts');
    }
    const setup = await evaluate(`(async () => {
      try {
        const api=gleecWalletCredentials;
        await api.write({key:'virtual-auth-fixture',value:'Test-only-no-wallet-42@'});
        const before=await api.metadata({key:'virtual-auth-fixture'});
        await api.enrollPasskey({key:'virtual-auth-fixture',value:'Test-only-no-wallet-42@',label:'Unfunded fixture'});
        const after=await api.metadata({key:'virtual-auth-fixture'});
        const matches=(await api.read({key:'virtual-auth-fixture',requireAuthentication:true}))==='Test-only-no-wallet-42@';
        const rows=await new Promise((resolve,reject)=>{
          const open=indexedDB.open('gleec-wallet-credentials-v1');
          open.onerror=()=>reject(new Error('Database unavailable'));
          open.onsuccess=()=>{const db=open.result;const tx=db.transaction('credentials');
            const request=tx.objectStore('credentials').getAll();
            request.onsuccess=()=>{const result=request.result;db.close();resolve(result);};};
        });
        return {before,after,matches,unattendedRows:rows.filter(row=>row.record.unattendedKey).length,
          stageRows:rows.filter(row=>row.slot.startsWith('staged:')).length};
      } catch(error) { return {error:error.code??'unexpected'}; }
    })()`);
    assert.equal(setup.error, undefined);
    assert.equal(setup.before.protection, 'browserLocal');
    assert.equal(setup.after.protection, 'passkeyPrf');
    assert.equal(setup.matches, true);
    assert.equal(setup.unattendedRows, 0);
    assert.equal(setup.stageRows, 0);
    trace('Durable passkey enrollment verified');
    await evaluate('window.gleecFixtureNavigating=true; true');
    await send('Page.reload', { ignoreCache: true });
    await ready();
    await loadBridge();
    trace('Reload ready');
    assert.equal(await evaluate(`(async () => {
      try { return (await gleecWalletCredentials.read({key:'virtual-auth-fixture',requireAuthentication:true}))==='Test-only-no-wallet-42@'; }
      catch(error) { return error.code??'unexpected'; }
    })()`), true, 'A fresh bridge must unlock the durable envelope after reload');
    await send('WebAuthn.setAutomaticPresenceSimulation', {
      authenticatorId: virtual.authenticatorId, enabled: false,
    });
    await evaluate(`window.pendingUnlock=gleecWalletCredentials.read({key:'virtual-auth-fixture'})
      .then(()=> 'unexpectedSuccess',error=>error.code); true`);
    await evaluate('gleecWalletCredentials.cancel(); true');
    assert.ok(['aborted', 'staleOperation'].includes(await evaluate('window.pendingUnlock')));
    await send('WebAuthn.setAutomaticPresenceSimulation', {
      authenticatorId: virtual.authenticatorId, enabled: true,
    });
    assert.equal(await evaluate(`(async () => {
      const authorization=await gleecWalletCredentials.prepareDelete({key:'virtual-auth-fixture'});
      await gleecWalletCredentials.delete({key:'virtual-auth-fixture',authorization});
      return await gleecWalletCredentials.metadata({key:'virtual-auth-fixture'});
    })()`), null);
    console.log('PASS: real IndexedDB, real WebAuthn PRF virtual authenticator, verified enrollment, reload unlock, cancellation, deletion');
  } finally {
    await command('Target.disposeBrowserContext', { browserContextId: context.browserContextId });
    socket.close();
  }
}

main().catch((error) => {
  console.error(error.name, error.message);
  process.exitCode = 1;
});
