// Full-app local-data loss checks. Only disposable unfunded profiles are touched.
'use strict';
const assert=require('node:assert/strict');
const path=require('node:path');
const {LocalBrowser,delay}=require('./web_release_test_driver.js');
const {probe,credentialsSummary,buttonPresent,virtualAuthenticator}=require('./web_credential_release.browser.test.js');
const {publicIdentity}=require('./web_wallet_recovery.browser.test.js');

const removeVault=`(async()=>{
  const db=await new Promise(resolve=>{const request=indexedDB.open('gleec-wallet-credentials-v1');request.onsuccess=()=>resolve(request.result);});
  await new Promise((resolve,reject)=>{const tx=db.transaction('credentials','readwrite');tx.objectStore('credentials').clear();tx.oncomplete=resolve;tx.onabort=()=>reject(new Error('Fixture removal failed'));});db.close();return true;
})()`;
const removeWallet=`(async()=>{
  const storageKey=Object.keys(localStorage).find(key=>key.endsWith('wallet_access_last_v1'));
  let last=localStorage.getItem(storageKey);for(let i=0;i<3&&typeof last==='string';i++)last=JSON.parse(last);
  let deleted=0;
  for(const descriptor of await indexedDB.databases()){
    const db=await new Promise(resolve=>{const request=indexedDB.open(descriptor.name);request.onsuccess=()=>resolve(request.result);});
    if(db.objectStoreNames.contains('mnemonics')){
      const primaryKey=await new Promise(resolve=>{const request=db.transaction('mnemonics').objectStore('mnemonics').index('wallet_name').getKey(last.walletId.name);request.onsuccess=()=>resolve(request.result);});
      if(primaryKey!==undefined){await new Promise((resolve,reject)=>{const tx=db.transaction('mnemonics','readwrite');tx.objectStore('mnemonics').delete(primaryKey);tx.oncomplete=resolve;tx.onabort=()=>reject(new Error('Fixture removal failed'));});deleted++;}
    }db.close();
  }
  return deleted;
})()`;
const walletRows=`(async()=>{
  let count=0;
  for(const descriptor of await indexedDB.databases()){
    const db=await new Promise(resolve=>{const request=indexedDB.open(descriptor.name);request.onsuccess=()=>resolve(request.result);});
    if(db.objectStoreNames.contains('mnemonics'))count+=await new Promise(resolve=>{const request=db.transaction('mnemonics').objectStore('mnemonics').count();request.onsuccess=()=>resolve(request.result);});db.close();
  }return count;
})()`;

async function check(kind){
  const browser=new LocalBrowser(path.resolve(__dirname,'../../..'),{port:18769,debugPort:9224});
  let credential;
  try{
    await browser.serve();await browser.launch();
    let page=await browser.page({initialize:probe});await browser.navigate(page);await browser.semantics(page);
    await browser.click(page,'Connect wallet');await browser.click(page,'Create a new wallet');
    await browser.wait(page,buttonPresent('Gleec Wallet'),{timeout:60000,label:'unfunded fixture wallet'});
    credential=await page.evaluate('__gleecReleaseProbe.testCredential()');
    const identity=await page.evaluate(publicIdentity);
    const vault=await page.evaluate(credentialsSummary);
    assert.equal(await page.evaluate(walletRows),1);
    if(kind==='passkeyOnly'){
      const provider=await virtualAuthenticator(browser,page);
      await browser.click(page,'Settings');await browser.click(page,'Security');await browser.click(page,'Set up local passkey');
      await browser.wait(page,`(${credentialsSummary}).then(value=>value.protections[0]==='passkeyPrf')`,{label:'passkey before browser cleanup'});
      const key=await page.evaluate(`(async()=>{const db=await new Promise(resolve=>{const request=indexedDB.open('gleec-wallet-credentials-v1');request.onsuccess=()=>resolve(request.result);});const rows=await new Promise(resolve=>{const request=db.transaction('credentials').objectStore('credentials').getAll();request.onsuccess=()=>resolve(request.result);});db.close();return rows.find(row=>row.slot.startsWith('active:')).walletKey;})()`);
      await page.send('Storage.clearDataForOrigin',{origin:new URL(browser.base).origin,storageTypes:'indexeddb,local_storage,cache_storage,service_workers'});
      await browser.navigate(page);await browser.semantics(page);
      await browser.wait(page,buttonPresent('Connect wallet'),{label:'clean local origin entry'});
      assert.equal((await page.send('WebAuthn.getCredentials',{authenticatorId:provider.authenticatorId})).credentials.length,1);
      assert.equal(await page.evaluate(`gleecWalletCredentials.read({key:${JSON.stringify(key)},requireAuthentication:true})`),null);
      assert.equal(await page.evaluate('__gleecReleaseProbe.metrics().challenges'),0);
      assert.equal(await page.evaluate(walletRows),0);
      await browser.click(page,'Connect wallet');
      await browser.wait(page,buttonPresent('Create a new wallet'),{label:'clean-origin create/import choice'});
      assert.equal(await page.evaluate(buttonPresent('Log In')),false);
      console.log('PASS: retained provider passkey and known password cannot restore a clean local origin without wallet data');
      return;
    }
    if(kind==='credential')await page.evaluate(removeVault);
    else assert.equal(await page.evaluate(removeWallet),1);
    await browser.stopBrowser();await browser.launch();
    page=await browser.page({initialize:probe,existing:true});await browser.navigate(page);await browser.semantics(page);
    await browser.wait(page,`${buttonPresent('Use password')}||${buttonPresent('Log In')}||${buttonPresent('Connect wallet')}`,{timeout:60000,label:'data-loss fallback'});
    await delay(1000);
    assert.equal(await page.evaluate('__gleecReleaseProbe.metrics().observedCredentials'),0,'A missing record must not silently create another credential');
    const after=await page.evaluate(credentialsSummary);
    if(kind==='wallet'){
      assert.deepEqual(after,vault);assert.equal(await page.evaluate(walletRows),0);
      assert.equal(await page.evaluate(buttonPresent('Gleec Wallet')),false,'A credential alone must not present an unlocked wallet');
      if(await page.evaluate(buttonPresent('Connect wallet')))await browser.click(page,'Connect wallet');
      await browser.wait(page,"Array.from(document.querySelectorAll('[role=button]')).some(el=>(el.getAttribute('aria-label')||el.textContent||'').startsWith('I already have a recovery phrase'))",{label:'missing-wallet recovery entry'});
      console.log('PASS: missing encrypted wallet preserves credential, offers import and does not create or claim a recovered wallet');
      return;
    }
    if(await page.evaluate(buttonPresent('Connect wallet'))){
      await browser.click(page,'Connect wallet');
      const stored="Array.from(document.querySelectorAll('[role=button]')).find(el=>(el.getAttribute('aria-label')||el.textContent||'').trim().startsWith('Gleec Wallet'))";
      await browser.wait(page,`!!(${stored})`,{label:'preserved wallet catalog entry'});
      await page.evaluate(`(${stored}).click();true`);
    }
    await browser.wait(page,`${buttonPresent('Use password')}||${buttonPresent('Log In')}`,{label:'explicit recovery form'});
    if(await page.evaluate(buttonPresent('Use password')))await browser.click(page,'Use password');
    if(kind==='credential'){
      assert.equal(after.active,0);assert.equal(await page.evaluate(walletRows),1);
      await browser.fill(page,'Wallet password',credential);await browser.click(page,'Log In');
      await browser.wait(page,buttonPresent('Gleec Wallet'),{timeout:60000,label:'known-password missing-credential recovery'});
      assert.deepEqual(await page.evaluate(publicIdentity),identity);
      console.log('PASS: missing local credential preserves encrypted wallet; known password restores same verified identity');
    }else{
      assert.deepEqual(after,vault);assert.equal(await page.evaluate(walletRows),0);
      assert.equal(await page.evaluate(buttonPresent('Gleec Wallet')),false,'A credential alone must not present an unlocked wallet');
      console.log('PASS: missing encrypted wallet preserves credential and does not create or claim a recovered wallet');
    }
  }finally{credential=null;await browser.cleanup();}
}
if(require.main===module)(async()=>{
  const cases=process.argv.length>2?process.argv.slice(2):['credential','wallet','passkeyOnly'];
  for(const kind of cases){assert.ok(['credential','wallet','passkeyOnly'].includes(kind));await check(kind);}
})().catch(error=>{console.error(error.name,error.message);process.exitCode=1;});
