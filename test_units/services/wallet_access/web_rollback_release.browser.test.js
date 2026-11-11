// Full app normal -> enrollment-disabled rollback -> normal, using one actual
// browser profile/origin and virtual PRF provider. Only unfunded test wallets.
'use strict';

const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const {createHash} = require('node:crypto');
const {LocalBrowser} = require('./web_release_test_driver.js');
const {probe, credentialsSummary: credentialsMetadataSummary, buttonPresent, virtualAuthenticator, unlockApp} =
  require('./web_credential_release.browser.test.js');
const {publicIdentity, recoverySummary} = require('./web_wallet_recovery.browser.test.js');
const {directoryDigest, toolsFingerprint} = require('./rollback_evidence.js');

const digest = filename => createHash('sha256').update(fs.readFileSync(filename)).digest('hex');
const customPassword = 'Synthetic-browser-pass-456!';
// Bind ciphertext/IV/AAD metadata as well as identity and revision. CryptoKeys
// remain nonextractable; real unlock verifies that their retained handles work.
// Only the digest leaves page memory, never ciphertext or key/provider material.
const credentialsSummary = `(async()=>{
  const metadata=await ${credentialsMetadataSummary};
  const rows=await new Promise((resolve,reject)=>{
    const open=indexedDB.open('gleec-wallet-credentials-v1');
    open.onerror=()=>reject(new Error('Database unavailable'));
    open.onsuccess=()=>{const db=open.result;const request=db.transaction('credentials').objectStore('credentials').getAll();
      request.onsuccess=()=>{resolve(request.result);db.close();};};
  });
  const canonical=value=>{
    if(value instanceof ArrayBuffer)return Array.from(new Uint8Array(value));
    if(ArrayBuffer.isView(value))return Array.from(new Uint8Array(value.buffer,value.byteOffset,value.byteLength));
    if(value instanceof CryptoKey)return {type:value.type,extractable:value.extractable,algorithm:canonical(value.algorithm),usages:Array.from(value.usages)};
    if(Array.isArray(value))return value.map(canonical);
    if(value&&typeof value==='object')return Object.fromEntries(Object.keys(value).sort().map(key=>[key,canonical(value[key])]));
    return value;
  };
  const bytes=new TextEncoder().encode(JSON.stringify(canonical(rows.sort((a,b)=>a.slot.localeCompare(b.slot)))));
  const digest=await crypto.subtle.digest('SHA-256',bytes);
  return {...metadata,envelopeFingerprint:Array.from(new Uint8Array(digest),byte=>byte.toString(16).padStart(2,'0')).join('')};
})()`;

async function main() {
  const candidate = path.resolve(process.env.GLEEC_ROLLBACK_CANDIDATE || '');
  assert.ok(process.env.GLEEC_ROLLBACK_CANDIDATE, 'Specify the immutable candidate directory');
  const manifest = JSON.parse(fs.readFileSync(path.join(candidate, 'manifest.json')));
  assert.equal(manifest.rollbackDefines.WALLET_DEVICE_ENROLLMENT_ENABLED, 'false');
  assert.equal(manifest.rollbackDefines.WALLET_PASSKEY_ENROLLMENT_ENABLED, 'false');
  assert.equal(manifest.rollbackDefines.WALLET_IMMEDIATE_LOCK_REQUIRED, 'true');
  const builds = {normal: path.join(candidate, 'normal-web'), rollback: path.join(candidate, 'rollback-web')};
  const hashes = Object.fromEntries(Object.entries(builds).map(([key, value]) =>
    [key, digest(path.join(value, 'main.dart.js'))]));
  assert.notEqual(hashes.normal, hashes.rollback, 'The reader build must be independently compiled');
  const evidence = {schema: 1, sourceSha256: manifest.sourceSha256, buildSha256: hashes,
    buildDirectorySha256: Object.fromEntries(Object.entries(builds).map(([name, directory]) => [name, directoryDigest(directory)])),
    validationTools: toolsFingerprint(path.basename(__filename)),
    scope: 'full-app-same-browser-origin-profile', virtualProvider: true, rounds: []};

  async function exercise(custom) {
    const fixtureRoot = fs.mkdtempSync(path.join(os.tmpdir(), 'gleec-rollback-web-root-'));
    fs.mkdirSync(path.join(fixtureRoot, 'build'));
    fs.symlinkSync(builds.normal, path.join(fixtureRoot, 'build', 'web'));
    fs.copyFileSync(path.join(candidate, 'source', 'firebase.json'), path.join(fixtureRoot, 'firebase.json'));
    const browser = new LocalBrowser(fixtureRoot, {port: 18770, debugPort: 9225});
    try {
      await browser.serve(); await browser.launch();
      assert.equal(directoryDigest(path.join(browser.profile, 'compiled-fixture')), evidence.buildDirectorySha256.normal);
      evidence.browser = browser.version;
      const page = await browser.page({initialize: probe});
      const virtual = await virtualAuthenticator(browser, page);
      await browser.navigate(page); await browser.semantics(page);
      await browser.click(page, 'Connect wallet');
      await browser.click(page, 'Create a new wallet');
      await browser.wait(page, buttonPresent('Gleec Wallet'), {timeout: 90000, label: 'disposable wallet created'});
      const identity = await page.evaluate(publicIdentity);
      const recovery = await page.evaluate(recoverySummary);
      const local = await page.evaluate(credentialsSummary);
      assert.equal(local.unattended, 1);

      async function replaceBuild(profile) {
        await browser.navigate(page, 'about:blank');
        const owned = path.join(browser.profile, 'compiled-fixture');
        // Only this harness-owned server root is replaced. Browser profile,
        // IndexedDB (including nonextractable keys), origin and provider remain.
        fs.rmSync(owned, {recursive: true, force: true});
        fs.cpSync(builds[profile], owned, {recursive: true, dereference: true});
        assert.equal(digest(path.join(owned, 'main.dart.js')), hashes[profile]);
        assert.equal(directoryDigest(owned), evidence.buildDirectorySha256[profile]);
        await browser.navigate(page); await browser.semantics(page);
      }

      async function passwordUnlock() {
        await browser.wait(page, `${buttonPresent('Unlock')}||${buttonPresent('Use password')}||!!document.querySelector('input[type=password]')`,
          {timeout: 60000, label: 'password return entry'});
        if (await page.evaluate(buttonPresent('Unlock'))) await browser.click(page, 'Unlock');
        if (await page.evaluate(buttonPresent('Use password'))) await browser.click(page, 'Use password');
        await browser.fill(page, 'Wallet password', customPassword);
        await browser.click(page, 'Log In');
        await browser.wait(page, buttonPresent('Gleec Wallet'), {timeout: 60000, label: 'custom password return'});
      }

      async function round(kind, expectedCredentials) {
        for (const profile of ['rollback', 'normal']) {
          const challenges = virtual.counts.asserted;
          await replaceBuild(profile);
          if (kind === 'custom-password') await passwordUnlock();
          else if (kind === 'passkey') await unlockApp(browser, page);
          else await browser.wait(page, buttonPresent('Gleec Wallet'), {timeout: 60000, label: 'unattended return'});
          assert.deepEqual(await page.evaluate(publicIdentity), identity);
          assert.deepEqual(await page.evaluate(recoverySummary), recovery);
          assert.deepEqual(await page.evaluate(credentialsSummary), expectedCredentials);
          const metrics = await page.evaluate('__gleecReleaseProbe.metrics()');
          assert.ok(metrics.challenges <= 1, 'Return must not repeat a passkey challenge');
          assert.equal(metrics.cspViolations, 0);
          if (kind === 'passkey') assert.ok(virtual.counts.asserted > challenges);
          await browser.click(page, 'Settings'); await browser.click(page, 'Security');
          if (profile === 'rollback') {
            assert.equal(await page.evaluate(buttonPresent('Create a passkey')), false);
            assert.equal(await page.evaluate(buttonPresent('Set up local passkey')), false);
            assert.equal(await page.evaluate(buttonPresent('Replace passkey using password')), false);
          }
          evidence.rounds.push({kind, profile, identityPreserved: true, recoveryPreserved: true,
            credentialEnvelopePreserved: true, challenges: metrics.challenges,
            newEnrollmentDisabled: profile === 'rollback'});
          console.log(`PASS: ${kind}: ${profile} preserves the actual wallet and credential envelope`);
        }
      }

      if (custom) {
        await browser.click(page, 'Settings'); await browser.click(page, 'Security');
        await browser.click(page, 'Change your password');
        await browser.fill(page, 'Enter new password', customPassword);
        await browser.fill(page, 'Confirm new password', customPassword);
        await page.evaluate('new Promise(resolve=>requestAnimationFrame(()=>requestAnimationFrame(resolve)))');
        await browser.click(page, 'Update password');
        try {
          await browser.wait(page, `(${credentialsSummary}).then(value=>value.active===0)`,
            {timeout: 60000, label: 'unattended credential removed after password replacement'});
        } catch (error) {
          const diagnostics = await page.evaluate(`JSON.stringify({
            controls:Array.from(document.querySelectorAll('[role=button]')).map(el=>el.getAttribute('aria-label')||'').filter(Boolean),
            fields:Array.from(document.querySelectorAll('input')).map(el=>({label:el.getAttribute('aria-label'),length:el.value.length})),
            knownErrors:['Password not accepted','Incorrect password','Password has changed','Please wait','Passwords do not match'].filter(text=>document.body.textContent.includes(text))
          })`);
          console.log('Password replacement control state (no field values)', diagnostics);
          throw error;
        }
        const protectedByPassword = await page.evaluate(credentialsSummary);
        await round('custom-password', protectedByPassword);
      } else {
        await round('browserLocal', local);
        await browser.wait(page, `(()=>{
          const action=Array.from(document.querySelectorAll('[role=button]')).find(el=>
            ['Create a passkey','Set up local passkey'].includes((el.getAttribute('aria-label')||el.textContent||'').trim())&&el.getAttribute('aria-disabled')!=='true');
          if(!action)return false;action.click();return true;
        })()`, {label:'current or retained passkey enrollment action'});
        await browser.wait(page, `(${credentialsSummary}).then(value=>value.protections[0]==='passkeyPrf'&&value.unattended===0)`,
          {label: 'verified PRF protection'});
        const protectedByPasskey = await page.evaluate(credentialsSummary);
        assert.equal(protectedByPasskey.staged, 0);
        await round('passkey', protectedByPasskey);
        await browser.click(page, 'Settings'); await browser.click(page, 'Log out');
        await browser.wait(page, "!!document.querySelector('[role=dialog]')", {label: 'explicit sign-out confirmation'});
        await browser.click(page, 'Log out');
        for (const profile of ['rollback', 'normal']) {
          const before = virtual.counts.asserted;
          await replaceBuild(profile);
          await browser.wait(page, buttonPresent('Connect wallet'), {label: 'persisted explicit sign-out'});
          assert.equal(virtual.counts.asserted, before);
          assert.deepEqual(await page.evaluate(publicIdentity), identity);
          assert.deepEqual(await page.evaluate(credentialsSummary), protectedByPasskey);
        }
        evidence.explicitSignOutPreserved = true;
      }
    } finally {
      await browser.cleanup();
      fs.rmSync(fixtureRoot, {recursive: true, force: true});
    }
  }

  if (!process.argv.includes('--custom-only')) await exercise(false);
  await exercise(true);
  for (const [name, directory] of Object.entries(builds)) assert.equal(directoryDigest(directory), evidence.buildDirectorySha256[name]);
  assert.deepEqual(toolsFingerprint(path.basename(__filename)), evidence.validationTools);
  if (process.env.GLEEC_ROLLBACK_REPORT) {
    fs.writeFileSync(process.env.GLEEC_ROLLBACK_REPORT, JSON.stringify(evidence, null, 2) + '\n');
  }
  console.log('EVIDENCE', JSON.stringify(evidence));
}

if (require.main === module) main().catch(error => {
  console.error(error.name, error.message); process.exitCode = 1;
});
