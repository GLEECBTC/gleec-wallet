// End-to-end explicit provider-loss recovery. Unfunded disposable profile only.
'use strict';
const assert=require('node:assert/strict');
const path=require('node:path');
const {LocalBrowser,delay}=require('./web_release_test_driver.js');
const {probe,credentialsSummary,buttonPresent,virtualAuthenticator,unlockApp}=require('./web_credential_release.browser.test.js');

async function main(){
  const browser=new LocalBrowser(path.resolve(__dirname,'../../..'));
  let credential;
  try{
    await browser.serve();await browser.launch();
    const page=await browser.page({initialize:probe});await browser.navigate(page);await browser.semantics(page);
    assert.equal(await page.evaluate("typeof gleecWalletCredentials.replacePasskeyAfterPasswordVerification"),'function',
      'Rebuild the app with explicit recovery APIs before this check');
    await browser.click(page,'Connect wallet');await browser.click(page,'Create a new wallet');
    await browser.wait(page,buttonPresent('Gleec Wallet'),{timeout:60000,label:'unfunded replacement fixture'});
    credential=await page.evaluate('__gleecReleaseProbe.testCredential()');
    const oldProvider=await virtualAuthenticator(browser,page);
    await browser.click(page,'Settings');await browser.click(page,'Security');await browser.click(page,'Set up local passkey');
    await browser.wait(page,buttonPresent('Replace passkey using password'),{label:'protected recovery action'});
    const before=await page.evaluate(credentialsSummary);
    console.log('CHECK: original passkey enrolled; removing only the virtual fixture provider');
    await page.send('WebAuthn.removeVirtualAuthenticator',{authenticatorId:oldProvider.authenticatorId});
    const replacement=await virtualAuthenticator(browser,page);

    await browser.click(page,'Replace passkey using password');
    console.log('CHECK: explicit password recovery dialog opened');
    await browser.fill(page,'Enter your password','Wrong-unfunded-fixture-password!');await browser.click(page,'Continue');
    await browser.wait(page,"document.body.textContent.includes('Password not accepted')",{label:'wrong-password rejection'});
    assert.equal(replacement.counts.created,0);assert.equal(replacement.counts.asserted,0);
    assert.deepEqual(await page.evaluate(credentialsSummary),before);
    await browser.click(page,'Cancel');
    console.log('PASS: wrong password cannot initiate replacement or release protected credentials');

    await page.send('WebAuthn.setAutomaticPresenceSimulation',{authenticatorId:replacement.authenticatorId,enabled:false});
    await browser.click(page,'Replace passkey using password');
    await browser.fill(page,'Enter your password',credential);await browser.click(page,'Continue');
    const registrations=await browser.wait(page,'__gleecReleaseProbe.metrics().registrations>=2',{label:'explicit replacement ceremony'});
    assert.ok(registrations);await page.evaluate('gleecWalletCredentials.cancel();true');
    await browser.wait(page,"Array.from(document.querySelectorAll('[role=button]')).some(el=>(el.getAttribute('aria-label')||el.textContent||'').trim()==='Replace passkey using password'&&el.getAttribute('aria-disabled')!=='true')",{label:'usable replacement action after cancellation'});
    assert.deepEqual(await page.evaluate(credentialsSummary),before);
    await delay(200);
    assert.equal(await page.evaluate('__gleecReleaseProbe.metrics().registrations'),2,'Cancellation must not initiate another ceremony');
    await page.send('WebAuthn.setAutomaticPresenceSimulation',{authenticatorId:replacement.authenticatorId,enabled:true});

    await browser.click(page,'Replace passkey using password');
    await browser.fill(page,'Enter your password',credential);await browser.click(page,'Continue');
    await browser.wait(page,`(${credentialsSummary}).then(value=>value.fingerprint!==${JSON.stringify(before.fingerprint)})`,{label:'verified replacement persisted'});
    const after=await page.evaluate(credentialsSummary);
    assert.equal(after.active,1);assert.equal(after.unattended,0);assert.equal(after.staged,0);
    assert.equal(replacement.counts.asserted,1);
    assert.equal(await page.evaluate('__gleecReleaseProbe.metrics().registrations'),3);
    console.log('PASS: explicit password recovery replaces a missing provider only after a new usable PRF; cancellation preserved prior access');

    const assertions=replacement.counts.asserted;
    await browser.navigate(page);await browser.semantics(page);
    await browser.wait(page,buttonPresent('Gleec Wallet'),{timeout:60000,label:'replacement cold return'});
    assert.equal(replacement.counts.asserted,assertions+1);
    assert.deepEqual(await page.evaluate(credentialsSummary),after);
    console.log('PASS: replaced local passkey reopens the same wallet with one automatic assertion');

    await page.send('WebAuthn.setAutomaticPresenceSimulation',{authenticatorId:replacement.authenticatorId,enabled:false});
    await browser.navigate(page);await browser.semantics(page);
    await browser.wait(page,'__gleecReleaseProbe.metrics().challenges===1',{label:'single automatic returning challenge'});
    await page.evaluate('gleecWalletCredentials.cancel();true');
    await browser.wait(page,`${buttonPresent('Unlock')}||${buttonPresent('Unlock with passkey')}`,
      {label:'usable returning-unlock fallback after cancellation'});
    await delay(350);
    assert.equal(await page.evaluate('__gleecReleaseProbe.metrics().challenges'),1,
      'Canceling automatic return must not loop or prompt again');
    assert.deepEqual(await page.evaluate(credentialsSummary),after);
    await page.send('WebAuthn.setAutomaticPresenceSimulation',{authenticatorId:replacement.authenticatorId,enabled:true});
    await unlockApp(browser,page);
    assert.equal(await page.evaluate('__gleecReleaseProbe.metrics().challenges'),2,
      'Only an explicit retry may start the second challenge');
    console.log('PASS: canceled automatic return stays stable and explicit retry reopens the same wallet');

    // Reach the existing deletion review from the active wallet's settings so
    // fresh password proof can precede the engine shutdown/deletion sequence.
    await page.send('WebAuthn.removeVirtualAuthenticator',{authenticatorId:replacement.authenticatorId});
    await browser.click(page,'Settings');await browser.click(page,'Security');
    await browser.click(page,'Review wallet removal');
    await browser.click(page,'Use password');await browser.fill(page,'Wallet password',credential);
    await browser.click(page,'Delete');
    await browser.wait(page,`(${credentialsSummary}).then(value=>value.active===0)`,{timeout:60000,label:'password-authorized active-wallet deletion'});
    const remainingWallets=await page.evaluate(`(async()=>{
      let count=0;
      for(const info of await indexedDB.databases()){
        const db=await new Promise((resolve,reject)=>{const open=indexedDB.open(info.name);open.onsuccess=()=>resolve(open.result);open.onerror=reject;});
        if(db.objectStoreNames.contains('mnemonics'))count+=await new Promise((resolve,reject)=>{const request=db.transaction('mnemonics').objectStore('mnemonics').count();request.onsuccess=()=>resolve(request.result);request.onerror=reject;});
        db.close();
      }
      return count;
    })()`);
    assert.equal(remainingWallets,0,'Active deletion must remove the encrypted engine wallet as well as its credential');
    await browser.navigate(page);await browser.semantics(page);
    await browser.wait(page,buttonPresent('Connect wallet'),{label:'entry after wallet removal and cold return'});
    assert.equal(await page.evaluate('__gleecReleaseProbe.metrics().challenges'),0);
    assert.equal((await page.evaluate(credentialsSummary)).active,0);
    console.log('PASS: known-password active deletion removes credentials and engine wallet after provider loss; cold return stays signed out');
    console.log('EVIDENCE',JSON.stringify({buildFingerprint:browser.buildFingerprint,wrongPasswordRejected:true,
      canceledReplacementPreservedRecord:true,newProviderUnlocks:true,coldAssertions:1,passwordDeletion:true,
      returningCancellationStable:true,returningExplicitRetry:true,
      engineWalletRemoved:true,deletionColdReturnSignedOut:true}));
  }finally{credential=null;await browser.cleanup();}
}
if(require.main===module)main().catch(error=>{console.error(error.name,error.message);process.exitCode=1;});
