// Compiled app lifecycle regression using only unfunded disposable wallets.
// Dispatch blur/focus while the document stays visible: Flutter web translates
// these into inactive/resumed, without a hidden/paused event in between.
'use strict';

const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const {createHash} = require('node:crypto');
const {LocalBrowser, delay} = require('./web_release_test_driver.js');
const {probe, credentialsSummary, buttonPresent, virtualAuthenticator, unlockApp} =
  require('./web_credential_release.browser.test.js');
const {publicIdentity} = require('./web_wallet_recovery.browser.test.js');
const {directoryDigest, toolsFingerprint} = require('./rollback_evidence.js');

const digest = filename => createHash('sha256').update(fs.readFileSync(filename)).digest('hex');
const hidden = "document.body.textContent.includes('Wallet content hidden')||Array.from(document.querySelectorAll('[aria-label]')).some(el=>el.getAttribute('aria-label')==='Wallet content hidden')";
const storedGrace = `(()=>{
  const key=Object.keys(localStorage).find(key=>key.endsWith('wallet_access_grace_seconds_v1'));
  let value=key?localStorage.getItem(key):null;
  for(let pass=0;pass<3&&typeof value==='string';pass++){try{value=JSON.parse(value);}catch(_){break;}}
  return value;
})()`;

async function main() {
  assert.ok(process.env.GLEEC_ROLLBACK_CANDIDATE, 'Specify the immutable candidate directory');
  const candidate = path.resolve(process.env.GLEEC_ROLLBACK_CANDIDATE);
  const manifest = JSON.parse(fs.readFileSync(path.join(candidate, 'manifest.json')));
  const builds = {normal: path.join(candidate, 'normal-web'), rollback: path.join(candidate, 'rollback-web')};
  const hashes = Object.fromEntries(Object.entries(builds).map(([name, directory]) =>
    [name, digest(path.join(directory, 'main.dart.js'))]));
  const evidence = {schema: 1, sourceSha256: manifest.sourceSha256, buildSha256: hashes,
    buildDirectorySha256: Object.fromEntries(Object.entries(builds).map(([name, directory]) => [name, directoryDigest(directory)])),
    validationTools: toolsFingerprint(path.basename(__filename)),
    scope: 'compiled-app-inactive-resumed-no-hidden', virtualProvider: true, rounds: []};
  const fixtureRoot = fs.mkdtempSync(path.join(os.tmpdir(), 'gleec-rollback-lifecycle-'));
  fs.mkdirSync(path.join(fixtureRoot, 'build'));
  fs.symlinkSync(builds.normal, path.join(fixtureRoot, 'build', 'web'));
  fs.copyFileSync(path.join(candidate, 'source', 'firebase.json'), path.join(fixtureRoot, 'firebase.json'));
  const browser = new LocalBrowser(fixtureRoot, {port: 18771, debugPort: 9226});
  try {
    await browser.serve(); await browser.launch();
    assert.equal(directoryDigest(path.join(browser.profile, 'compiled-fixture')), evidence.buildDirectorySha256.normal);
    evidence.browser = browser.version;
    const lifecycleProbe = `(() => {
      window.__lifecycleEvents=[];
      for(const name of ['blur','focus'])window.addEventListener(name,()=>__lifecycleEvents.push({name,at:performance.now(),visibility:document.visibilityState}));
      document.addEventListener('visibilitychange',()=>__lifecycleEvents.push({name:'visibilitychange',at:performance.now(),visibility:document.visibilityState}));
    })();`;
    const page = await browser.page({initialize: probe + lifecycleProbe});
    const virtual = await virtualAuthenticator(browser, page);
    await browser.navigate(page); await browser.semantics(page);
    console.log('CHECK: compiled lifecycle fixture loaded');
    await browser.click(page, 'Connect wallet');
    await browser.click(page, 'Create a new wallet');
    await browser.wait(page, buttonPresent('Gleec Wallet'), {timeout: 90000, label: 'disposable wallet creation'});
    console.log('CHECK: disposable lifecycle wallet created');
    await browser.click(page, 'Settings'); await browser.click(page, 'Security');
    await browser.wait(page, `(()=>{
      const action=Array.from(document.querySelectorAll('[role=button]')).find(el=>
        ['Create a passkey','Set up local passkey'].includes((el.getAttribute('aria-label')||el.textContent||'').trim())&&el.getAttribute('aria-disabled')!=='true');
      if(!action)return false;action.click();return true;
    })()`, {label:'current or retained passkey enrollment action'});
    await browser.wait(page, `(${credentialsSummary}).then(value=>value.protections[0]==='passkeyPrf'&&value.unattended===0)`,
      {label: 'PRF protection committed'});
    await browser.wait(page, `!(${buttonPresent('Create a passkey')})&&!(${buttonPresent('Set up local passkey')})`, {label: 'enrollment UI settled'});
    await delay(500);
    console.log('CHECK: lifecycle passkey enrollment settled');
    const identity = await page.evaluate(publicIdentity);
    const envelope = await page.evaluate(credentialsSummary);
    let privacyPixels;

    async function inactiveRound(profile, graceSeconds, awayMilliseconds, expectsChallenge) {
      await browser.wait(page, buttonPresent('Gleec Wallet'), {label: 'foreground wallet before interruption'});
      await page.evaluate('new Promise(resolve=>requestAnimationFrame(()=>requestAnimationFrame(resolve)))');
      await delay(250);
      await page.send('WebAuthn.setAutomaticPresenceSimulation', {authenticatorId: virtual.authenticatorId, enabled: false});
      const before = await page.evaluate('__gleecReleaseProbe.metrics().challenges');
      const start = await page.evaluate("__lifecycleEvents=[];window.dispatchEvent(new Event('blur'));performance.now()");
      await browser.wait(page, `!(${buttonPresent('Gleec Wallet')})`, {timeout: 2000, label: 'wallet semantics excluded on inactivity'});
      await page.evaluate('new Promise(resolve=>requestAnimationFrame(()=>requestAnimationFrame(resolve)))');
      // Only capture an already-covered disposable app. PNG bytes remain in
      // process memory; evidence records Booleans, never images. Flutter web can
      // omit a reused cover's accessibility label, so also require pixel equality
      // with the first cover positively identified by that localized label.
      if (!privacyPixels) await browser.wait(page, hidden, {timeout: 2000, label: 'first privacy cover identified'});
      const privacyLabelAvailable = await page.evaluate(hidden);
      const shot = await page.send('Page.captureScreenshot', {format: 'png'});
      const pixels = createHash('sha256').update(shot.data).digest('hex');
      if (!privacyPixels) privacyPixels = pixels;
      assert.equal(pixels, privacyPixels, 'Each inactive view must match the identified opaque privacy cover');
      const privacyCoverObservedMs = Math.round(await page.evaluate('performance.now()') - start);
      assert.equal(await page.evaluate(buttonPresent('Gleec Wallet')), false);
      const remaining = awayMilliseconds - (await page.evaluate('performance.now()') - start);
      if (remaining > 0) await delay(remaining);
      const elapsedMs = await page.evaluate(`(()=>{const elapsed=performance.now()-${start};window.dispatchEvent(new Event('focus'));return elapsed;})()`);
      if (awayMilliseconds < 30000) assert.ok(elapsedMs < 30000, 'Short return must remain inside the grace window');
      if (expectsChallenge) {
        await browser.wait(page, `__gleecReleaseProbe.metrics().challenges===${before + 1}`, {label: 'one automatic return challenge'});
        assert.equal(await page.evaluate(buttonPresent('Gleec Wallet')), false);
        await page.evaluate('gleecWalletCredentials.cancel();true');
        await browser.wait(page, `${buttonPresent('Unlock')}||${buttonPresent('Unlock with passkey')}`, {label: 'stable explicit unlock after cancellation'});
        await delay(500);
        assert.equal(await page.evaluate('__gleecReleaseProbe.metrics().challenges'), before + 1, 'Cancellation must not loop');
        await page.send('WebAuthn.setAutomaticPresenceSimulation', {authenticatorId: virtual.authenticatorId, enabled: true});
        await unlockApp(browser, page);
      } else {
        await browser.wait(page, buttonPresent('Gleec Wallet'), {label: 'existing session restored inside grace'});
        assert.equal(await page.evaluate('__gleecReleaseProbe.metrics().challenges'), before);
        await page.send('WebAuthn.setAutomaticPresenceSimulation', {authenticatorId: virtual.authenticatorId, enabled: true});
      }
      const events = await page.evaluate('__lifecycleEvents');
      assert.deepEqual(events.map(event => event.name), ['blur', 'focus']);
      assert.ok(events.every(event => event.visibility === 'visible'));
      assert.deepEqual(await page.evaluate(publicIdentity), identity);
      assert.deepEqual(await page.evaluate(credentialsSummary), envelope);
      assert.equal(await page.evaluate('__gleecReleaseProbe.metrics().cspViolations'), 0);
      evidence.rounds.push({profile, graceSeconds, requestedAwayMs: awayMilliseconds,
        elapsedMs: Math.round(elapsedMs), hiddenImmediately: true, events: events.map(event => event.name),
        privacyCoverObservedMs, privacyLabelAvailable, privacyPixelsMatched: true,
        remainedVisible: true, automaticChallenges: expectsChallenge ? 1 : 0,
        cancellationStable: expectsChallenge, identityPreserved: true, credentialEnvelopePreserved: true});
      console.log(`PASS: ${profile}, grace ${graceSeconds}s, inactive-only ${Math.round(elapsedMs)}ms, ${expectsChallenge ? 'locked with one challenge' : 'session restored'}`);
    }

    async function setGrace(label) {
      await browser.click(page, 'Settings'); await browser.click(page, 'Security');
      await browser.click(page, label);
      await browser.wait(page, buttonPresent('Continue'), {label: 'fresh authorization for lock preference'});
      await browser.click(page, 'Continue');
      await browser.wait(page, `(${storedGrace})===${label === 'Immediately' ? 0 : 30}`, {label: 'lock preference persisted'});
      await browser.wait(page, `!(${buttonPresent('Continue')})`, {label: 'lock preference authorization completed'});
      await delay(500);
    }

    async function replaceBuild(profile) {
      await browser.navigate(page, 'about:blank');
      const owned = path.join(browser.profile, 'compiled-fixture');
      fs.rmSync(owned, {recursive: true, force: true});
      fs.cpSync(builds[profile], owned, {recursive: true, dereference: true});
      assert.equal(digest(path.join(owned, 'main.dart.js')), hashes[profile]);
      assert.equal(directoryDigest(owned), evidence.buildDirectorySha256[profile]);
      await browser.navigate(page); await browser.semantics(page);
      await unlockApp(browser, page);
      assert.deepEqual(await page.evaluate(publicIdentity), identity);
      assert.deepEqual(await page.evaluate(credentialsSummary), envelope);
    }

    if (process.argv.includes('--privacy-diagnostic')) {
      await inactiveRound('normal', 30, 1000, false);
      await inactiveRound('normal', 30, 1000, false);
      return;
    }
    await inactiveRound('normal', 30, 29000, false);
    await inactiveRound('normal', 30, 31000, true);
    await setGrace('Immediately');
    await inactiveRound('normal', 0, 1000, true);
    await setGrace('After 30 seconds');
    assert.equal(await page.evaluate(storedGrace), 30);
    await replaceBuild('rollback');
    assert.equal(await page.evaluate(storedGrace), 30);
    await inactiveRound('rollback', 0, 1000, true);
    await replaceBuild('normal');
    assert.equal(await page.evaluate(storedGrace), 30);
    await inactiveRound('normal-after-rollback', 30, 1000, false);
    evidence.storedGracePreserved = true;
    for (const [name, directory] of Object.entries(builds)) assert.equal(directoryDigest(directory), evidence.buildDirectorySha256[name]);
    assert.deepEqual(toolsFingerprint(path.basename(__filename)), evidence.validationTools);
    if (process.env.GLEEC_ROLLBACK_LIFECYCLE_REPORT) {
      fs.writeFileSync(process.env.GLEEC_ROLLBACK_LIFECYCLE_REPORT, JSON.stringify(evidence, null, 2) + '\n');
    }
    console.log('EVIDENCE', JSON.stringify(evidence));
  } finally {
    await browser.cleanup();
    fs.rmSync(fixtureRoot, {recursive: true, force: true});
  }
}

if (require.main === module) main().catch(error => {
  console.error(error.name, error.message); process.exitCode = 1;
});
