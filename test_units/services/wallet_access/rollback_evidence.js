'use strict';

// Release evidence binds all served bytes and the exact executing test helpers.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const {createHash} = require('node:crypto');
const digest = bytes => createHash('sha256').update(bytes).digest('hex');

function directoryDigest(root) {
  const files = [];
  function visit(directory) {
    for (const entry of fs.readdirSync(directory, {withFileTypes: true})) {
      const filename = path.join(directory, entry.name);
      assert.equal(entry.isSymbolicLink(), false, 'Served artifacts must not contain symlinks');
      if (entry.isDirectory()) visit(filename);
      else {
        assert.ok(entry.isFile(), 'Served artifacts must contain only ordinary files');
        const bytes = fs.readFileSync(filename);
        files.push({bytes: bytes.length, path: path.relative(root, filename).split(path.sep).join('/'), sha256: digest(bytes)});
      }
    }
  }
  visit(root);
  files.sort((a, b) => a.path < b.path ? -1 : a.path > b.path ? 1 : 0);
  return digest(JSON.stringify(files));
}

function toolsFingerprint(harness) {
  const root = path.resolve(__dirname, '../../..');
  const names = [harness, 'rollback_evidence.js', 'web_release_test_driver.js',
    'web_credential_release.browser.test.js', 'web_wallet_recovery.browser.test.js'];
  return names.sort().map(name => {
    const filename = path.join(__dirname, name);
    return {path: path.relative(root, filename).split(path.sep).join('/'), sha256: digest(fs.readFileSync(filename))};
  });
}

module.exports = {directoryDigest, toolsFingerprint};
