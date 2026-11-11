// Optional full-app recovery checks. Secrets stay in this disposable test's
// process memory; no screenshots, clipboard use, raw logs or financial requests.
'use strict';

const assert=require('node:assert/strict');
const fs=require('node:fs');
const path=require('node:path');
const {gunzipSync}=require('node:zlib');
const {LocalBrowser,delay}=require('./web_release_test_driver.js');
const {probe,credentialsSummary,buttonPresent,virtualAuthenticator,waitForPasskeySettingsReady}=require('./web_credential_release.browser.test.js');

const publicIdentity=`(async()=>{
  const key=Object.keys(localStorage).find(key=>key.endsWith('wallet_access_last_v1'));
  let last=key?localStorage.getItem(key):null;
  for(let pass=0;pass<3&&typeof last==='string';pass++){try{last=JSON.parse(last);}catch(_){break;}}
  if(!last?.walletId?.pubkey_hash)throw new Error('Verified identity unavailable');
  const identity=JSON.stringify([last.walletId.pubkey_hash,last.walletId.auth_options]);
  const digest=await crypto.subtle.digest('SHA-256',new TextEncoder().encode(identity));
  return{entryId:last.entryId,identity:Array.from(new Uint8Array(digest),byte=>byte.toString(16).padStart(2,'0')).join('')};
})()`;

// Read only the current disposable wallet's catalog metadata. The plugin's
// local key and decrypted catalog remain inside the page; return this whitelist.
const recoverySummary=`(async()=>{
  const lastKey=Object.keys(localStorage).find(key=>key.endsWith('wallet_access_last_v1'));
  let last=lastKey?localStorage.getItem(lastKey):null;
  for(let pass=0;pass<3&&typeof last==='string';pass++){try{last=JSON.parse(last);}catch(_){break;}}
  if(!last?.walletId?.name||!last?.entryId)throw new Error('Fixture identity unavailable');
  const encoded=localStorage.getItem('FlutterSecureStorage.user_'+last.walletId.name);
  const encodedKey=localStorage.getItem('FlutterSecureStorage');
  if(!encoded||!encodedKey)throw new Error('Fixture catalog unavailable');
  const bytes=value=>Uint8Array.from(atob(value),character=>character.charCodeAt(0));
  const [iv,ciphertext]=encoded.split('.');
  const key=await crypto.subtle.importKey('raw',bytes(encodedKey),{name:'AES-GCM'},false,['decrypt']);
  const plain=await crypto.subtle.decrypt({name:'AES-GCM',iv:bytes(iv)},key,bytes(ciphertext));
  const user=JSON.parse(new TextDecoder().decode(plain));
  const metadata=user.metadata??{};
  if(user.wallet_id?.pubkey_hash!==last.walletId.pubkey_hash||metadata._wallet_entry_id!==last.entryId)
    throw new Error('Fixture catalog identity changed');
  return{hasBackup:metadata.has_backup===true,evidence:metadata.recovery_evidence??'none',
    exportRequested:metadata.encrypted_file_export_requested===true,
    exportConfirmed:metadata.encrypted_file_exported===true};
})()`;

async function signOut(browser,page,{contend=false}={}){
  await browser.click(page,'Settings');await browser.click(page,'Log out');
  await browser.wait(page,"!!document.querySelector('[role=dialog]')",{label:'sign-out confirmation'});
  if(contend){
    await page.evaluate("window.__heldAccessLock=navigator.locks.request('gleec-wallet-access',()=>new Promise(resolve=>{window.__releaseAccessLock=resolve;}));true");
    await browser.wait(page,"typeof window.__releaseAccessLock==='function'",{label:'short access-lock contention fixture'});
  }
  await browser.click(page,'Log out');
  if(contend){
    await delay(250);
    assert.equal(await page.evaluate(buttonPresent('Connect wallet')),false,
      'Sign-out must remain covered until its durable preference is written');
    await page.evaluate('window.__releaseAccessLock();window.__heldAccessLock.then(()=>true)');
  }
  // Finish the current shutdown before testing a cold, explicitly signed-out
  // launch. A page reload must not interrupt the confirmation transition.
  await browser.wait(page,`(${buttonPresent('Connect wallet')})&&!document.querySelector('[role=dialog],[role=progressbar]')`,
    {timeout:60000,label:'completed explicit sign-out'});
  await browser.navigate(page);await browser.semantics(page);
  await browser.wait(page,buttonPresent('Connect wallet'),{label:'signed-out entry'});
  if(contend)console.log('PASS: short access-lock contention retries sign-out without another user action and survives reload');
}

async function openImport(browser,page){
  // The signed-out wallet route already owns an inline manager. Opening the
  // header dialog duplicates its controls and can target the obscured entry.
  await browser.wait(page,"(()=>{const element=Array.from(document.querySelectorAll('[role=button]')).find(el=>(el.getAttribute('aria-label')||el.textContent||'').startsWith('Import an existing wallet'));if(!element||element.getAttribute('aria-disabled')==='true')return false;element.click();return true;})()",{label:'inline import entry'});
  await browser.wait(page,"Array.from(document.querySelectorAll('input,textarea,[role=textbox]')).some(el=>(el.getAttribute('aria-label')||'').split('\\n').some(part=>part.trim()==='Wallet name')&&!el.readOnly)",
    {label:'import form ready'});
}

async function newDownload(browser,before,{suffix}={}){
  for(let attempt=0;attempt<150;attempt++){
    // Chrome can expose a hidden staging file before renaming the completed
    // download. Never decode that file as an encrypted wallet or log archive.
    const filename=fs.readdirSync(browser.downloads).find(name=>
      !before.has(name)&&!name.startsWith('.')&&!name.endsWith('.crdownload')&&
      (!suffix||name.endsWith(suffix)));
    if(filename)return path.join(browser.downloads,filename);
    await delay(100);
  }
  throw new Error('Fixture encrypted-wallet download did not complete');
}

async function main(){
  const browser=new LocalBrowser(path.resolve(__dirname,'../../..'));
  let generatedCredential;
  let phrase;
  const evidence={};
  const consoleMessages=[];
  try{
    await browser.serve();await browser.launch();
    evidence.buildFingerprint=browser.buildFingerprint;
    browser.events.add(message=>{
      if(message.method==='Runtime.consoleAPICalled')consoleMessages.push((message.params.args??[])
        .map(arg=>typeof arg.value==='string'?arg.value:'').join(' '));
    });
    // Hold the optional provider reply to reproduce setup racing the automatic
    // password save. This fixture never saves or returns a password credential.
    const providerPending=`(() => {
      navigator.credentials.store=async()=>{
        window.__providerSaveReached=true;
        await new Promise(resolve=>{window.__completeProviderSave=resolve;});
        return null;
      };
    })();`;
    const page=await browser.page({initialize:probe+'\n'+providerPending});
    await browser.navigate(page);await browser.semantics(page);
    await browser.click(page,'Create a new wallet');
    await browser.wait(page,buttonPresent('Gleec Wallet'),{timeout:60000,label:'unfunded wallet created'});
    console.log('CHECK: disposable recovery wallet created');
    generatedCredential=await page.evaluate('__gleecReleaseProbe.testCredential()');
    assert.equal(typeof generatedCredential,'string');
    const originalIdentity=await page.evaluate(publicIdentity);
    const virtual=await virtualAuthenticator(browser,page);
    await browser.wait(page,"window.__providerSaveReached===true",{timeout:60000,label:'optional provider save is pending'});
    await browser.click(page,'Settings');await browser.click(page,'Security');
    await browser.wait(page,`Array.from(document.querySelectorAll('[role=button]')).some(el=>
      (el.getAttribute('aria-label')||el.textContent||'').trim()==='Create a passkey'&&el.getAttribute('aria-disabled')==='true')`,
      {label:'protection waits for automatic provider save'});
    assert.equal(await page.evaluate('__gleecReleaseProbe.metrics().registrations'),0);
    assert.equal(await page.evaluate(buttonPresent('Save to password manager')),false);
    await page.evaluate('window.__completeProviderSave();true');
    console.log('PASS: automatic provider saving disables setup until completion without another Save action or ceremony');
    await browser.click(page,'Create a passkey',{pointer:true});
    await waitForPasskeySettingsReady(browser,page);
    const enrollmentPrompts=await page.evaluate('__gleecReleaseProbe.metrics()');
    assert.equal(enrollmentPrompts.registrations,1,'Setup creates one passkey');
    assert.equal(enrollmentPrompts.challenges,1,'Setup verifies its new passkey once, without a second unlock');
    await browser.click(page,'Wallet');
    await browser.wait(page,buttonPresent('Gleec Wallet'),{label:'wallet after passkey setup'});
    await browser.click(page,'Settings');await browser.click(page,'Security');
    await waitForPasskeySettingsReady(browser,page);
    const afterNavigation=await page.evaluate('__gleecReleaseProbe.metrics()');
    assert.equal(afterNavigation.registrations,1,'Rebuilding setup must not save another passkey');
    assert.equal(afterNavigation.challenges,1,'Returning to protection settings must not unlock again');
    evidence.passkeySetup={registrations:1,verificationAssertions:1,extraPromptsOnNavigation:0};
    console.log('CHECK: recovery wallet protected with one registration and one verification');

    // Download before phrase confirmation so existing phrase evidence cannot
    // hide an incorrect claim that a browser download completed a backup.
    const initialRecovery=await page.evaluate(recoverySummary);
    assert.deepEqual(initialRecovery,{hasBackup:false,evidence:'none',exportRequested:false,exportConfirmed:false});
    const filesBefore=new Set(fs.readdirSync(browser.downloads));
    const beforeExport=virtual.counts.asserted;
    await browser.click(page,'Download as file');
    await browser.wait(page,buttonPresent('Continue'),{label:'encrypted export authorization'});
    assert.equal(await page.evaluate("document.querySelectorAll('input[type=password]').length"),0);
    await browser.click(page,'Continue');
    const exported=await newDownload(browser,filesBefore);
    const ciphertext=fs.readFileSync(exported,'utf8');
    assert.equal(ciphertext.includes(generatedCredential),false);
    assert.ok(virtual.counts.asserted>beforeExport);
    await browser.wait(page,`(${recoverySummary}).then(value=>value.exportRequested)`,{label:'unconfirmed browser export evidence'});
    assert.deepEqual(await page.evaluate(recoverySummary),
      {hasBackup:false,evidence:'none',exportRequested:true,exportConfirmed:false});
    assert.equal(await page.evaluate(buttonPresent('Backup seed phrase')),true);
    const importFile=path.join(browser.downloads,'File Restore.txt');fs.copyFileSync(exported,importFile);
    evidence.encryptedExport={downloaded:true,unknownCredentialNeverTyped:true,
      requestedOnly:true,confirmedBackupNotClaimed:true,phraseReminderRetained:true};
    console.log('PASS: encrypted browser download remains requested-only and preserves the recovery reminder');

    const beforeBackup=virtual.counts.asserted;
    await browser.click(page,'Backup seed phrase');
    console.log('CHECK: requested fresh authorization for phrase backup');
    await browser.wait(page,buttonPresent('Continue'),{label:'sensitive-action confirmation'});
    assert.equal(await page.evaluate("document.querySelectorAll('input[type=password]').length"),0,
      'Generated-password authorization must not ask the user to type that credential');
    await browser.click(page,'Continue');
    await browser.wait(page,"Array.from(document.querySelectorAll('[role]')).some(el=>(el.getAttribute('aria-label')||el.textContent||'').trim()==='Show my seed phrase')",{label:'authorized phrase screen'});
    await browser.click(page,'Show my seed phrase');
    const wordCount=await page.evaluate("Array.from(document.querySelectorAll('input')).filter(el=>/^\\d+\\.$/.test(el.getAttribute('aria-label')||'')).length");
    assert.ok([12,24].includes(wordCount),'The accessible fixture phrase must expose numbered fields');
    const words=[];
    for(let index=1;index<=wordCount;index++){
      await page.evaluate(`(()=>{const field=Array.from(document.querySelectorAll('input')).find(el=>el.getAttribute('aria-label')===${JSON.stringify(index+'.')});field.focus();field.click();return true;})()`);
      await page.evaluate('new Promise(resolve=>requestAnimationFrame(()=>requestAnimationFrame(resolve)))');
      await browser.wait(page,"/^[a-z]+$/.test(document.activeElement?.value||'')",{label:'focused fixture phrase field'});
      words.push(await page.evaluate('document.activeElement.value'));
    }
    phrase=words.join(' ');words.fill('');
    console.log('CHECK: fixture phrase word count and distinct count',phrase.split(' ').length,new Set(phrase.split(' ')).size);
    assert.ok([12,24].includes(phrase.split(' ').length),'The fixture phrase must have the expected word count');
    await page.evaluate(`__gleecReleaseProbe.testAddCanary(${JSON.stringify(phrase)});true`);
    await browser.click(page,'I saved my seed phrase');
    await browser.wait(page,buttonPresent('Confirm'),{label:'phrase confirmation choices'});
    await page.evaluate('window.__usedSeedChoices=new Set();true');
    for(const word of phrase.split(' ')){
      const selected=await page.evaluate(`(()=>{const element=Array.from(document.querySelectorAll('[role=button]')).find(el=>(el.getAttribute('aria-label')||el.textContent||'').trim()===${JSON.stringify(word)}&&!window.__usedSeedChoices.has(el.id));if(!element)return false;window.__usedSeedChoices.add(element.id);element.click();return true;})()`);
      assert.equal(selected,true,'A fixture confirmation word must be selectable');await delay(30);
    }
    await browser.click(page,'Confirm');
    await browser.wait(page,buttonPresent('I got it'),{label:'phrase confirmation saved'});
    assert.equal(await page.evaluate("document.querySelectorAll('input[type=password]:not([readonly])').length"),0);
    await browser.click(page,'I got it');
    assert.ok(virtual.counts.asserted>beforeBackup);
    await browser.wait(page,`(${recoverySummary}).then(value=>value.evidence==='phraseConfirmed'&&value.hasBackup)`,{label:'confirmed phrase evidence'});
    assert.equal((await page.evaluate(recoverySummary)).exportConfirmed,false);
    evidence.generatedPasswordBackup={phraseConfirmed:true,unknownCredentialNeverTyped:true,customPasswordNotRequired:true};
    console.log('PASS: generated-password wallet completes phrase confirmation through device authorization');
    assert.equal(ciphertext.includes(phrase),false);
    evidence.encryptedExport.plaintextPhraseAbsent=true;
    if(process.env.GLEEC_TEST_NARROW_AUTH==='true'){
      for(const diagnostic of consoleMessages){
        assert.equal(diagnostic.includes(phrase),false);
        assert.equal(diagnostic.includes(generatedCredential),false);
      }
      evidence.consoleCanaries={phraseLeaked:false,passwordLeaked:false};
      console.log('EVIDENCE',JSON.stringify(evidence));
      return;
    }

    await signOut(browser,page,{contend:true});await openImport(browser,page);
    await browser.fill(page,'Wallet name','Seed Restore');
    await browser.fill(page,'Enter seed phrase',phrase);
    await browser.click(page,'Continue');
    const restoreCredential='Unfunded-restore-fixture-42!';
    await browser.fill(page,'Wallet password',restoreCredential);
    await browser.fill(page,'Confirm password',restoreCredential);
    await browser.click(page,'Import');
    await browser.wait(page,buttonPresent('Seed Restore'),{timeout:60000,label:'phrase-restored wallet opened'});
    const seedIdentity=await page.evaluate(publicIdentity);
    assert.equal(seedIdentity.identity,originalIdentity.identity);
    assert.notEqual(seedIdentity.entryId,originalIdentity.entryId);
    evidence.seedRestoration={verifiedIdentityMatches:true,separateEntry:true,hdOptionsPreserved:true};
    console.log('PASS: separate seed-restored wallet preserves verified identity and derivation options');

    await signOut(browser,page);await openImport(browser,page);
    console.log('CHECK: encrypted-file import entry opened');
    await browser.upload(page,'Import encrypted wallet file',importFile);
    await browser.fill(page,'Wallet password',generatedCredential);
    await browser.click(page,'Import');
    await browser.wait(page,buttonPresent('File Restore'),{timeout:60000,label:'file-restored wallet opened'});
    const fileIdentity=await page.evaluate(publicIdentity);
    assert.equal(fileIdentity.identity,originalIdentity.identity);
    assert.notEqual(fileIdentity.entryId,originalIdentity.entryId);
    assert.notEqual(fileIdentity.entryId,seedIdentity.entryId);
    evidence.encryptedFileRestoration={verifiedIdentityMatches:true,separateEntry:true,hdOptionsPreserved:true};
    console.log('PASS: encrypted-file restoration independently preserves verified wallet identity');

    await browser.click(page,'Settings');await browser.click(page,'General');
    const beforeLogs=new Set(fs.readdirSync(browser.downloads));
    await browser.click(page,'Download logs');
    const logs=gunzipSync(fs.readFileSync(await newDownload(browser,beforeLogs,{suffix:'.txt.zip'}))).toString('utf8');
    for(const diagnostic of [logs,...consoleMessages]){
      assert.equal(diagnostic.includes(phrase),false,'A fixture phrase must not enter diagnostics');
      assert.equal(diagnostic.includes(generatedCredential),false,'A fixture password must not enter diagnostics');
    }
    evidence.secretDiagnostics={phraseCanaryLeaked:false,passwordCanaryLeaked:false,downloadBytes:Buffer.byteLength(logs)};
    console.log('PASS: backup/export/import console and support diagnostics exclude phrase and password canaries');
    console.log('EVIDENCE',JSON.stringify(evidence));
  }finally{generatedCredential=null;phrase=null;await browser.cleanup();}
}

if(require.main===module)main().catch(error=>{console.error(error.name,error.message);console.error(error.stack?.split('\n').slice(1).join('\n'));process.exitCode=1;});
module.exports={publicIdentity,recoverySummary,newDownload};
