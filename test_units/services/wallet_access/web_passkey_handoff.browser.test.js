// Uses only a temporary profile, virtual authenticator and an unfunded vault fixture.
'use strict';

const assert = require('node:assert/strict');
const path = require('node:path');
const {LocalBrowser} = require('./web_release_test_driver.js');
const {
  credentialsSummary, virtualAuthenticator,
} = require('./web_credential_release.browser.test.js');

const provider = `(() => {
  const credentials = navigator.credentials;
  const key = 'provider-handoff-fixture';
  const value = 'Unfunded-passkey-handoff-fixture';
  const pending = new Map();
  for (const method of ['create', 'get']) {
    const request = credentials[method].bind(credentials);
    credentials[method] = async options => {
      const answer = await request(options);
      if (!options?.publicKey || answer?.type !== 'public-key') return answer;
      const prf = answer.getClientExtensionResults().prf;
      if (!prf || (method === 'create' ? prf.enabled !== true : !prf.results?.first))
        throw new Error('Missing fixture PRF response');
      await new Promise(resolve => pending.set(method, resolve));
      pending.delete(method);
      return answer;
    };
  }
  let outcome;
  const track = action => {
    outcome = 'pending';
    window.fixtureOutcome = action.then(
      success => outcome = success,
      error => outcome = error.code,
    );
    return true;
  };
  window.handoff = {
    write: () => gleecWalletCredentials.write({key, value}),
    enroll: (target = key) => track(
      gleecWalletCredentials.enrollPasskey({key: target, value, label: 'Provider handoff fixture'})
        .then(() => 'enrolled'),
    ),
    read: (trigger) => track(
      gleecWalletCredentials.read({key, trigger, purpose: 'unlock', requireAuthentication: true})
        .then(secret => secret === value ? 'opened' : 'wrong credential'),
    ),
    pending: method => pending.has(method),
    release: method => { pending.get(method)(); return true; },
    outcome: () => outcome,
  };
  return true;
})()`;

async function deliverWhileHidden(browser, page, method) {
  await browser.wait(page, `handoff.pending(${JSON.stringify(method)})`,
    {label: 'valid PRF response held by the provider'});
  await browser.visibility(page, 'hidden');
  await page.evaluate(`handoff.release(${JSON.stringify(method)})`);
  // Allow the response to reach the vault before asserting that it waited.
  await page.evaluate('new Promise(resolve => requestAnimationFrame(() => resolve(true)))');
}

async function main() {
  const browser = new LocalBrowser(path.resolve(__dirname, '../../..'), {port: 0});
  try {
    await browser.serve();
    await browser.launch();
    const page = await browser.page();
    const authenticator = await virtualAuthenticator(browser, page);
    await browser.navigate(page);
    await browser.semantics(page);
    await browser.wait(page, 'typeof gleecWalletCredentials?.enrollPasskey === "function"',
      {label: 'compiled app vault'});
    await page.evaluate(provider);
    await page.evaluate('handoff.write().then(() => true)');
    const initial = await page.evaluate(credentialsSummary);
    assert.deepEqual(initial.protections, ['browserLocal']);

    await page.evaluate('handoff.enroll()');
    await deliverWhileHidden(browser, page, 'create');
    assert.equal(await page.evaluate('handoff.outcome()'), 'pending');
    assert.equal(authenticator.counts.asserted, 0, 'Registration cannot start verification while hidden');
    assert.deepEqual(await page.evaluate(credentialsSummary), initial);
    await browser.visibility(page, 'visible');

    await deliverWhileHidden(browser, page, 'get');
    assert.equal(await page.evaluate('handoff.outcome()'), 'pending');
    assert.deepEqual(await page.evaluate(credentialsSummary), initial,
      'Even a valid verification response cannot commit while hidden');
    await browser.visibility(page, 'visible');
    assert.equal(await page.evaluate('window.fixtureOutcome'), 'enrolled');
    assert.equal(authenticator.counts.created, 1);
    assert.equal(authenticator.counts.asserted, 1);
    const protectedRecord = await page.evaluate(credentialsSummary);
    assert.deepEqual(protectedRecord.protections, ['passkeyPrf']);
    assert.equal(protectedRecord.staged, 0);

    await page.evaluate("handoff.read('explicit')");
    await deliverWhileHidden(browser, page, 'get');
    assert.equal(await page.evaluate('handoff.outcome()'), 'pending');
    await browser.visibility(page, 'visible');
    assert.equal(await page.evaluate('window.fixtureOutcome'), 'opened');

    await page.evaluate("handoff.read('automatic')");
    await deliverWhileHidden(browser, page, 'get');
    await browser.visibility(page, 'visible');
    assert.equal(await page.evaluate('window.fixtureOutcome'), 'staleOperation');
    assert.deepEqual(await page.evaluate(credentialsSummary), protectedRecord);
    console.log('PASS: explicit WebAuthn prompts finish on return and automatic prompts stay canceled');

    await page.evaluate("handoff.enroll('navigated-fixture')");
    await browser.wait(page, "handoff.pending('create')", {label: 'pending enrollment before navigation'});
    await page.evaluate("window.dispatchEvent(new Event('pagehide')); handoff.release('create')");
    assert.equal(await page.evaluate('window.fixtureOutcome'), 'staleOperation');
    assert.deepEqual(await page.evaluate(credentialsSummary), protectedRecord);

    await page.evaluate("handoff.enroll('expired-fixture')");
    await deliverWhileHidden(browser, page, 'create');
    await browser.wait(page, "handoff.outcome() === 'notCompleted'", {label: 'expired provider return'});
    await browser.visibility(page, 'visible');
    assert.deepEqual(await page.evaluate(credentialsSummary), protectedRecord);
    assert.equal(authenticator.counts.asserted, 3,
      'Canceled enrollments never request verification');
    console.log('PASS: navigation and expired provider returns preserve the active record');
  } finally {
    await browser.cleanup();
  }
}

main().catch(error => {
  console.error(error.name, error.message);
  process.exitCode = 1;
});
