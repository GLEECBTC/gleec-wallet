'use strict';

const assert = require('node:assert/strict');
const path = require('node:path');
const {LocalBrowser} = require('./web_release_test_driver.js');
const {
  buttonPresent, credentialsSummary, probe, unlockApp, virtualAuthenticator,
  waitForPasskeySettingsReady,
} = require('./web_credential_release.browser.test.js');
const {publicIdentity} = require('./web_wallet_recovery.browser.test.js');

const observeRecovery = "(() => {" +
  "window.__gleecSawLostUnlock=false;" +
  "const observer=new MutationObserver(()=>{" +
    "if(" + buttonPresent('Use saved password') + ")window.__gleecSawLostUnlock=true;" +
  "});observer.observe(document,{subtree:true,childList:true,attributes:true,attributeFilter:['aria-label']});" +
"})();";

async function checkInterruptedEnrollment(browser, page, authenticator, original) {
  const assertions = authenticator.counts.asserted;
  await page.evaluate(`(() => {
    const credentials = navigator.credentials;
    const create = credentials.create;
    const handoff = new Promise(resolve => { window.__finishProviderHandoff = resolve; });
    credentials.create = async options => {
      try {
        const answer = await create.call(credentials, options);
        window.__providerHasPrf = answer.getClientExtensionResults().prf?.enabled === true;
        await handoff;
        return answer;
      } finally {
        credentials.create = create;
      }
    };
    window.__interruptedEnrollment = gleecWalletCredentials.enrollPasskey({
      key: 'interrupted-enrollment-fixture', value: 'Unfunded-fixture-only',
      label: 'Interrupted enrollment fixture',
    }).then(() => 'unexpectedSuccess', error => error.code);
    return true;
  })()`);
  await browser.wait(page, 'window.__providerHasPrf === true',
    {label: 'provider returned a registration with PRF'});
  await browser.visibility(page, 'hidden');
  await browser.visibility(page, 'visible');
  await page.evaluate('window.__finishProviderHandoff(); true');
  assert.equal(await page.evaluate('window.__interruptedEnrollment'), 'staleOperation');
  assert.equal(authenticator.counts.asserted, assertions, 'A stale enrollment must not verify');
  assert.deepEqual(await page.evaluate(credentialsSummary), original);
}

async function main() {
  const legacyBuild = process.argv[2];
  assert.ok(legacyBuild, 'Pass the compiled pre-#3641 build/web directory');
  const browser = new LocalBrowser(path.resolve(__dirname, '../../..'), {port: 0});
  try {
    const upgrade = await browser.serve({previousBuild: path.resolve(legacyBuild)});
    await browser.launch();
    const page = await browser.page({initialize: probe + '\n' + observeRecovery});
    await page.send('Network.setCacheDisabled', {cacheDisabled: true});
    await page.send('Network.setBypassServiceWorker', {bypass: true});
    const authenticator = await virtualAuthenticator(browser, page);

    await browser.navigate(page);
    await browser.semantics(page, 'javascript');
    await browser.wait(page,
      "performance.getEntriesByType('resource').some(entry=>entry.name.endsWith('/services/wallet_credentials.js'))",
      {label: 'pre-#3641 vault loaded'});
    await browser.click(page, 'Create a new wallet');
    await browser.wait(page, buttonPresent('Gleec Wallet'),
      {timeout: 60000, label: 'legacy disposable wallet opened'});
    const identity = await page.evaluate(publicIdentity);

    await browser.click(page, 'Settings');
    await browser.click(page, 'Security');
    await browser.click(page, 'Create a passkey', {pointer: true});
    await waitForPasskeySettingsReady(browser, page);
    const original = await page.evaluate(credentialsSummary);
    assert.deepEqual(original.protections, ['passkeyPrf']);
    assert.equal(original.active, 1);
    assert.equal(original.staged, 0);
    assert.equal(original.unattended, 0);
    assert.equal(authenticator.counts.created, 1);

    upgrade();
    for (let opening = 0; opening < 2; opening++) {
      const assertionsBefore = authenticator.counts.asserted;
      await browser.navigate(page);
      await browser.semantics(page);
      assert.equal(await page.evaluate(
        "performance.getEntriesByType('resource').some(entry=>entry.name.endsWith('/services/wallet_credentials.js'))"),
      false, 'The replacement build must use the Dart vault');
      await unlockApp(browser, page);
      assert.equal(authenticator.counts.asserted, assertionsBefore + 1);
      assert.equal(authenticator.counts.created, 1, 'Migration must keep the original passkey');
      assert.equal(await page.evaluate('__gleecReleaseProbe.metrics().passwordRequests'), 0,
        'Passkey unlock must not ask Chrome to fill a saved password');
      assert.deepEqual(await page.evaluate(credentialsSummary), original);
      assert.deepEqual(await page.evaluate(publicIdentity), identity);
      assert.equal(await page.evaluate('window.__gleecSawLostUnlock'), false,
        'The healthy legacy record must not flash the lost-unlock recovery button');
    }
    console.log("PASS: the original passkey opened the same wallet twice on the " +
      browser.webCompiler + " release after replacing the legacy vault");
    await checkInterruptedEnrollment(browser, page, authenticator, original);
    console.log('PASS: a PRF registration returned after a hidden-page handoff preserves the vault');
  } finally {
    await browser.cleanup();
  }
}

if (require.main === module) {
  main().catch(error => {
    console.error(error.name, error.message);
    process.exitCode = 1;
  });
}
