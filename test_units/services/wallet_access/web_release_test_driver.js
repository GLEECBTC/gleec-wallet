'use strict';

// Disposable local browser integration support. Never attaches to a user profile.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const http = require('node:http');
const os = require('node:os');
const path = require('node:path');
const { spawn } = require('node:child_process');
const { createHash } = require('node:crypto');

const delay = milliseconds => new Promise(resolve => setTimeout(resolve, milliseconds));

class LocalBrowser {
  constructor(root, { port = 18768, debugPort = 9223 } = {}) {
    this.root = root;
    this.port = port;
    this.debugPort = debugPort;
    this.base = `http://localhost:${port}/`;
    this.profile = fs.mkdtempSync(path.join(os.tmpdir(), 'gleec-browser-release-'));
    this.events = new Set();
    this.pending = new Map();
    this.sequence = 0;
    this.downloads = path.join(this.profile, 'test-downloads');
    fs.mkdirSync(this.downloads);
  }

  async serve() {
    const hosted = process.env.GLEEC_TEST_HOSTED_URL;
    if (hosted) {
      const target = new URL(hosted);
      assert.equal(target.protocol, 'https:');
      assert.match(target.hostname, /^(?:walletrc|gleec-wallet-official)--pull-\d+-merge-(?:[a-f0-9]{7,40}-)?[a-z0-9]{6,40}\.web\.app$/);
      assert.equal(target.pathname, '/');
      assert.equal(target.search + target.hash + target.username + target.password + target.port, '');
      const expected = process.env.GLEEC_TEST_EXPECTED_BUILD_SHA256;
      assert.match(expected ?? '', /^[a-f0-9]{64}$/, 'Hosted checks require an independently verified bundle digest');
      this.base = target.href;
      const response = await fetch(new URL('main.dart.js', this.base));
      assert.equal(response.status, 200);
      const actual = createHash('sha256').update(Buffer.from(await response.arrayBuffer())).digest('hex');
      assert.equal(actual, expected, 'The hosted app must match the approved build');
      this.buildFingerprint = actual;
      return;
    }
    const source = path.join(this.root, 'build/web');
    assert.ok(fs.existsSync(path.join(source, 'main.dart.js')), 'Build the release app first');
    assert.equal(fs.existsSync(path.join(source, 'assets/assets/debug_data.json')),false,
      'Stop: rebuild with the explicit public asset manifest before browser validation');
    for(const name of ['AssetManifest.bin','AssetManifest.json','AssetManifest.bin.json']){
      const filename=path.join(source,'assets',name);
      if(!fs.existsSync(filename))continue;
      let manifest=fs.readFileSync(filename);
      if(name.endsWith('.bin.json'))manifest=Buffer.from(JSON.parse(manifest.toString('utf8')),'base64');
      assert.equal(manifest.includes(Buffer.from('assets/debug_data.json')),false,
        'Stop: the compiled asset manifest still advertises a private fixture');
    }
    const digest = filename => createHash('sha256').update(fs.readFileSync(filename)).digest('hex');
    this.buildFingerprint = digest(path.join(source, 'main.dart.js'));
    if(process.env.GLEEC_TEST_EXPECTED_BUILD_SHA256){
      assert.equal(this.buildFingerprint,process.env.GLEEC_TEST_EXPECTED_BUILD_SHA256,
        'Use only the exact release build approved for this regression round');
    }
    const build = path.join(this.profile, 'compiled-fixture');
    fs.cpSync(source, build, {recursive:true,dereference:true});
    assert.equal(digest(path.join(source, 'main.dart.js')),this.buildFingerprint,
      'Wait for the shared Flutter build to finish before taking a fixture snapshot');
    assert.equal(digest(path.join(build, 'main.dart.js')),this.buildFingerprint);
    const hosting = JSON.parse(fs.readFileSync(path.join(this.root, 'firebase.json'))).hosting;
    const headers = Object.fromEntries(hosting.headers.find(item => item.source === '**').headers
      .map(item => [item.key, item.value]));
    const mime = { '.html':'text/html', '.js':'text/javascript', '.json':'application/json',
      '.wasm':'application/wasm', '.svg':'image/svg+xml', '.png':'image/png', '.webp':'image/webp',
      '.jpg':'image/jpeg', '.ttf':'font/ttf', '.otf':'font/otf', '.woff2':'font/woff2', '.css':'text/css' };
    this.server = http.createServer((request, response) => {
      let filename;
      try {
        const pathname = decodeURIComponent(new URL(request.url, this.base).pathname);
        filename = path.resolve(build, `.${pathname}`);
        if (!filename.startsWith(`${build}${path.sep}`) && filename !== build) throw new Error('Path');
        if (fs.existsSync(filename) && fs.statSync(filename).isDirectory()) filename = path.join(filename, 'index.html');
        if (!fs.existsSync(filename) && !path.extname(filename)) filename = path.join(build, 'index.html');
        if (!fs.existsSync(filename)) { response.writeHead(404, headers); response.end(); return; }
      } catch (_) { response.writeHead(400); response.end(); return; }
      response.writeHead(200, { ...headers, 'Content-Type': filename.endsWith('apple-app-site-association')
        ? 'application/json' : mime[path.extname(filename)] ?? 'application/octet-stream',
        'Cache-Control':'no-cache', 'Content-Length':fs.statSync(filename).size });
      fs.createReadStream(filename).pipe(response);
    });
    await new Promise((resolve, reject) => { this.server.once('error', reject); this.server.listen(this.port, '127.0.0.1', resolve); });
  }

  async launch() {
    const binary = process.env.GLEEC_TEST_CHROME ?? (process.platform === 'darwin'
      ? '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome' : '/usr/bin/google-chrome');
    assert.ok(fs.existsSync(binary), 'Set GLEEC_TEST_CHROME to an installed Chrome executable');
    this.process = spawn(binary, ['--headless=new', '--no-first-run', '--no-default-browser-check',
      '--disable-background-networking', '--disable-component-update', '--disable-sync',
      `--remote-debugging-port=${this.debugPort}`, `--user-data-dir=${this.profile}`, 'about:blank'],
    { stdio:'ignore' });
    let version;
    for (let count=0;count<100;count++) {
      if (this.process.exitCode != null) throw new Error('Isolated Chrome exited during startup');
      try { version=await (await fetch(`http://127.0.0.1:${this.debugPort}/json/version`)).json(); break; }
      catch (_) { await delay(100); }
    }
    assert.ok(version, 'Isolated Chrome must expose its local debugging endpoint');
    this.version = version.Browser;
    this.socket = new WebSocket(version.webSocketDebuggerUrl);
    this.socket.addEventListener('message', ({data}) => {
      const message=JSON.parse(data);
      if (message.id) {
        const request=this.pending.get(message.id); this.pending.delete(message.id);
        clearTimeout(request?.timer);
        if (message.error) request?.reject(new Error(`CDP command failed (${request.method}, ${message.error.code})`));
        else request?.resolve(message.result);
      } else for (const listener of this.events) listener(message);
    });
    await new Promise((resolve,reject)=>{this.socket.addEventListener('open',resolve,{once:true});this.socket.addEventListener('error',reject,{once:true});});
    await this.command('Browser.setDownloadBehavior', {behavior:'allow', downloadPath:this.downloads, eventsEnabled:true});
  }

  command(method, params={}, sessionId) {
    return new Promise((resolve,reject)=>{
      const id=++this.sequence;
      const timer=setTimeout(()=>{this.pending.delete(id);reject(new Error(`CDP command timeout: ${method}`));},30000);
      this.pending.set(id,{resolve,reject,timer,method});
      this.socket.send(JSON.stringify({id,method,params,...(sessionId?{sessionId}:{})}));
    });
  }

  async page({ initialize, existing = false }={}) {
    const targets=existing ? (await this.command('Target.getTargets')).targetInfos : [];
    const target=targets.find(item=>item.type==='page'&&item.url.startsWith(this.base)) ??
      await this.command('Target.createTarget',{url:'about:blank'});
    const {sessionId}=await this.command('Target.attachToTarget',{targetId:target.targetId,flatten:true});
    const send=(method,params)=>this.command(method,params,sessionId);
    const evaluate=async expression=>{
      const result=await send('Runtime.evaluate',{expression,awaitPromise:true,returnByValue:true,userGesture:true});
      if(result.exceptionDetails)throw new Error(`Browser fixture evaluation failed (${result.exceptionDetails.exception?.className??'unknown'})`);
      return result.result.value;
    };
    const page={targetId:target.targetId,sessionId,send,evaluate};
    this.events.add(message=>{
      if(message.sessionId===sessionId&&message.method==='Page.javascriptDialogOpening'&&message.params.type==='beforeunload') {
        send('Page.handleJavaScriptDialog',{accept:true}).catch(()=>{});
      }
    });
    await send('Page.enable'); await send('Runtime.enable'); await send('Network.enable');
    await send('Page.setLifecycleEventsEnabled',{enabled:true});
    await send('Emulation.setDeviceMetricsOverride',{width:1280,height:1000,deviceScaleFactor:1,mobile:false});
    await send('Emulation.setFocusEmulationEnabled',{enabled:true});
    await send('Page.bringToFront');
    if(initialize) await send('Page.addScriptToEvaluateOnNewDocument',{source:initialize});
    return page;
  }

  async navigate(page, url=this.base) {
    const readyLoaders=new Set();
    const listener=message=>{
      if(message.sessionId===page.sessionId&&message.method==='Page.lifecycleEvent'&&
        ['DOMContentLoaded','load'].includes(message.params.name))readyLoaders.add(message.params.loaderId);
    };
    this.events.add(listener);
    try {
      const response=await page.send('Page.navigate',{url});
      assert.equal(response.errorText,undefined,'Local fixture navigation must succeed');
      // A navigation response can precede document replacement. Never let the
      // next semantic lookup operate on the departing wallet's stale DOM.
      if(response.loaderId){
        const deadline=performance.now()+30000;
        while(!readyLoaders.has(response.loaderId)&&performance.now()<deadline)await delay(50);
        assert.ok(readyLoaders.has(response.loaderId),'The new local document must finish parsing');
      }
    }finally{this.events.delete(listener);}
  }

  async wait(page, expression, {timeout=30000, label='browser condition', accept}={}) {
    const until=performance.now()+timeout;
    while(performance.now()<until){
      try {const result=await page.evaluate(expression);if(result&&(!accept||accept(result)))return result;} catch(_) {}
      await delay(100);
    }
    throw new Error(`Timed out waiting for ${label}`);
  }

  async semantics(page) {
    await this.wait(page,"document.querySelector('flt-semantics-placeholder')||document.querySelector('[role=button]')",{label:'Flutter semantics'});
    await page.evaluate("document.querySelector('flt-semantics-placeholder')?.click(); true");
  }

  async buttons(page) {
    return page.evaluate("Array.from(document.querySelectorAll('[role=button]')).map(el=>el.getAttribute('aria-label')||el.textContent||'')");
  }

  async click(page, label, {pointer=false}={}) {
    const expression=`Array.from(document.querySelectorAll('[role=button],[role=switch],[role=checkbox]')).find(el=>(el.getAttribute('aria-label')||el.textContent||'').trim()===${JSON.stringify(label)})`;
    if(!pointer){
      // Resolve and activate in one task so a rebuild cannot detach the node
      // between lookup and the semantics action.
      await this.wait(page,`(()=>{const element=${expression};if(!element||element.getAttribute('aria-disabled')==='true')return false;element.click();return true;})()`,{label:`button ${label}`});
      return;
    }
    // Use genuine pointer activation for the system-credential handoff. Flutter
    // can expose a route's semantics before its transition accepts input. Wait
    // for a stable painted target, then activate exactly once, without retrying
    // an authentication action. This adds no delay to the application itself.
    let candidate;
    let stableSince=0;
    const settled=await this.wait(page,`(()=>{
      const element=${expression};
      if(!element||element.getAttribute('aria-disabled')==='true'||element.closest('[aria-hidden=true]'))return false;
      const r=element.getBoundingClientRect();const x=r.x+r.width/2,y=r.y+r.height/2;
      if(r.width<=0||r.height<=0||x<0||y<0||x>=innerWidth||y>=innerHeight)return false;
      const hit=document.elementFromPoint(x,y);
      return hit&&(hit===element||element.contains(hit))?{x,y,id:element.id}:false;
    })()`,{label:`settled button ${label}`,accept:point=>{
      const same=candidate&&point.id===candidate.id&&Math.abs(point.x-candidate.x)<0.5&&Math.abs(point.y-candidate.y)<0.5;
      if(!same){candidate=point;stableSince=performance.now();return false;}
      return performance.now()-stableSince>=500;
    }});
    await page.send('Input.dispatchMouseEvent',{type:'mousePressed',button:'left',clickCount:1,x:settled.x,y:settled.y});
    await page.send('Input.dispatchMouseEvent',{type:'mouseReleased',button:'left',clickCount:1,x:settled.x,y:settled.y});
  }

  async fill(page, label, value) {
    const selector=`Array.from(document.querySelectorAll('input,textarea,[role=textbox]')).find(el=>
      (el.getAttribute('aria-label')||el.getAttribute('placeholder')||'').split('\\n').some(part=>part.trim()===${JSON.stringify(label)})&&!el.readOnly)`;
    try {
      await this.wait(page,`(()=>{const field=${selector};if(!field)return false;field.focus();return true;})()`,{label:`editable fixture field: ${label}`});
    } catch (error) {
      // Diagnose shape/label matching only. Never return field values or text.
      const shape = await page.evaluate(`Array.from(document.querySelectorAll('input,textarea,[role=textbox]')).map(el=>({tag:el.tagName,readOnly:el.readOnly===true,labelMatches:(el.getAttribute('aria-label')||'')===${JSON.stringify(label)},labelContains:(el.getAttribute('aria-label')||'').includes(${JSON.stringify(label)}),placeholderMatches:(el.getAttribute('placeholder')||'')===${JSON.stringify(label)}}))`);
      console.error('Fixture field shape', JSON.stringify(shape));
      throw error;
    }
    await delay(50);
    const modifiers=process.platform==='darwin'?4:2;
    await page.send('Input.dispatchKeyEvent',{type:'keyDown',key:'a',code:'KeyA',modifiers});
    await page.send('Input.dispatchKeyEvent',{type:'keyUp',key:'a',code:'KeyA',modifiers});
    await page.send('Input.insertText',{text:value});
    await this.wait(page,`(${selector})?.value===${JSON.stringify(value)}`,{label:'fixture field accepted input'});
  }

  async upload(page, label, filename) {
    await this.wait(page,`Array.from(document.querySelectorAll('[role=button]')).some(el=>(el.getAttribute('aria-label')||el.textContent||'').trim()===${JSON.stringify(label)})`,{label:`file upload control ${label}`});
    await page.send('Page.setInterceptFileChooserDialog',{enabled:true});
    let listener,timer;
    const chooser=new Promise((resolve,reject)=>{
      timer=setTimeout(()=>{this.events.delete(listener);reject(new Error('Fixture file chooser did not open'));},30000);
      listener=message=>{if(message.sessionId===page.sessionId&&message.method==='Page.fileChooserOpened'){
        clearTimeout(timer);this.events.delete(listener);resolve(message.params);
      }};
      this.events.add(listener);
    });
    // Attach rejection handling immediately while the async click is pending.
    // Any failure must reach the caller's cleanup instead of terminating Node.
    chooser.catch(()=>{});
    try {
      await this.click(page,label);
      const event=await chooser;
      assert.ok(event.backendNodeId,'The fixture upload must come from the app file input');
      await page.send('DOM.setFileInputFiles',{files:[filename],backendNodeId:event.backendNodeId});
    } finally {clearTimeout(timer);this.events.delete(listener);await page.send('Page.setInterceptFileChooserDialog',{enabled:false});}
  }

  async stopBrowser() {
    if(!this.process)return;
    if(this.process.exitCode==null) {
      await this.command('Browser.close').catch(()=>{});
      for(let count=0;count<100&&this.process.exitCode==null;count++)await delay(100);
      if(this.process.exitCode==null)this.process.kill('SIGTERM');
    }
    this.socket?.close(); this.process=null;
    for(const request of this.pending.values()){clearTimeout(request.timer);request.reject(new Error('Isolated browser stopped'));}
    this.pending.clear(); this.events.clear();
  }

  async cleanup() {
    await this.stopBrowser();
    if(this.server)await new Promise(resolve=>this.server.close(resolve));
    assert.ok(path.basename(this.profile).startsWith('gleec-browser-release-'));
    fs.rmSync(this.profile,{recursive:true,force:true});
  }
}

module.exports={LocalBrowser,delay};
