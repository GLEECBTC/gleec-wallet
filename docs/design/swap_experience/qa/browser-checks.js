// Run as the function argument of Chrome DevTools evaluate_script on index.html.
// No live wallet calls. This validates only the illustrative HTML reference.
async () => {
  const $ = (selector) => document.querySelector(selector);
  const results = [];
  const check = (name, passed) => results.push({name, passed: !!passed});
  const click = (action) => $('[data-action="' + action + '"]').click();
  const toggle = (id, value) => {
    $('#' + id).checked = value;
    $('#' + id).dispatchEvent(new Event('change'));
  };
  const scenario = (value) => {
    $('#scenario').value = value;
    $('#scenario').dispatchEvent(new Event('change'));
  };
  toggle('play', false);
  toggle('reduce', false);
  $('#restart').click();
  check('Ready form', !!$('#amount') && $('#estimate').textContent === '$19.60');
  $('#amount').focus();
  $('#amount').value = '25';
  $('#amount').dispatchEvent(new Event('input', {bubbles: true}));
  check('Typing keeps focus and exact current estimate', document.activeElement === $('#amount') && $('#estimate').textContent === '$24.50');
  click('pick-to');
  check('Picker is one exclusive screen', !$('#amount') && !!$('#asset-search'));
  $('#asset-search').value = 'arb';
  $('#asset-search').dispatchEvent(new Event('input', {bubbles: true}));
  check('Picker search responds immediately', document.querySelectorAll('[data-asset]').length === 2);
  $('[data-asset="3"]').click();
  check('Selection returns and preserves dollars', $('#amount').value === '25' && $('#receive-card').textContent.includes('Arbitrum'));
  click('review');
  check('Review shows minimum, network and own recipient', $('#screen').textContent.includes('Minimum received') && $('#screen').textContent.includes('Arbitrum') && $('#screen').textContent.includes('Your wallet ·'));
  click('details');
  check('Expanded details become accessible', !$('#details-body').inert && $('[data-action="details"]').getAttribute('aria-expanded') === 'true');
  click('form');
  check('Returning preserves input', $('#amount').value === '25');
  scenario('slow');
  check('Slow quote is unknown, not zero', $('#estimate').textContent === '—' && $('#screen').textContent.includes('Still checking swap options'));
  scenario('failed');
  check('Failure preserves input and provides Retry', $('#amount').value === '25' && !!$('[data-action="retry"]'));
  scenario('changed');
  check('Changed terms require acceptance', !!$('[data-action="accept"]') && !$('[data-action="confirm"]'));
  click('accept');
  check('Accepted changes still require Confirm', !!$('[data-action="confirm"]') && $('#screen').textContent.includes('Review swap'));
  toggle('play', true);
  click('confirm');
  check('Starting does not claim receiving', $('#screen').textContent.includes('Starting your swap') && !$('#screen').textContent.includes('Receiving ETH'));
  click('wallet');
  await new Promise(resolve => setTimeout(resolve, 5900));
  check('Execution continues after returning to wallet', $('.wallet-swap').textContent.includes('Received ETH'));
  click('track');
  check('Reopening completion does not celebrate', !$('.hero-icon.complete') && $('#screen').textContent.includes('Updating wallet balance'));
  click('asset');
  check('Asset uses pending balance refresh', $('#screen').textContent.includes('Updating available balance'));
  scenario('completed');
  check('New completion has one effect', document.querySelectorAll('.hero-icon.complete').length === 1 && !$('.page.enter'));
  toggle('reduce', true);
  check('Reduced motion removes completion animation', getComputedStyle($('.hero-icon .token')).animationName === 'none');
  toggle('play', false);
  const geometry = ['ready', 'loading', 'slow', 'failed'].map(value => {
    scenario(value);
    return [$('#receive-card').offsetHeight, $('#quote-summary').offsetHeight, $('.primary').getBoundingClientRect().top].join(',');
  });
  check('Quote ready, pending and failed geometry stays fixed', new Set(geometry).size === 1);
  $('#restart').click();
  click('max');
  check('Fiat Max cannot exceed fixture funding', Number($('#amount').value) <= 50 * .999565);
  $('#restart').click();
  toggle('reduce', false);
  toggle('play', true);
  return {passed: results.filter(result => result.passed).length, total: results.length, results};
}
