import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import test from 'node:test';
import vm from 'node:vm';

// Execute the shipped asset, including its installed message handler, instead
// of maintaining a second implementation of the security check in the test.
const asset = readFileSync(
  new URL('../../assets/web_pages/bitrefill_widget.js', import.meta.url),
  'utf8',
);

function createWidget() {
  const sender = {};
  const elements = {
    'bitrefill-iframe': { contentWindow: sender, src: '' },
    'bitrefill-payment-banner': { style: { display: 'none' } },
    'bitrefill-email-banner': { style: { display: 'none' } },
  };
  const messages = [];
  const logs = [];
  const window = {
    location: { search: '', origin: 'https://wallet.example' },
    opener: {
      postMessage: (message, origin) => messages.push({ message, origin }),
    },
  };
  const context = vm.createContext({
    window,
    document: { getElementById: (id) => elements[id] },
    URLSearchParams,
    console: {
      log: (message) => logs.push(message),
      error: (message) => logs.push(message),
    },
  });
  vm.runInContext(asset, context, { filename: 'bitrefill_widget.js' });

  return {
    elements,
    messages,
    logs,
    send(data, overrides = {}) {
      window.onmessage({
        origin: 'https://embed.bitrefill.com',
        source: sender,
        data,
        ...overrides,
      });
    },
  };
}

const paymentIntent = {
  event: 'payment_intent',
  invoiceId: 'test-invoice',
  paymentUri: 'bitcoin:test-payment-address?amount=0.001',
  paymentMethod: 'bitcoin',
  paymentAmount: 0.001,
  paymentCurrency: 'BTC',
  paymentAddress: 'test-payment-address',
};

for (const representation of ['JSON string', 'object']) {
  test(`forwards a genuine payment intent as ${representation}`, () => {
    const widget = createWidget();
    widget.send(
      representation === 'JSON string'
        ? JSON.stringify(paymentIntent)
        : paymentIntent,
    );

    assert.deepEqual(widget.messages, [{
      message: JSON.stringify(paymentIntent),
      origin: 'https://wallet.example',
    }]);
    assert.deepEqual(widget.logs, [JSON.stringify(paymentIntent)]);
    assert.equal(widget.elements['bitrefill-payment-banner'].style.display, 'block');
    assert.equal(widget.elements['bitrefill-email-banner'].style.display, 'none');
  });
}

test('preserves invoice-created events and the email warning banner', () => {
  const widget = createWidget();
  const invoice = { ...paymentIntent, event: 'invoice_created', products: ['test-product'] };
  widget.send(JSON.stringify(invoice));

  assert.deepEqual(JSON.parse(widget.messages[0].message), invoice);
  assert.equal(widget.elements['bitrefill-email-banner'].style.display, 'block');
  assert.equal(widget.elements['bitrefill-payment-banner'].style.display, 'none');
});

for (const origin of [
  'https://attacker.example',
  'https://embed.bitrefill.com.attacker.example',
  'http://embed.bitrefill.com',
  'https://www.bitrefill.com',
  'https://embed.bitrefill.com:444',
  'null',
  '',
]) {
  test(`ignores payment events from untrusted origin ${JSON.stringify(origin)}`, () => {
    const widget = createWidget();
    widget.send(JSON.stringify(paymentIntent), { origin });
    assert.deepEqual(widget.messages, []);
    assert.deepEqual(widget.logs, []);
    assert.equal(widget.elements['bitrefill-payment-banner'].style.display, 'none');
  });
}

test('ignores messages from another Bitrefill window or a missing sender', () => {
  const widget = createWidget();
  for (const source of [{}, null, undefined]) {
    widget.send(JSON.stringify(paymentIntent), { source });
  }
  assert.deepEqual(widget.messages, []);
  assert.deepEqual(widget.logs, []);
});

test('requires a live checkout iframe', () => {
  const widget = createWidget();
  widget.elements['bitrefill-iframe'].contentWindow = null;
  widget.send(JSON.stringify(paymentIntent), { source: null });
  delete widget.elements['bitrefill-iframe'];
  widget.send(JSON.stringify(paymentIntent));
  assert.deepEqual(widget.messages, []);
});

test('ignores malformed and unrelated messages without throwing or logging', () => {
  const widget = createWidget();
  const circular = { event: 'payment_intent' };
  circular.self = circular;
  for (const data of [
    '{', '', 'null', '[]', 'true', '"message"',
    null, undefined, [], 42, true, {},
    { event: 'invoice_update', status: 'payment_detected' },
    { event: 'invoice_complete', deliveryStatus: 'all_delivered' },
    { event: 'payment_intent', amount: 1n }, circular,
  ]) {
    assert.doesNotThrow(() => widget.send(data));
  }
  assert.deepEqual(widget.messages, []);
  assert.deepEqual(widget.logs, []);
});
