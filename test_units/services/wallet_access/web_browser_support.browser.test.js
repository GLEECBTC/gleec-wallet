// Real compiled-app startup minimum, using disposable unfunded profiles only.
'use strict';
const assert=require('node:assert/strict');
const fs=require('node:fs');
const path=require('node:path');
const {LocalBrowser}=require('./web_release_test_driver.js');
const {probe,credentialsSummary,buttonPresent,virtualAuthenticator}=require('./web_credential_release.browser.test.js');

async function checkProtectedGate(){
  const browser=new LocalBrowser(path.resolve(__dirname,'../../..'));
  try{
    await browser.serve();await browser.launch();
    const page=await browser.page({initialize:probe});await browser.navigate(page);await browser.semantics(page);
    assert.equal(await page.evaluate('typeof gleecWalletBrowserSupport'),'object','Rebuild with the startup gate first');
    await browser.click(page,'Create a new wallet');
    await browser.wait(page,buttonPresent('Gleec Wallet'),{timeout:60000,label:'startup fixture wallet'});
    const provider=await virtualAuthenticator(browser,page);
    await browser.click(page,'Settings');await browser.click(page,'Security');await browser.click(page,'Set up local passkey');
    await browser.wait(page,`(${credentialsSummary}).then(value=>value.protections[0]==='passkeyPrf')`,{label:'protected startup fixture'});
    const before=await page.evaluate(credentialsSummary);
    const assertions=provider.counts.asserted;
    await page.send('Page.addScriptToEvaluateOnNewDocument',{source:"window.__fixtureLocks=navigator.locks;Object.defineProperty(navigator,'locks',{configurable:true,value:undefined});"});
    await browser.navigate(page);
    await browser.wait(page,"!!document.querySelector('#browser-support button')",{label:'actionable unsupported-browser message'});
    assert.equal(await page.evaluate("document.querySelector('#browser-support').textContent.includes('This check has not changed your wallet data')"),true);
    assert.equal(await page.evaluate("performance.getEntriesByType('resource').some(entry=>entry.name.endsWith('/main.dart.js')||entry.name.includes('/kdf/')&&entry.name.endsWith('.wasm'))"),false);
    assert.deepEqual(await page.evaluate(credentialsSummary),before);assert.equal(provider.counts.asserted,assertions);
    const screenshots=path.join(browser.root,'build/qa/screenshots/auth_browser_support');
    fs.mkdirSync(screenshots,{recursive:true});
    await page.send('Emulation.setEmulatedMedia',{features:[{name:'prefers-reduced-motion',value:'reduce'}]});
    assert.equal(await page.evaluate("getComputedStyle(document.querySelector('#loading img')).animationName"),'none');
    for(const [theme,width,height,scale] of [['light',1280,900,1],['dark',1280,900,1],['light',320,568,2],['dark',320,568,2]]){
      await page.send('Emulation.setDeviceMetricsOverride',{width,height,deviceScaleFactor:1,mobile:width<600});
      await page.evaluate(`document.body.classList.remove('light','dark');document.body.classList.add(${JSON.stringify(theme)});document.documentElement.style.fontSize=${JSON.stringify(scale*100+'%')};true`);
      const layout=await page.evaluate("({viewport:innerWidth,body:document.body.scrollWidth,panel:document.querySelector('#browser-support').scrollWidth,available:document.querySelector('#browser-support').clientWidth,buttonHeight:document.querySelector('#browser-support button').getBoundingClientRect().height})");
      assert.ok(layout.body<=layout.viewport+1&&layout.panel<=layout.available+1,'Browser support content must not overflow horizontally');
      assert.ok(layout.buttonHeight>=48);
      const screenshot=await page.send('Page.captureScreenshot',{format:'png'});
      fs.writeFileSync(path.join(screenshots,`${theme}-${width}-${scale}x.png`),Buffer.from(screenshot.data,'base64'));
    }
    await page.send('Emulation.setDeviceMetricsOverride',{width:1280,height:1000,deviceScaleFactor:1,mobile:false});
    await page.evaluate("document.documentElement.style.fontSize='100%';document.querySelector('#browser-support button').focus();true");
    assert.equal(await page.evaluate("document.activeElement===document.querySelector('#browser-support button')"),true);
    await page.evaluate("document.querySelector('#browser-support button').click();true");
    await browser.wait(page,"document.querySelector('#browser-support button')?.disabled===false",{label:'unsuccessful retry remains usable'});
    assert.deepEqual(await page.evaluate(credentialsSummary),before);
    await page.evaluate("Object.defineProperty(navigator,'locks',{configurable:true,value:window.__fixtureLocks});document.querySelector('#browser-support button').click();true");
    await browser.semantics(page);
    await browser.wait(page,buttonPresent('Gleec Wallet'),{timeout:60000,label:'original protected wallet after capability restored'});
    assert.equal(provider.counts.asserted,assertions+1);assert.deepEqual(await page.evaluate(credentialsSummary),before);
    console.log('PASS: missing coordination blocks before Flutter/KDF, preserves protected data, and Retry resumes one existing passkey unlock');
  }finally{await browser.cleanup();}
}

async function checkNoPasskeys(){
  const browser=new LocalBrowser(path.resolve(__dirname,'../../..'));
  try{
    await browser.serve();await browser.launch();
    const page=await browser.page({initialize:probe+"\nObject.defineProperty(window,'PublicKeyCredential',{configurable:true,value:undefined});"});
    await browser.navigate(page);await browser.semantics(page);
    console.log('CHECK: app loaded without passkey capability');
    assert.equal(await page.evaluate('!!document.querySelector("#browser-support")'),false);
    await browser.wait(page,buttonPresent('Create a new wallet'),{label:'inline no-passkey creation entry'});
    console.log('CHECK: no-passkey creation entry opened');
    await browser.click(page,'Create a new wallet');
    await browser.wait(page,buttonPresent('Gleec Wallet'),{timeout:60000,label:'instant creation without passkey support'});
    const vault=await page.evaluate(credentialsSummary);
    assert.equal(vault.active,1);assert.equal(vault.unattended,1);assert.deepEqual(vault.protections,['browserLocal']);
    console.log('PASS: missing passkey support still permits durable instant browser-local creation');
  }finally{await browser.cleanup();}
}
if(require.main===module)(async()=>{await checkProtectedGate();await checkNoPasskeys();})().catch(error=>{console.error(error.name,error.message);console.error(error.stack?.split('\n').slice(1).join('\n'));process.exitCode=1;});
