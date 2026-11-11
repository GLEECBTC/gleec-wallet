// Optional release acceptance harness; creates only unfunded disposable wallets.
// Uses the existing build/web. Requires Node 22+ and a locally installed Chrome.
'use strict';

const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const { gunzipSync } = require('node:zlib');
const { LocalBrowser, delay } = require('./web_release_test_driver.js');

const probe = `(() => {
  const secrets=new Set();
  const measures={challenges:0,fulfilledAssertions:0,registrations:0,systemMilliseconds:0,cspViolations:0};
  let api;
  Object.defineProperty(window,'gleecWalletCredentials',{configurable:true,get:()=>api,set(value){
    api=Object.freeze({...value,write:async args=>{secrets.add(args.value);return value.write(args);}});
  }});
  for(const method of ['get','create']){
    const original=navigator.credentials[method].bind(navigator.credentials);
    navigator.credentials[method]=async options=>{
      if(options.publicKey)measures[method==='get'?'challenges':'registrations']++;
      const start=performance.now();try{
        const credential=await original(options);
        if(options.publicKey&&method==='get'&&credential?.type==='public-key')measures.fulfilledAssertions++;
        return credential;
      }
      finally{if(options.publicKey)measures.systemMilliseconds+=performance.now()-start;}
    };
  }
  document.addEventListener('securitypolicyviolation',()=>measures.cspViolations++);
  new MutationObserver(()=>{
    if(measures.creationStarted&&!measures.feedbackObserved&&document.body?.textContent.includes('Creating your wallet')){
      measures.feedbackObserved=performance.now();
      requestAnimationFrame(()=>requestAnimationFrame(()=>{measures.feedbackPainted=performance.now();}));
    }
  }).observe(document,{subtree:true,childList:true,characterData:true});
  window.__gleecReleaseProbe={
    begin(){measures.creationStarted=performance.now();},
    complete(){measures.creationComplete=performance.now();},
    metrics:()=>({...measures,observedCredentials:secrets.size}),
    // Test process memory only; never printed, logged or persisted by this probe.
    testCredential:()=>Array.from(secrets)[0],
    testAddCanary:value=>secrets.add(value),
    containsCredential:text=>Array.from(secrets).some(secret=>typeof secret==='string'&&text.includes(secret)),
  };
})();`;

const credentialsSummary = `(async()=>{
  const rows=await new Promise((resolve,reject)=>{
    const open=indexedDB.open('gleec-wallet-credentials-v1');
    open.onerror=()=>reject(new Error('Database unavailable'));
    open.onsuccess=()=>{const db=open.result;const request=db.transaction('credentials').objectStore('credentials').getAll();
      request.onsuccess=()=>{resolve(request.result);db.close();};};
  });
  const active=rows.filter(row=>row.slot.startsWith('active:')).map(row=>row.record);
  const identity=JSON.stringify(active.map(record=>[record.key,record.enrollmentId,record.credentialId,record.revision,record.protection]));
  const digest=await crypto.subtle.digest('SHA-256',new TextEncoder().encode(identity));
  const fingerprint=Array.from(new Uint8Array(digest),byte=>byte.toString(16).padStart(2,'0')).join('');
  return {active:active.length,staged:rows.filter(row=>row.slot.startsWith('staged:')).length,
    unattended:active.filter(record=>record.unattendedKey).length,protections:active.map(record=>record.protection),fingerprint};
})()`;

const buttonPresent = label => `Array.from(document.querySelectorAll('[role=button]')).some(el=>(el.getAttribute('aria-label')||el.textContent||'').trim()===${JSON.stringify(label)})`;

async function waitForPasskeySettingsReady(browser,page) {
  try {
    await browser.wait(page, `(()=>{
    const decode=key=>{let value=key?localStorage.getItem(key):null;for(let i=0;i<3&&typeof value==='string';i++){try{value=JSON.parse(value);}catch(_){break;}}return value;};
    const keys=Object.keys(localStorage);
    const last=decode(keys.find(key=>key.endsWith('wallet_access_last_v1')));
    const records=decode(keys.find(key=>key.endsWith('wallet_access_records_v1')));
    const record=records?.[last?.entryId];
    const action=Array.from(document.querySelectorAll('[role=button]')).find(el=>
      (el.getAttribute('aria-label')||el.textContent||'').trim()==='Replace passkey using password'&&el.getAttribute('aria-disabled')!=='true');
    return record?.phase==='ready'&&record?.requiresAuthentication===true&&record?.protection==='passkey'&&!!action;
    })()`,{timeout:90000,label:'passkey protection and authenticated readback completed'});
  } catch(error) {
    console.log('PUBLIC_SETUP_STATUS',JSON.stringify(await page.evaluate(`(()=>{
      const metrics=__gleecReleaseProbe.metrics();
      return {challenges:metrics.challenges,registrations:metrics.registrations,
        createAction:${buttonPresent('Create a passkey')},replaceAction:${buttonPresent('Replace passkey using password')},
        canceled:document.body.textContent.includes('Setup canceled'),
        stale:document.body.textContent.includes('Wallet access changed'),
        busy:document.body.textContent.includes('Finish the current device'),
        unsupported:document.body.textContent.includes('This browser or provider'),
        failed:document.body.textContent.includes('This change could not be completed')};
    })()`)));
    throw error;
  }
}

async function virtualAuthenticator(browser,page) {
  await page.send('WebAuthn.enable');
  const {authenticatorId}=await page.send('WebAuthn.addVirtualAuthenticator',{options:{
    protocol:'ctap2',ctap2Version:'ctap2_1',transport:'internal',hasResidentKey:true,
    hasUserVerification:true,isUserVerified:true,hasPrf:true,hasHmacSecret:true,automaticPresenceSimulation:true,
  }});
  const counts={created:0,asserted:0};
  browser.events.add(message=>{
    if(message.sessionId!==page.sessionId)return;
    if(message.method==='WebAuthn.credentialAdded')counts.created++;
    if(message.method==='WebAuthn.credentialAsserted')counts.asserted++;
  });
  return {authenticatorId,counts};
}

async function unlockApp(browser,page) {
  // Status loading and automatic return can finish between CDP requests. Wait
  // for a live choice and activate it atomically, once per explicit stage.
  const activate=labels=>`(()=>{
    if(${buttonPresent('Gleec Wallet')})return 'wallet';
    const element=Array.from(document.querySelectorAll('[role=button]')).find(el=>${JSON.stringify(labels)}.includes((el.getAttribute('aria-label')||el.textContent||'').trim())&&el.getAttribute('aria-disabled')!=='true');
    if(!element)return false;
    const label=(element.getAttribute('aria-label')||element.textContent||'').trim();element.click();return label;
  })()`;
  const stage=await browser.wait(page,activate(['Unlock','Unlock with passkey']),
    {timeout:60000,label:'wallet unlock entry'});
  if(stage==='Unlock')await browser.wait(page,activate(['Unlock with passkey']),
    {timeout:60000,label:'passkey unlock entry'});
  await browser.wait(page,buttonPresent('Gleec Wallet'),{timeout:60000,label:'wallet unlocked'});
}

async function verifiedBrowserReturn(browser,page,before) {
  const snapshot=`(()=>({
    ...__gleecReleaseProbe.metrics(),walletVisible:${buttonPresent('Gleec Wallet')},
    retryAvailable:Array.from(document.querySelectorAll('[role=button]')).some(el=>
      ['Unlock','Unlock with passkey'].includes((el.getAttribute('aria-label')||el.textContent||'').trim())&&el.getAttribute('aria-disabled')!=='true')
  }))()`;
  // Browser focus and user-activation policies differ. A return may either
  // finish its one automatic challenge or require an explicit retry. Count
  // fulfilled browser assertions before the vault receives them; CDP event
  // delivery is not the authorization boundary after a frozen renderer.
  const started=performance.now();
  const deadline=started+60000;
  while(performance.now()<deadline){
    const state=await page.evaluate(snapshot);
    const attempts=state.challenges-before.challenges;
    const assertions=state.fulfilledAssertions-before.fulfilledAssertions;
    assert.ok(attempts<=1,'Return must initiate at most one automatic challenge');
    assert.ok(assertions<=1,'Return must not duplicate successful assertions');
    if(assertions===1){
      await browser.wait(page,buttonPresent('Gleec Wallet'),{label:'freshly authenticated browser return'});
      return {automaticAttempts:attempts,automaticAssertions:1,explicitRetry:false};
    }
    assert.equal(state.walletVisible,false,'Expired grace must not expose the wallet before a fresh assertion');
    if(state.retryAvailable&&(attempts>0||performance.now()-started>=1000)){
      await delay(500);
      const stable=await page.evaluate(snapshot);
      assert.ok(stable.challenges-before.challenges<=1,'An automatic failure must not prompt again');
      if(stable.fulfilledAssertions===before.fulfilledAssertions+1){
        await browser.wait(page,buttonPresent('Gleec Wallet'),{label:'verified automatic return during handoff'});
        return {automaticAttempts:stable.challenges-before.challenges,automaticAssertions:1,explicitRetry:false};
      }
      if(stable.challenges!==state.challenges||!stable.retryAvailable)continue;
      assert.equal(stable.walletVisible,false);
      assert.equal(stable.challenges,state.challenges,'An automatic failure must not prompt again');
      assert.equal(stable.fulfilledAssertions,before.fulfilledAssertions);
      await unlockApp(browser,page);
      const completed=await page.evaluate(snapshot);
      assert.equal(completed.fulfilledAssertions,before.fulfilledAssertions+1,
        'Explicit retry must obtain one fresh browser assertion');
      assert.equal(completed.challenges,before.challenges+attempts+1);
      return {automaticAttempts:attempts,automaticAssertions:0,explicitRetry:true};
    }
    await delay(100);
  }
  throw new Error('No verified browser return or stable explicit unlock fallback');
}

async function main() {
  const root=path.resolve(__dirname,'../../..');
  const browser=new LocalBrowser(root);
  const evidence={};
  const consoleMessages=[];
  let generatedCredential;
  try {
    await browser.serve(); await browser.launch();
    evidence.browser=browser.version;
    let page=await browser.page({initialize:probe});
    browser.events.add(message=>{
      if(message.method==='Runtime.consoleAPICalled'){
        consoleMessages.push((message.params.args??[]).map(arg=>typeof arg.value==='string'?arg.value:'').join(' '));
      }
    });
    await browser.navigate(page); await browser.semantics(page);
    console.log('CHECK: fresh production app loaded');
    await browser.wait(page,buttonPresent('Create a new wallet'),{label:'instant creation entry'});
    const assets=await browser.wait(page,`performance.getEntriesByType('resource').filter(entry=>entry.name.includes('/kdf/')&&entry.name.endsWith('.wasm')&&entry.responseEnd>0).map(entry=>({duration:entry.duration,responseEnd:entry.responseEnd})).length>0`,
      {timeout:60000,label:'KDF engine asset download'});
    assert.ok(assets);
    evidence.engineAssets=await page.evaluate("performance.getEntriesByType('resource').filter(entry=>entry.name.includes('/kdf/')&&entry.name.endsWith('.wasm')).map(entry=>({durationMs:Math.round(entry.duration),responseEndMs:Math.round(entry.responseEnd)}))");
    await page.evaluate(`__gleecReleaseProbe.begin();Array.from(document.querySelectorAll('[role=button]')).find(el=>(el.getAttribute('aria-label')||el.textContent||'').trim()==='Create a new wallet').click();true`);
    await browser.wait(page,buttonPresent('Gleec Wallet'),{timeout:60000,label:'new wallet opened'});
    await page.evaluate('__gleecReleaseProbe.complete();true');
    const metrics=await page.evaluate('__gleecReleaseProbe.metrics()');
    generatedCredential=await page.evaluate('__gleecReleaseProbe.testCredential()');
    evidence.buildFingerprint=browser.buildFingerprint;
    evidence.creation={feedbackObservedMs:Math.round(metrics.feedbackObserved-metrics.creationStarted),
      feedbackPaintEstimateMs:Math.round(metrics.feedbackPainted-metrics.creationStarted),
      completeObservedMs:Math.round(metrics.creationComplete-metrics.creationStarted),
      navigationToCreationStartMs:Math.round(metrics.creationStarted),
      navigationToWalletMs:Math.round(metrics.creationComplete),
      systemMs:Math.round(metrics.systemMilliseconds),systemChallenges:metrics.challenges,
      cspViolations:metrics.cspViolations,credentialWritesObserved:metrics.observedCredentials};
    assert.equal(metrics.cspViolations,0);
    assert.ok(metrics.feedbackObserved,'Creation must show immediate feedback');
    const before=await page.evaluate(credentialsSummary);
    assert.equal(before.active,1);assert.equal(before.unattended,1);assert.equal(before.staged,0);
    assert.equal(await page.evaluate(`__gleecReleaseProbe.containsCredential(${JSON.stringify(consoleMessages.join('\n'))})`),false,
      'Generated credential must not appear in browser console diagnostics');
    evidence.consoleCanary={generatedCredentialObserved:metrics.observedCredentials>0,leaked:false};
    console.log('PASS: durable instant creation and console credential canary',JSON.stringify(evidence.creation));

    await browser.click(page,'Settings');
    await browser.click(page,'Download logs');
    let download;
    for(let attempt=0;attempt<100;attempt++){
      download=fs.readdirSync(browser.downloads).find(name=>name.endsWith('.zip'));
      if(download)break;
      await delay(100);
    }
    assert.ok(download,'The app must produce its diagnostic download');
    const exported=gunzipSync(fs.readFileSync(path.join(browser.downloads,download))).toString('utf8');
    assert.equal(await page.evaluate(`__gleecReleaseProbe.containsCredential(${JSON.stringify(exported)})`),false,
      'Generated credential must not appear in the app diagnostic export');
    const records=exported.split('\n').filter(Boolean).map(line=>JSON.parse(line));
    assert.ok(records.every(record=>record.schema===1),'Only current-schema diagnostics may be exported');
    evidence.diagnosticExport={bytes:Buffer.byteLength(exported),records:records.length,generatedCredentialLeaked:false};
    console.log('PASS: app diagnostic download excludes the generated credential',JSON.stringify(evidence.diagnosticExport));

    // Preserve the disposable profile while terminating the entire Chrome process.
    await browser.stopBrowser(); await browser.launch();
    page=await browser.page({initialize:probe,existing:true});
    await browser.navigate(page); await browser.semantics(page);
    await browser.wait(page,buttonPresent('Gleec Wallet'),{timeout:60000,label:'unprotected full-process return'});
    assert.deepEqual(await page.evaluate(credentialsSummary),before);
    evidence.fullProcessRestartUnprotected=true;
    console.log('PASS: full browser-process restart preserves wallet identity and unattended access');

    // A second real tab has already opened through the unattended credential.
    const second=await browser.page({initialize:probe});
    await browser.navigate(second);await browser.semantics(second);
    await browser.wait(second,buttonPresent('Gleec Wallet'),{timeout:60000,label:'second tab wallet'});
    await second.evaluate("window.__revisionEvents=[];gleecWalletCredentials.subscribe(event=>__revisionEvents.push({external:event.external,fields:Object.keys(event).sort(),protection:event.protection}));true");
    await page.send('Page.bringToFront');
    const virtual=await virtualAuthenticator(browser,page);
    await browser.click(page,'Settings');await browser.click(page,'Security');
    await browser.click(page,'Create a passkey',{pointer:true});
    await browser.wait(page,`(${credentialsSummary}).then(value=>value.protections[0]==='passkeyPrf')`,{label:'passkey protection persisted'});
    // The envelope is committed before the service finishes its authenticated
    // readback. Keep this tab foreground until enrollment reports completion;
    // otherwise the readback can still own the origin-wide ceremony lock.
    // The success notice can be outside the viewport's semantics. Bind to the
    // wallet's committed app record and the enabled completed-action control.
    await waitForPasskeySettingsReady(browser,page);
    const protectedSummary=await page.evaluate(credentialsSummary);
    assert.equal(protectedSummary.unattended,0);assert.equal(protectedSummary.staged,0);
    assert.equal(virtual.counts.created,1);
    await browser.wait(second,"window.__revisionEvents.some(event=>event.external&&event.protection==='passkeyPrf')",{label:'cross-tab protection event'});
    await second.send('Page.bringToFront');
    const external=await second.evaluate('window.__revisionEvents');
    assert.ok(external.every(event=>event.fields.join(',')==='external,key,protection,revision'));
    // Returning this already-open tab can start its one automatic unlock.
    // Cancel that fixture ceremony before probing the old unattended path;
    // cancellation releases the origin lock asynchronously.
    await second.evaluate('gleecWalletCredentials.cancel();true');
    let crossTabRead;
    for(let attempt=0;attempt<100;attempt++){
      crossTabRead=await second.evaluate(`(async()=>{
      let attempted=0;const original=navigator.credentials.get;
      navigator.credentials.get=async()=>{attempted++;throw new DOMException('','NotAllowedError');};
      try{
        const db=await new Promise(resolve=>{const open=indexedDB.open('gleec-wallet-credentials-v1');open.onsuccess=()=>resolve(open.result);});
        const key=await new Promise(resolve=>{const request=db.transaction('credentials').objectStore('credentials').getAll();request.onsuccess=()=>resolve(request.result.find(row=>row.slot.startsWith('active:')).walletKey);});db.close();
        try{await gleecWalletCredentials.read({key,requireAuthentication:false});return{attempted,unexpectedSuccess:true};}
        catch(error){return{attempted,failure:error.code};}
      }finally{navigator.credentials.get=original;}
      })()`);
      if(crossTabRead.failure!=='busy')break;
      await delay(50);
    }
    assert.deepEqual(crossTabRead,{attempted:1,failure:'notCompleted'});
    evidence.crossTabProtection={revisionEvent:true,unattendedPathRemoved:true};
    console.log('PASS: another real tab loses unattended access after passkey enrollment');
    await page.send('Page.bringToFront');

    // A real origin-wide lock rejects a second tab immediately, without a prompt.
    await page.evaluate("window.__heldVaultLock=navigator.locks.request('gleec-wallet-credentials-v1',()=>new Promise(resolve=>{window.__releaseVaultLock=resolve;}));true");
    await browser.wait(page,"typeof window.__releaseVaultLock==='function'",{label:'test ceremony lock'});
    const lockedRead=await second.evaluate("gleecWalletCredentials.read({key:'blocked-fixture'}).then(()=> 'unexpectedSuccess',error=>error.code)");
    assert.equal(lockedRead,'busy');
    await page.evaluate('window.__releaseVaultLock();window.__heldVaultLock.then(()=>true)');

    // Store the immutable key in this fixture's memory, never the credential.
    await page.evaluate(`(async()=>{
      const db=await new Promise(resolve=>{const request=indexedDB.open('gleec-wallet-credentials-v1');request.onsuccess=()=>resolve(request.result);});
      window.__walletKey=await new Promise(resolve=>{const request=db.transaction('credentials').objectStore('credentials').getAll();request.onsuccess=()=>resolve(request.result.find(row=>row.slot.startsWith('active:')).walletKey);});db.close();return true;
    })()`);
    await page.send('WebAuthn.setAutomaticPresenceSimulation',{authenticatorId:virtual.authenticatorId,enabled:false});
    await page.evaluate("window.__pendingRead=gleecWalletCredentials.read({key:window.__walletKey}).then(()=> 'unexpectedSuccess',error=>error.code);true");
    await delay(100);
    // An external revision notification must invalidate an in-flight result,
    // even if it arrives while the browser's system ceremony is outstanding.
    const revisionKey=await page.evaluate('window.__walletKey');
    await second.evaluate(`(()=>{const channel=new BroadcastChannel('gleec-wallet-credentials-v1');channel.postMessage({key:${JSON.stringify(revisionKey)},revision:999999,protection:'passkeyPrf'});channel.close();return true;})()`);
    assert.ok(['aborted','staleOperation'].includes(await page.evaluate('window.__pendingRead')));
    await page.send('WebAuthn.setAutomaticPresenceSimulation',{authenticatorId:virtual.authenticatorId,enabled:true});
    assert.deepEqual(await page.evaluate(credentialsSummary),protectedSummary);
    evidence.crossTabProtection.busyWithoutPrompt=true;
    evidence.crossTabProtection.externalRevisionCancelsPending=true;
    console.log('PASS: real Web Locks reject concurrent prompts and external revisions abort stale reads');

    // Finish the multi-tab fixture before mutating ciphertext. A focus-driven
    // app return can still own or be requesting a challenge on a slow runner.
    await browser.command('Target.closeTarget',{targetId:second.targetId});
    await page.evaluate('gleecWalletCredentials.cancel();true');
    await browser.wait(page,`navigator.locks.query().then(state=>
      ![...state.held,...state.pending].some(lock=>lock.name==='gleec-wallet-credentials-v1'))`,
      {timeout:5000,label:'aborted ceremony releases the vault lock'});
    const corrupted=await page.evaluate(`(async()=>{
      const db=await new Promise(resolve=>{const request=indexedDB.open('gleec-wallet-credentials-v1');request.onsuccess=()=>resolve(request.result);});
      const slot='active:'+window.__walletKey;
      const original=await new Promise(resolve=>{const request=db.transaction('credentials').objectStore('credentials').get(slot);request.onsuccess=()=>resolve(request.result);});
      const write=row=>new Promise((resolve,reject)=>{const tx=db.transaction('credentials','readwrite');tx.objectStore('credentials').put(row);tx.oncomplete=resolve;tx.onabort=()=>reject(new Error('Fixture mutation failed'));});
      const damaged=structuredClone(original);new Uint8Array(damaged.record.ciphertext)[0]^=1;
      try{
        await write(damaged);
        let failure;
        for(let attempt=0;attempt<100;attempt++){
          try{await gleecWalletCredentials.read({key:window.__walletKey});failure='unexpectedSuccess';}
          catch(error){failure=error.code;}
          if(failure!=='busy')break;
          await new Promise(resolve=>setTimeout(resolve,50));
        }
        return failure;
      }finally{await write(original);db.close();}
    })()`);
    assert.equal(corrupted,'envelopeCorrupt');
    assert.deepEqual(await page.evaluate(credentialsSummary),protectedSummary);
    evidence.corruptEnvelope={authenticatedDecryptionRejected:true,recordPreserved:true};
    console.log('PASS: corrupt protected ciphertext fails closed without deleting or downgrading the wallet');
    if(process.env.GLEEC_TEST_LIFECYCLE==='true'){
      await browser.wait(page,`navigator.locks.query().then(state=>
        ![...state.held,...state.pending].some(lock=>lock.name==='gleec-wallet-credentials-v1'))`,
        {timeout:5000,label:'corrupt-envelope probe releases the vault lock'});
      await unlockApp(browser,page);
      await page.send('Emulation.setFocusEmulationEnabled',{enabled:false});
      await page.send('Page.bringToFront');
      const background=await browser.page();
      const returns=[];
      for(const seconds of [29,31]){
        await page.send('Page.bringToFront');
        await browser.wait(page,"document.visibilityState==='visible'",{label:'visible wallet before background'});
        const assertionsBefore=virtual.counts.asserted;
        const requestsBefore=await page.evaluate('__gleecReleaseProbe.metrics()');
        await background.send('Page.bringToFront');
        await browser.wait(page,"document.visibilityState==='hidden'",{label:'real background visibility'});
        await page.send('Page.setWebLifecycleState',{state:'frozen'});
        console.log(`CHECK: frozen background for ${seconds} seconds`);
        const began=performance.now();await delay(seconds*1000);
        await page.send('Page.setWebLifecycleState',{state:'active'});
        await page.send('Page.bringToFront');
        await browser.wait(page,"document.visibilityState==='visible'",{label:'wallet resumed'});
        if(seconds===29){
          await browser.wait(page,buttonPresent('Gleec Wallet'),{label:'grace restores existing session'});
          assert.equal(virtual.counts.asserted,assertionsBefore);
          const current=await page.evaluate('__gleecReleaseProbe.metrics()');
          assert.equal(current.fulfilledAssertions,requestsBefore.fulfilledAssertions);
          assert.equal(current.challenges,requestsBefore.challenges);
          returns.push({seconds,elapsedMs:Math.round(performance.now()-began),locked:false,additionalAssertions:0});
        }else{
          const result=await verifiedBrowserReturn(browser,page,requestsBefore);
          returns.push({seconds,elapsedMs:Math.round(performance.now()-began),locked:true,
            additionalAssertions:1,...result});
        }
      }
      evidence.frozenBackgroundGrace=returns;
      await browser.command('Target.closeTarget',{targetId:background.targetId});
      console.log('PASS: 29/31-second real background returns respect grace despite frozen timers');
    }

    console.log('CHECK: protected wallet record survives another full browser restart with no provider');
    await browser.stopBrowser();await browser.launch();
    page=await browser.page({initialize:probe,existing:true});
    const missingProvider=await virtualAuthenticator(browser,page);
    await browser.navigate(page);await browser.semantics(page);
    await browser.wait(page,"__gleecReleaseProbe.metrics().challenges===1",{label:'missing-provider return attempt'});
    // A browser cannot reliably distinguish provider loss from cancellation.
    // End the unavailable virtual-provider ceremony without fabricating access.
    await page.evaluate('gleecWalletCredentials.cancel();true');
    await browser.wait(page,buttonPresent('Use password'),{label:'provider-loss password fallback'});
    await browser.wait(page,buttonPresent('Recover wallet'),{label:'provider-loss recovery fallback'});
    assert.deepEqual(await page.evaluate(credentialsSummary),protectedSummary);
    assert.equal(missingProvider.counts.created,0);assert.equal(missingProvider.counts.asserted,0);
    const providerMetrics=await page.evaluate('__gleecReleaseProbe.metrics()');
    assert.equal(providerMetrics.challenges,1);
    evidence.providerLoss={walletPreserved:true,unattendedDowngrade:false,passwordAndRecoveryAvailable:true,
      canceledUnavailableCeremony:true,physicalProviderRestartNotProven:true};
    console.log('PASS: provider loss preserves the protected record and exposes recovery fallback');

    await browser.click(page,'Use password');
    await browser.fill(page,'Wallet password',generatedCredential);
    await browser.click(page,'Log In');
    await browser.wait(page,buttonPresent('Gleec Wallet'),{timeout:60000,label:'known-password provider-loss return'});
    assert.deepEqual(await page.evaluate(credentialsSummary),protectedSummary);
    await browser.click(page,'Settings');await browser.click(page,'Security');
    await browser.wait(page,buttonPresent('Replace passkey using password'),
      {timeout:15000,label:'protected-wallet recovery settings loaded'});
    const protectionActions=await browser.buttons(page);
    evidence.providerLoss.knownPasswordLoginWorks=true;
    evidence.providerLoss.passwordReplacementAvailable=protectionActions.includes('Replace passkey using password');
    assert.equal(evidence.providerLoss.passwordReplacementAvailable,true);
    console.log('PASS: known-password fallback succeeds and offers explicit passkey replacement');

    console.log('EVIDENCE',JSON.stringify(evidence));
  } finally { generatedCredential=null;await browser.cleanup(); }
}

module.exports={probe,credentialsSummary,buttonPresent,virtualAuthenticator,unlockApp,waitForPasskeySettingsReady};
if(require.main===module)main().catch(error=>{console.error(error.name,error.message);process.exitCode=1;});
