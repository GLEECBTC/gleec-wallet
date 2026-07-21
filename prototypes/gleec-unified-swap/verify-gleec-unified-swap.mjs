#!/usr/bin/env node

/**
 * Read-only regression gate for the Gleec Unified Swap design artifact.
 *
 * This script intentionally uses only Node.js built-ins. It reads the design
 * artifact and its QA record, prints every failed assertion, and never writes
 * to either input file.
 *
 * Usage:
 *   node verify-gleec-unified-swap.mjs
 *   node verify-gleec-unified-swap.mjs path/to/artifact.html path/to/qa.md
 *   node verify-gleec-unified-swap.mjs --json
 */

import fs from 'node:fs';
import path from 'node:path';
import process from 'node:process';
import vm from 'node:vm';
import crypto from 'node:crypto';
import { fileURLToPath } from 'node:url';

const scriptDirectory = path.dirname(fileURLToPath(import.meta.url));
if (process.argv.includes('--help') || process.argv.includes('-h')) {
  process.stdout.write([
    'Usage:',
    '  node verify-gleec-unified-swap.mjs [artifact.html] [qa.md] [--json]',
    '',
    'With no paths, the verifier reads gleec-unified-swap.html and',
    'gleec-unified-swap-qa.md from its own directory. It never writes inputs.',
    '',
  ].join('\n'));
  process.exit(0);
}
const positional = process.argv.slice(2).filter((argument) => argument !== '--json');
const jsonOutput = process.argv.includes('--json');
const artifactPath = path.resolve(positional[0] || path.join(scriptDirectory, 'gleec-unified-swap.html'));
const qaPath = path.resolve(positional[1] || path.join(scriptDirectory, 'gleec-unified-swap-qa.md'));

const failures = [];
const warnings = [];
const passes = [];

function result(collection, id, message, detail = undefined) {
  collection.push({ id, message, ...(detail === undefined ? {} : { detail }) });
}

function fail(id, message, detail) {
  result(failures, id, message, detail);
}

function warn(id, message, detail) {
  result(warnings, id, message, detail);
}

function pass(id, message, detail) {
  result(passes, id, message, detail);
}

function assert(id, condition, failureMessage, successMessage = failureMessage, detail = undefined) {
  if (condition) pass(id, successMessage, detail);
  else fail(id, failureMessage, detail);
}

function readRequired(filePath, label) {
  try {
    return fs.readFileSync(filePath, 'utf8');
  } catch (error) {
    fail(`input.${label}`, `Cannot read ${label}: ${filePath}`, error.message);
    return null;
  }
}

const artifact = readRequired(artifactPath, 'artifact');
const qa = readRequired(qaPath, 'qa');

if (artifact === null || qa === null) {
  printResults();
  process.exitCode = 2;
} else {
  await verifyArtifact(artifact, qa);
  printResults();
  process.exitCode = failures.length === 0 ? 0 : 1;
}

function lineNumberFor(source, index) {
  return source.slice(0, Math.max(0, index)).split('\n').length;
}

function sourceMatches(source, expression) {
  return [...source.matchAll(expression)].map((match) => ({
    text: match[0].replace(/\s+/g, ' ').trim(),
    line: lineNumberFor(source, match.index ?? 0),
  }));
}

function sha256(value) {
  return crypto.createHash('sha256').update(value).digest('hex');
}

function normalizeId(value) {
  return String(value ?? '').toLowerCase().replace(/[^a-z0-9]+/g, '');
}

function parseAmount(value) {
  if (typeof value === 'number') return Number.isFinite(value) ? value : null;
  if (typeof value !== 'string') return null;
  const cleaned = value.replace(/[,\s$€£]/g, '').match(/-?\d+(?:\.\d+)?/);
  if (!cleaned) return null;
  const number = Number(cleaned[0]);
  return Number.isFinite(number) ? number : null;
}

function nearlyEqual(left, right, epsilon = 0.005) {
  return Math.abs(left - right) <= epsilon;
}

function extractBalanced(source, startIndex) {
  const opening = source[startIndex];
  const closing = opening === '{' ? '}' : opening === '[' ? ']' : opening === '(' ? ')' : null;
  if (!closing) return null;

  const stack = [closing];
  let quote = null;
  let escaped = false;
  let lineComment = false;
  let blockComment = false;

  for (let index = startIndex + 1; index < source.length; index += 1) {
    const character = source[index];
    const next = source[index + 1];

    if (lineComment) {
      if (character === '\n') lineComment = false;
      continue;
    }
    if (blockComment) {
      if (character === '*' && next === '/') {
        blockComment = false;
        index += 1;
      }
      continue;
    }
    if (quote) {
      if (escaped) {
        escaped = false;
      } else if (character === '\\') {
        escaped = true;
      } else if (character === quote) {
        quote = null;
      }
      continue;
    }
    if (character === '/' && next === '/') {
      lineComment = true;
      index += 1;
      continue;
    }
    if (character === '/' && next === '*') {
      blockComment = true;
      index += 1;
      continue;
    }
    if (character === '\'' || character === '"' || character === '`') {
      quote = character;
      continue;
    }
    if (character === '{') stack.push('}');
    else if (character === '[') stack.push(']');
    else if (character === '(') stack.push(')');
    else if (character === stack.at(-1)) {
      stack.pop();
      if (stack.length === 0) return source.slice(startIndex, index + 1);
    }
  }
  return null;
}

function extractInitializer(source, names) {
  for (const name of names) {
    const expression = new RegExp(`(?:const|let|var)\\s+${name.replace(/[.*+?^${}()|[\\]\\]/g, '\\$&')}\\s*=`, 'm');
    const match = expression.exec(source);
    if (!match) continue;
    let cursor = (match.index ?? 0) + match[0].length;
    while (/\s/.test(source[cursor] ?? '')) cursor += 1;
    const literal = extractBalanced(source, cursor);
    if (literal) return { name, literal, line: lineNumberFor(source, match.index ?? 0) };
  }
  return null;
}

function evaluateLiteral(extracted) {
  if (!extracted) return null;
  try {
    return vm.runInNewContext(`(${extracted.literal})`, Object.create(null), {
      timeout: 750,
      displayErrors: false,
    });
  } catch (error) {
    fail(
      `fixtures.${extracted.name}.parse`,
      `The ${extracted.name} fixture is not a self-contained data literal.`,
      `Line ${extracted.line}: ${error.message}`,
    );
    return null;
  }
}

function extractFunction(source, name) {
  const expression = new RegExp(`(?:async\\s+)?function\\s+${name.replace(/[.*+?^${}()|[\\]\\]/g, '\\$&')}\\s*\\(`, 'm');
  const match = expression.exec(source);
  if (!match) return null;
  const parameterStart = source.indexOf('(', match.index ?? 0);
  const parameters = parameterStart >= 0 ? extractBalanced(source, parameterStart) : null;
  if (!parameters) return null;
  let brace = parameterStart + parameters.length;
  while (/\s/.test(source[brace] ?? '')) brace += 1;
  if (source[brace] !== '{') return null;
  const body = brace >= 0 ? extractBalanced(source, brace) : null;
  return body ? source.slice(match.index ?? 0, brace) + body : null;
}

function evaluateFunction(source, name, sandbox = Object.create(null)) {
  const extracted = extractFunction(source, name);
  if (!extracted) return { extracted: null, value: null, error: null };
  try {
    const value = vm.runInNewContext(`(${extracted})`, sandbox, {
      timeout: 750,
      displayErrors: false,
    });
    return { extracted, value, error: null };
  } catch (error) {
    return { extracted, value: null, error };
  }
}

function createFakeScheduler() {
  let clock = 0;
  let nextHandle = 1;
  const tasks = new Map();

  function schedule(callback, delay = 0) {
    if (typeof callback !== 'function') throw new TypeError('Scheduled work must be a function.');
    const normalizedDelay = Number(delay);
    const handle = nextHandle;
    nextHandle += 1;
    tasks.set(handle, {
      handle,
      callback,
      delay: Number.isFinite(normalizedDelay) ? normalizedDelay : 0,
      dueAt: clock + (Number.isFinite(normalizedDelay) ? normalizedDelay : 0),
      cancelled: false,
      ran: false,
    });
    return handle;
  }

  function cancelScheduled(handle) {
    const task = tasks.get(handle);
    if (task) task.cancelled = true;
  }

  function matching(delay, { includeCancelled = false, includeRan = false } = {}) {
    return [...tasks.values()]
      .filter((task) => task.delay === delay)
      .filter((task) => includeCancelled || !task.cancelled)
      .filter((task) => includeRan || !task.ran)
      .sort((left, right) => left.handle - right.handle);
  }

  function run(task, { force = false } = {}) {
    if (!task || task.ran || (task.cancelled && !force)) return false;
    task.ran = true;
    clock = Math.max(clock, task.dueAt);
    task.callback();
    return true;
  }

  function runFirst(delay, options = {}) {
    const candidates = matching(delay, {
      includeCancelled: Boolean(options.force),
      includeRan: false,
    });
    const task = options.newest ? candidates.at(-1) : candidates[0];
    return { task, ran: run(task, options) };
  }

  function dropFirst(delay, { newest = false } = {}) {
    const candidates = matching(delay);
    const task = newest ? candidates.at(-1) : candidates[0];
    if (task) task.cancelled = true;
    return task;
  }

  return {
    schedule,
    cancelScheduled,
    matching,
    run,
    runFirst,
    dropFirst,
    tasks,
  };
}

function quoteStateOf(value) {
  if (typeof value === 'string') return value === 'quote-timeout' ? 'timeout' : value;
  if (!value || typeof value !== 'object') return null;
  for (const key of ['status', 'state', 'entry', 'phase', 'outcome', 'value']) {
    if (typeof value[key] === 'string') return value[key] === 'quote-timeout' ? 'timeout' : value[key];
  }
  return null;
}

function findNamedObjectLiteral(source, name) {
  if (!source) return null;
  const escaped = name.replace(/[.*+?^${}()|[\\]\\]/g, '\\$&');
  const expression = new RegExp(`(?:["']${escaped}["']|\\b${escaped}\\b)\\s*:\\s*`, 'm');
  const match = expression.exec(source);
  if (!match) return null;
  let cursor = (match.index ?? 0) + match[0].length;
  while (/\s/.test(source[cursor] ?? '')) cursor += 1;
  return source[cursor] === '{' ? extractBalanced(source, cursor) : null;
}

async function verifyArtifact(source, qaSource) {
  verifyUtf8(source);
  verifyLocalAssets(source);
  verifyForbiddenTerminology(source);
  verifyNavigationScaling(source);
  verifySidePanelSemantics(source);
  verifyProgressActions(source);
  verifyKnownBadValues(source);
  verifyWarningStates(source);
  verifyInteractions(source);
  const fixtures = verifyJourneyFixtures(source);
  verifyPrototypeFlows(source, fixtures);
  verifyRuntimeContracts(source);
  verifyPrototypeDataContracts(source, fixtures);
  await verifyClipboardContract(source);
  verifyEvidenceManifest(qaSource);
  verifyQuoteEvaluationController(source);
  verifyRemediatedUiContracts(source);
  verifyQaResult(qaSource, source);
  verifyRemediationCopy(source);
}

function verifyUtf8(source) {
  const hasUtf8 = /<meta\b[^>]*(?:charset\s*=\s*["']?utf-?8|content\s*=\s*["'][^"']*charset\s*=\s*utf-?8)/i.test(source);
  assert('markup.utf8', hasUtf8, 'Missing explicit UTF-8 metadata.', 'Explicit UTF-8 metadata is present.');
}

function verifyLocalAssets(source) {
  const styleBlocks = [...source.matchAll(/<style\b[^>]*>([\s\S]*?)<\/style>/gi)].map((match) => match[1]);
  const css = styleBlocks.join('\n');
  const remoteImports = [
    ...sourceMatches(css, /@import\s+(?:url\(\s*)?["']?https?:\/\/[^;)'"\s]+[^;]*/gi),
    ...sourceMatches(css, /url\(\s*["']?https?:\/\/[^)'"\s]+["']?\s*\)/gi),
    ...sourceMatches(source, /<link\b(?=[^>]*\b(?:rel\s*=\s*["'](?:stylesheet|preload)["']|as\s*=\s*["']font["']))(?=[^>]*\bhref\s*=\s*["']https?:\/\/)[^>]*>/gi),
  ];
  assert(
    'assets.local-fonts-icons',
    remoteImports.length === 0,
    'Remote font or icon imports remain; bundle them locally or use local/inline assets.',
    'No remote font or icon imports are present.',
    remoteImports.slice(0, 8),
  );
}

function verifyForbiddenTerminology(source) {
  const forbidden = [
    ['Li.Fi', /\bli\s*\.?\s*fi\b/gi],
    ['routed by', /\brouted\s+by\b/gi],
    ['route provided by', /\broute\s+provided\s+by\b/gi],
    ['Main account', /\bmain\s+account\b/gi],
    ['Connected account', /\bconnected\s+account\b/gi],
    ['multi-account', /\bmulti[\s-]+account\b/gi],
    ['account selector', /\baccount\s+selector\b/gi],
  ];
  const matches = forbidden.flatMap(([term, expression]) =>
    sourceMatches(source, expression).map((match) => ({ term, ...match })),
  );
  assert(
    'copy.forbidden-terminology',
    matches.length === 0,
    'Forbidden provider or account terminology appears in the artifact.',
    'No forbidden provider or account terminology is present.',
    matches.slice(0, 12),
  );
}

function verifyNavigationScaling(source) {
  const styleBlocks = [...source.matchAll(/<style\b[^>]*>([\s\S]*?)<\/style>/gi)].map((match) => match[1]);
  const violations = [];
  for (const css of styleBlocks) {
    for (const match of css.matchAll(/([^{}]+)\{([^{}]*)\}/g)) {
      const selector = match[1].trim();
      const declarations = match[2];
      if (/(?:nav|navigation)/i.test(selector) && /font-size\s*:\s*0(?:\D|$)/i.test(declarations)) {
        violations.push({ selector, line: lineNumberFor(source, source.indexOf(match[0])) });
      }
    }
  }
  assert(
    'accessibility.navigation-labels',
    violations.length === 0,
    'Navigation labels are hidden with font-size: 0.',
    'Navigation labels remain visible at large text sizes.',
    violations,
  );
}

function verifySidePanelSemantics(source) {
  const reviewFunction = extractFunction(source, 'renderReviewPreview') ?? '';
  const optionsFunction = extractFunction(source, 'renderOptionsSheet') ?? '';
  const pickerFunctions = ['renderAssetSheet', 'renderAddressSheet', 'renderRecipientSheet']
    .map((name) => extractFunction(source, name) ?? '')
    .join('\n');
  const sidePanelSource = [reviewFunction, optionsFunction, pickerFunctions].join('\n');
  const violations = sourceMatches(sidePanelSource, /aria-modal\s*=\s*["']true["']/gi);
  const explicitlyMarked = sourceMatches(
    source,
    /<[^>]+(?:data-surface\s*=\s*["'](?:side-panel|side-sheet)["']|class\s*=\s*["'][^"']*(?:side-panel|side-sheet)[^"']*["'])[^>]*aria-modal\s*=\s*["']true["'][^>]*>/gi,
  );
  const allViolations = [...violations, ...explicitlyMarked];
  assert(
    'accessibility.side-panels-nonmodal',
    allViolations.length === 0,
    'A desktop review/comparison/picker side panel is incorrectly declared aria-modal.',
    'Desktop side panels use non-modal semantics; confirmation dialogs remain modal.',
    allViolations.slice(0, 8),
  );
}

function verifyProgressActions(source) {
  const extracted = extractInitializer(source, ['progressCopy', 'progressStatesById', 'executionStateCopy']);
  const progress = evaluateLiteral(extracted);
  const noOp = [];

  if (progress && typeof progress === 'object') {
    for (const [stateName, value] of Object.entries(progress)) {
      const serialized = JSON.stringify(value);
      if (/continue tracking/i.test(serialized)) noOp.push(stateName);
    }
  } else {
    const progressFunction = extractFunction(source, 'renderProgressPreview') ?? '';
    if (/Continue tracking/i.test(progressFunction)) noOp.push('renderProgressPreview');
  }

  assert(
    'execution.no-passive-cta',
    noOp.length === 0,
    'Passive progress states still map to a no-op “Continue tracking” CTA.',
    'Passive progress states render status without a no-op primary CTA.',
    noOp,
  );
}

function verifyKnownBadValues(source) {
  const impossible = sourceMatches(source, /\b0\.062(?:0+)?\s+WBTC\b/gi);
  assert(
    'fixtures.wbtc-holding',
    impossible.length === 0,
    'The known impossible 0.062 WBTC intermediate holding remains.',
    'The known impossible WBTC holding is absent.',
    impossible,
  );
}

function verifyWarningStates(source) {
  const normalized = normalizeId(source);
  const required = [
    ['high-price-impact', ['highpriceimpact', 'priceimpacthigh']],
    ['low-liquidity', ['lowliquidity', 'insufficientliquiditywarning']],
    ['suspicious-token', ['suspicioustoken', 'tokenrisk']],
    ['unknown-token', ['unknowntoken', 'unverifiedtoken']],
    ['price-estimate-unavailable', ['priceestimateunavailable', 'estimateunavailable', 'priceunavailable']],
  ];
  const missing = required
    .filter(([, aliases]) => !aliases.some((alias) => normalized.includes(alias)))
    .map(([name]) => name);
  assert(
    'states.risk-warnings',
    missing.length === 0,
    'Required financial/token warning states are missing.',
    'High-price-impact, liquidity, token-risk, and unavailable-price states are represented.',
    missing,
  );
}

function collectActionNames(source) {
  const names = new Set();
  for (const match of source.matchAll(/\bdata-(?:wallet-)?action\s*=\s*["']([^"']+)["']/gi)) names.add(match[1]);
  for (const match of source.matchAll(/\bdata-open\s*=\s*["']([^"']+)["']/gi)) names.add(`open-${match[1]}`);
  return [...names];
}

function verifyInteractions(source) {
  const actions = collectActionNames(source);
  const normalizedActions = actions.map(normalizeId);
  const categories = [
    ['asset picker', /(asset|token).*(pick|select|open)|(pick|select|open).*(asset|token)/],
    ['address or recipient', /(address|recipient)/],
    ['option comparison', /(compare|option|details)/],
    ['review', /review/],
    ['execution', /(start|approve|sign|execute|swap)/],
    ['Activity or resume', /(activity|resume)/],
    ['recovery or evidence', /(recover|finish|refund|revoke|claim|evidence)/],
  ];
  const missingCategories = categories
    .filter(([, expression]) => !normalizedActions.some((name) => expression.test(name)))
    .map(([name]) => name);
  const hasDelegatedHandler = /closest\(\s*["']\[data-(?:wallet-)?action\]/.test(source)
    || /dataset\.(?:walletAction|action)\b/.test(source)
    || /function\s+handleWalletAction\s*\(/.test(source);

  assert(
    'interactions.customer-controls',
    actions.length >= 7 && missingCategories.length === 0,
    'Customer-facing control interactions do not cover the required journey categories.',
    'Customer-facing controls cover picker, comparison, review, execution, Activity, and recovery transitions.',
    { actions, missingCategories },
  );
  assert(
    'interactions.delegated-handler',
    hasDelegatedHandler,
    'Customer-facing data-action controls have no delegated interaction handler.',
    'Customer-facing data-action controls have a delegated interaction handler.',
  );
}

function journeyCollection(value) {
  if (Array.isArray(value)) {
    return Object.fromEntries(value.map((journey, index) => [journey?.id ?? journey?.journeyId ?? String(index), journey]));
  }
  if (!value || typeof value !== 'object') return null;
  for (const key of ['journeys', 'fixtures', 'items']) {
    if (value[key] && typeof value[key] === 'object') return journeyCollection(value[key]);
  }
  return value;
}

function findJourney(collection, aliases) {
  if (!collection) return null;
  for (const [key, value] of Object.entries(collection)) {
    const identifier = normalizeId(value?.id ?? value?.journeyId ?? key);
    if (aliases.some((alias) => identifier.includes(alias))) return { id: key, value };
  }
  return null;
}

function findFirst(object, paths) {
  for (const candidatePath of paths) {
    let value = object;
    for (const part of candidatePath.split('.')) value = value?.[part];
    if (value !== undefined && value !== null) return value;
  }
  return undefined;
}

function endpointFor(journey, role) {
  const sourcePaths = ['pay', 'source', 'from', 'intent.pay', 'intent.source', 'tradeIntent.pay', 'tradeIntent.source'];
  const destinationPaths = ['receive', 'destination', 'to', 'intent.receive', 'intent.destination', 'tradeIntent.receive', 'tradeIntent.destination'];
  const endpoint = findFirst(journey, role === 'source' ? sourcePaths : destinationPaths);
  if (!endpoint || typeof endpoint !== 'object') return null;
  const assetObject = endpoint.asset && typeof endpoint.asset === 'object' ? endpoint.asset : null;
  const asset = findFirst(endpoint, ['asset', 'symbol', 'ticker', 'assetCode', 'identity.symbol'])
    ?? findFirst(assetObject, ['symbol', 'ticker', 'code', 'id']);
  const network = findFirst(endpoint, ['network', 'networkName', 'chain', 'chainName', 'identity.network'])
    ?? findFirst(assetObject, ['network', 'networkName', 'chain', 'chainName']);
  const amount = findFirst(endpoint, ['amount', 'value', 'expected', 'expectedAmount', 'minimum', 'minimumAmount']);
  const address = findFirst(endpoint, ['address', 'recipient', 'resolvedAddress', 'walletAddress']);
  return {
    raw: endpoint,
    asset: typeof asset === 'object' ? findFirst(asset, ['symbol', 'ticker', 'code', 'id']) : asset,
    network: typeof network === 'object' ? findFirst(network, ['name', 'displayName', 'id']) : network,
    amount,
    address,
  };
}

function verifyJourneyFixtures(source) {
  const extracted = extractInitializer(source, ['canonicalJourneyFixtures', 'journeyFixtures']);
  assert(
    'fixtures.canonical-collection',
    Boolean(extracted),
    'Missing canonical journey fixture collection (`journeyFixtures` or `canonicalJourneyFixtures`).',
    `Canonical journey fixtures are exposed as ${extracted?.name ?? 'unknown'}.`,
  );
  if (!extracted) return null;

  const evaluated = evaluateLiteral(extracted);
  const collection = journeyCollection(evaluated);
  if (!collection) {
    fail('fixtures.canonical-shape', 'Canonical journey fixtures are not an object or array.');
    return null;
  }

  const required = {
    sameChain: ['samechain'],
    crossChain: ['crosschain'],
    mixed: ['mixed'],
    refund: ['refund'],
    differentToken: ['differenttoken'],
  };
  const journeys = Object.fromEntries(
    Object.entries(required).map(([name, aliases]) => [name, findJourney(collection, aliases)]),
  );
  const missing = Object.entries(journeys).filter(([, journey]) => !journey).map(([name]) => name);
  assert(
    'fixtures.required-journeys',
    missing.length === 0,
    'Canonical fixtures must include same-chain, cross-chain, mixed, refund, and different-token recovery journeys.',
    'Canonical fixtures include all core and recovery journeys.',
    missing,
  );

  for (const [name, found] of Object.entries(journeys)) {
    if (!found) continue;
    verifyJourney(name, found.value);
  }
  return { collection, journeys };
}

function verifyJourney(name, journey) {
  const source = endpointFor(journey, 'source');
  const destination = endpointFor(journey, 'destination');
  assert(
    `fixtures.${name}.endpoints`,
    Boolean(source && destination),
    `${name} is missing canonical pay/source or receive/destination data.`,
    `${name} exposes canonical source and destination data.`,
  );
  if (!source || !destination) return;

  const missingFields = [];
  for (const [role, endpoint] of [['source', source], ['destination', destination]]) {
    for (const field of ['asset', 'network', 'amount', 'address']) {
      if (endpoint[field] === undefined || endpoint[field] === null || endpoint[field] === '') {
        missingFields.push(`${role}.${field}`);
      }
    }
  }
  assert(
    `fixtures.${name}.identity`,
    missingFields.length === 0,
    `${name} must expose asset, network, amount, and address for both endpoints.`,
    `${name} endpoints have exact identity, amount, and address.`,
    missingFields,
  );

  const expectedRoutes = {
    sameChain: ['ETH', 'Ethereum', 'USDC', 'Ethereum'],
    crossChain: ['ETH', 'Ethereum', 'USDC', 'Arbitrum One'],
    mixed: ['USDC', 'Ethereum', 'BTC', 'Bitcoin'],
    refund: ['USDT', 'Ethereum', 'USDC', 'Arbitrum One'],
    differentToken: ['USDT', 'Arbitrum One', 'USDC', 'Arbitrum One'],
  };
  const expected = expectedRoutes[name];
  const actual = [source.asset, source.network, destination.asset, destination.network].map(normalizeId);
  const expectedNormalized = expected.map(normalizeId);
  assert(
    `fixtures.${name}.route`,
    actual.every((value, index) => value === expectedNormalized[index]),
    `${name} does not preserve the approved asset/network route end-to-end.`,
    `${name} preserves the approved asset/network route end-to-end.`,
    { expected, actual: [source.asset, source.network, destination.asset, destination.network] },
  );

  const expectedReceive = parseAmount(findFirst(journey, [
    'quote.expected', 'quote.expectedReceive', 'expected', 'expectedReceive', 'receive.expected', 'destination.expected',
  ]) ?? destination.amount);
  const minimumReceive = parseAmount(findFirst(journey, [
    'quote.minimum', 'quote.minimumReceive', 'minimum', 'minimumReceive', 'receive.minimum', 'destination.minimum',
  ]));
  if (expectedReceive !== null && minimumReceive !== null) {
    assert(
      `fixtures.${name}.minimum`,
      minimumReceive <= expectedReceive,
      `${name} minimum received exceeds expected received.`,
      `${name} minimum received does not exceed expected received.`,
      { expectedReceive, minimumReceive },
    );
  } else {
    warn(`fixtures.${name}.minimum`, `${name} does not expose both expected and minimum received as parseable fixture values.`);
  }

  verifyFees(name, journey);
  verifyOptions(name, journey, source, destination);
  verifyStageContinuity(name, journey);
}

function verifyOptions(name, journey, source, destination) {
  const options = findFirst(journey, ['options', 'quote.options', 'candidates']);
  const best = options?.best;
  assert(
    `fixtures.${name}.options`,
    options && typeof options === 'object' && best,
    `${name} is missing structured best/alternative option fixtures.`,
    `${name} exposes structured option fixtures.`,
  );
  if (!options || typeof options !== 'object' || !best) return;

  const failures = [];
  for (const [optionName, option] of Object.entries(options)) {
    const expected = parseAmount(option.expected);
    const minimum = parseAmount(option.minimum);
    const total = parseAmount(option.totalCost);
    const network = parseAmount(option.networkCost);
    const swap = parseAmount(option.swapCost);
    const maximum = parseAmount(option.maximumNetworkCost);
    if ([expected, minimum, total, network, swap, maximum].some((value) => value === null)
        || minimum > expected || !nearlyEqual(total, network + swap) || maximum < network) {
      failures.push({ optionName, expected, minimum, total, network, swap, maximum });
    }
  }
  assert(
    `fixtures.${name}.option-arithmetic`,
    failures.length === 0,
    `${name} has an option with invalid expected/minimum or fee arithmetic.`,
    `${name} option economics reconcile.`,
    failures,
  );

  const outcomeMismatch = normalizeId(best.expected) !== normalizeId(destination.raw.display ?? `${destination.amount} ${destination.asset}`)
    || normalizeId(best.minimum) !== normalizeId(destination.raw.minimum);
  assert(
    `fixtures.${name}.selected-option`,
    !outcomeMismatch,
    `${name} selected option does not match the canonical outcome/minimum.`,
    `${name} selected option matches the canonical outcome/minimum.`,
    { expected: best.expected, canonical: destination.raw.display, minimum: best.minimum, canonicalMinimum: destination.raw.minimum },
  );

  if (normalizeId(source.asset) === 'eth') {
    const invalidPermission = Object.entries(options)
      .filter(([, option]) => normalizeId(option.permission) !== 'none')
      .map(([optionName, option]) => ({ optionName, permission: option.permission }));
    assert(
      `fixtures.${name}.native-permission`,
      invalidPermission.length === 0,
      `${name} incorrectly requires token permission for native ETH.`,
      `${name} native ETH options require no token permission.`,
      invalidPermission,
    );
  }
}

function verifyFees(name, journey) {
  const fees = findFirst(journey, ['fees', 'quote.fees', 'costs']);
  if (!fees || typeof fees !== 'object') {
    fail(`fixtures.${name}.fees`, `${name} is missing a structured fee fixture.`);
    return;
  }

  const total = parseAmount(findFirst(fees, ['totalCost', 'total', 'allIn', 'allInCost']));
  const maximum = parseAmount(findFirst(fees, ['maximumNetworkCost', 'maxNetworkCost']));
  const invalidApprovalName = Object.keys(fees).some((key) => normalizeId(key) === 'approvalcost');
  assert(
    `fixtures.${name}.approval-fee-name`,
    !invalidApprovalName,
    `${name} uses “approvalCost”; use “approvalNetworkCost” and nest it under network costs.`,
    `${name} does not model approval gas as a provider/swap fee.`,
  );

  let components = [];
  if (Array.isArray(fees.components)) {
    components = fees.components
      .map((component) => parseAmount(component?.amount ?? component?.value ?? component?.cost))
      .filter((amount) => amount !== null);
  } else {
    components = Object.entries(fees)
      .filter(([key, value]) => {
        const normalizedKey = normalizeId(key);
        return typeof value !== 'object'
          && /cost|fee/.test(normalizedKey)
          && !/(total|maximum|max|currency|fiat)/.test(normalizedKey);
      })
      .map(([, value]) => parseAmount(value))
      .filter((amount) => amount !== null);
  }

  const networkCost = parseAmount(findFirst(fees, ['networkCost', 'networkCosts']));
  const approvalNetworkCost = parseAmount(findFirst(fees, ['approvalNetworkCost', 'network.approvalNetworkCost', 'network.approval']));
  // When fees are expressed as scalar object fields, approvalNetworkCost is an
  // informational child of networkCost and must not be added a second time.
  const countedComponents = Array.isArray(fees.components) ? components : Object.entries(fees)
    .filter(([key, value]) => {
      const normalizedKey = normalizeId(key);
      return typeof value !== 'object'
        && /cost|fee/.test(normalizedKey)
        && !/(total|maximum|max|currency|fiat|approvalnetworkcost)/.test(normalizedKey);
    })
    .map(([, value]) => parseAmount(value))
    .filter((amount) => amount !== null);
  const componentTotal = Number(countedComponents.reduce((sum, amount) => sum + amount, 0).toFixed(8));
  const reconciled = total !== null && countedComponents.length > 0 && nearlyEqual(total, componentTotal);

  assert(
    `fixtures.${name}.fee-total`,
    total !== null && countedComponents.length > 0 && reconciled,
    `${name} total cost does not reconcile with its structured fee components.`,
    `${name} total cost reconciles with its structured fee components.`,
    { total, countedComponents, nestedApprovalNetworkCost: approvalNetworkCost, componentTotal },
  );
  assert(
    `fixtures.${name}.nonnegative-fees`,
    components.every((amount) => amount >= 0),
    `${name} includes a negative fee component.`,
    `${name} fee components are non-negative.`,
    components,
  );
  if (maximum !== null && networkCost !== null) {
    assert(
      `fixtures.${name}.maximum-network-cost`,
      maximum >= networkCost,
      `${name} maximum network cost is below its expected network cost.`,
      `${name} maximum network cost bounds its expected network cost.`,
      { maximum, networkCost },
    );
  } else {
    warn(`fixtures.${name}.maximum-network-cost`, `${name} does not expose parseable expected and maximum network costs.`);
  }
}

function stageEndpoint(stage, role) {
  const value = findFirst(stage, role === 'input'
    ? ['input', 'source', 'from', 'inputHolding']
    : ['output', 'destination', 'to', 'outputHolding', 'holding']);
  if (!value || typeof value !== 'object') return null;
  return {
    asset: findFirst(value, ['asset', 'symbol', 'ticker', 'assetCode']),
    network: findFirst(value, ['network', 'networkName', 'chain', 'chainName']),
    address: findFirst(value, ['address', 'recipient']),
    amount: findFirst(value, ['amount', 'value']),
  };
}

function verifyStageContinuity(name, journey) {
  const stages = findFirst(journey, ['stages', 'route.stages', 'timeline.stages']);
  if (!Array.isArray(stages) || stages.length === 0) {
    fail(`fixtures.${name}.stages`, `${name} is missing a structured stage sequence.`);
    return;
  }
  const checked = [];
  const mismatches = [];
  for (let index = 0; index < stages.length - 1; index += 1) {
    const output = stageEndpoint(stages[index], 'output');
    const input = stageEndpoint(stages[index + 1], 'input');
    if (!output || !input) continue;
    checked.push(index);
    for (const field of ['asset', 'network', 'address']) {
      if (output[field] !== undefined && input[field] !== undefined
          && normalizeId(output[field]) !== normalizeId(input[field])) {
        mismatches.push({ transition: `${index}→${index + 1}`, field, output: output[field], input: input[field] });
      }
    }
    const outputAmount = parseAmount(output.amount);
    const inputAmount = parseAmount(input.amount);
    if (outputAmount !== null && inputAmount !== null && !nearlyEqual(outputAmount, inputAmount, 0.000001)) {
      mismatches.push({ transition: `${index}→${index + 1}`, field: 'amount', output: outputAmount, input: inputAmount });
    }
  }
  assert(
    `fixtures.${name}.stage-continuity`,
    mismatches.length === 0,
    `${name} has discontinuities between adjacent structured stages.`,
    checked.length > 0
      ? `${name} adjacent structured stage holdings are continuous.`
      : `${name} declares stages; no adjacent input/output pairs were exposed for deeper continuity checks.`,
    mismatches,
  );
}

function verifyPrototypeFlows(source, fixtureResult) {
  const extracted = extractInitializer(source, ['flows', 'prototypeFlows']);
  const flows = evaluateLiteral(extracted);
  assert(
    'flows.collection',
    Array.isArray(flows),
    'Missing a parseable prototype flow collection.',
    'Prototype flow collection is parseable.',
  );
  if (!Array.isArray(flows)) return;

  const required = [
    'same-chain', 'cross-chain', 'external-recipient', 'compare-update', 'approval-reset',
    'mixed', 'resume', 'different-token', 'refund', 'manual-revoke',
  ];
  const flowById = new Map(flows.map((flow) => [normalizeId(flow?.id), flow]));
  const missing = required.filter((id) => !flowById.has(normalizeId(id)));
  assert(
    'flows.required-ten',
    flows.length >= 10 && missing.length === 0,
    'The ten required prototype flows are not all present.',
    'All ten required prototype flows are present.',
    { count: flows.length, missing },
  );

  const fixtureLinks = {};
  for (const id of ['same-chain', 'cross-chain', 'mixed']) {
    const flow = flowById.get(normalizeId(id));
    const fixtureId = flow && findFirst(flow, ['fixture', 'fixtureId', 'journey', 'journeyId']);
    fixtureLinks[id] = fixtureId ?? null;
  }
  const missingLinks = Object.entries(fixtureLinks).filter(([, value]) => !value).map(([id]) => id);
  const mismatchedLinks = Object.entries(fixtureLinks)
    .filter(([id, value]) => value && !normalizeId(value).includes(normalizeId(id)))
    .map(([id, value]) => ({ flow: id, fixture: value }));
  assert(
    'flows.fixture-links',
    Boolean(fixtureResult) && missingLinks.length === 0 && mismatchedLinks.length === 0,
    'Same-chain, cross-chain, and mixed prototype flows must reference their canonical journey fixtures.',
    'Core prototype flows reference canonical journey fixtures.',
    { fixtureLinks, mismatchedLinks },
  );
}

function verifyPrototypeDataContracts(source, fixtureResult) {
  const journeys = Object.values(fixtureResult?.collection || {});
  const executionIds = journeys.map((journey) => journey?.executionId).filter(Boolean);
  const invalidExecutionIds = executionIds.filter((executionId) => (
    typeof executionId !== 'string'
    || executionId.includes('…')
    || executionId.includes('...')
    || !/^route_[a-z0-9_]{20,}$/i.test(executionId)
  ));
  assert(
    'contracts.execution-ids-full',
    executionIds.length === journeys.length
      && new Set(executionIds).size === executionIds.length
      && invalidExecutionIds.length === 0,
    'Journey fixtures must store unique full execution IDs without embedded visual truncation.',
    'Journey fixtures store unique full execution IDs; truncation is presentation-only.',
    { executionIds, invalidExecutionIds },
  );

  const activityContract = evaluateLiteral(extractInitializer(source, ['activityDataContract']));
  const activityContractValid = activityContract?.authority === 'KDF'
    && activityContract?.listMethod === 'experimental::trade_route::list_executions'
    && activityContract?.getMethod === 'experimental::trade_route::get_execution'
    && activityContract?.prototypeFixtureStorage === 'in-memory'
    && activityContract?.prototypeIsDurable === false;
  assert(
    'contracts.activity-authority',
    activityContractValid,
    'Activity fixtures must identify KDF list/get as authoritative and explicitly deny in-memory durability.',
    'Activity fixtures explicitly simulate KDF-authoritative list/get and deny in-memory durability.',
    activityContract,
  );

  const historicalContract = evaluateLiteral(extractInitializer(source, ['historicalRecoveryContract']));
  const historicalContractValid = historicalContract?.fixtureId === 'refund'
    && historicalContract?.sourceNetwork === 'Ethereum'
    && historicalContract?.destinationNetwork === 'Arbitrum One'
    && historicalContract?.readOnly === true
    && Array.isArray(historicalContract?.executableActions)
    && historicalContract.executableActions.length === 0;
  assert(
    'contracts.historical-refund-read-only',
    historicalContractValid && /terminal\|\|item\.readOnly\?['"]{2}:/.test(source),
    'The historical refund example must be EVM-only, read-only, and expose no execution CTA.',
    'The historical EVM refund contract is read-only and suppresses execution CTAs.',
    historicalContract,
  );

  const holdings = evaluateLiteral(extractInitializer(source, ['recoveryHoldingData']));
  const expectedHoldings = {
    'different-token': ['USDT', 'Arbitrum One', 1318.42],
    intermediate: ['WBTC', 'Ethereum', 0.01816],
    'missing-order': ['USDC', 'Arbitrum One', 892],
    recoverable: ['WBTC', 'Ethereum', 0.01816],
    'stale-action': ['WBTC', 'Ethereum', 0.01816],
    'approval-only': ['USDC', 'Ethereum', 320],
    refunded: ['USDT', 'Ethereum', 409.2],
    'claim-ready': ['USDT', 'Ethereum', 409.2],
  };
  const holdingMismatches = Object.entries(expectedHoldings).flatMap(([state, expected]) => {
    const actual = holdings?.[state];
    const matches = actual
      && normalizeId(actual.asset) === normalizeId(expected[0])
      && normalizeId(actual.network) === normalizeId(expected[1])
      && nearlyEqual(parseAmount(actual.amount), expected[2], 0.000001)
      && typeof actual.full === 'string'
      && !actual.full.includes('…');
    return matches ? [] : [{ state, expected, actual }];
  });
  assert(
    'contracts.recovery-holdings',
    holdingMismatches.length === 0,
    'Canonical recovery holdings contain inconsistent asset, network, amount, or full-address data.',
    'Canonical recovery holdings reconcile across recovery states.',
    holdingMismatches,
  );

  const analyticsSchema = evaluateLiteral(extractInitializer(source, ['privacySafeAnalyticsSchema']));
  const expectedAnalyticsFields = ['outcomeCategory', 'routeSourceCategory', 'stageCount', 'stageDurationMs'];
  const actualAnalyticsFields = Object.keys(analyticsSchema?.fields || {}).sort();
  const analyticsFunction = evaluateFunction(source, 'buildPrivacySafeAnalyticsEvent', { privacySafeAnalyticsSchema: analyticsSchema });
  let analyticsEvent = null;
  let analyticsError = analyticsFunction.error;
  if (typeof analyticsFunction.value === 'function') {
    try {
      analyticsEvent = analyticsFunction.value({
        routeSourceCategory: 'external_evm',
        stageCount: 4,
        stageDurationMs: 1200,
        outcomeCategory: 'completed',
        asset: 'ETH',
        amount: '1.0',
        address: '0xsecret',
        hash: '0xhash',
        providerIdentity: 'provider',
        rawPayload: { secret: true },
      });
    } catch (error) {
      analyticsError = error;
    }
  }
  const emittedAnalyticsFields = Object.keys(analyticsEvent || {}).sort();
  assert(
    'contracts.analytics-whitelist',
    !analyticsError
      && JSON.stringify(actualAnalyticsFields) === JSON.stringify(expectedAnalyticsFields)
      && JSON.stringify(emittedAnalyticsFields) === JSON.stringify(expectedAnalyticsFields),
    'Privacy analytics must emit only route source category, stage count/duration, and outcome category.',
    'Privacy analytics uses an executable four-field whitelist and drops sensitive dimensions.',
    { schemaFields: actualAnalyticsFields, emittedFields: emittedAnalyticsFields, error: analyticsError?.message },
  );

  const binder = evaluateFunction(source, 'bindConsentToExecution');
  const fullExecutionId = 'route_test_1234567890abcdef12345678';
  let boundConsent = null;
  let binderError = binder.error;
  if (typeof binder.value === 'function') {
    try {
      boundConsent = binder.value({ expected: '10 USDC', minimum: '9 USDC' }, fullExecutionId);
    } catch (error) {
      binderError = error;
    }
  }
  assert(
    'contracts.consent-execution-binding',
    !binderError
      && boundConsent?.executionId === fullExecutionId
      && boundConsent?.expected === '10 USDC'
      && /action\s*===\s*['"]start-swap['"][\s\S]{0,180}executionConsentFromReview\(state\.selectedExecutionId\s*,/.test(source)
      && /\['progress','activity','timeline'\][\s\S]{0,400}executionConsentFromReview\(state\.selectedExecutionId\s*,\s*reviewedState\)/.test(source),
    'Completed scripted flows must bind reviewed consent to the same full execution ID before progress.',
    'Reviewed consent and scripted execution progress share the same full execution ID.',
    { boundConsent, error: binderError?.message },
  );
}

async function verifyClipboardContract(source) {
  async function exercise(writeText) {
    const announcements = [];
    const writes = [];
    const evaluated = evaluateFunction(source, 'copyValue', {
      navigator: { clipboard: { async writeText(value) { writes.push(value); return writeText(value); } } },
      announce(message) { announcements.push(message); },
    });
    if (evaluated.error || typeof evaluated.value !== 'function') {
      return { error: evaluated.error?.message || 'copyValue is not executable', announcements, writes };
    }
    try {
      const returned = await evaluated.value('route_full_1234567890', 'Execution ID');
      return { returned, announcements, writes };
    } catch (error) {
      return { error: error.message, announcements, writes };
    }
  }

  const success = await exercise(async () => undefined);
  assert(
    'runtime.clipboard-success',
    !success.error
      && success.returned === true
      && success.writes.length === 1
      && success.announcements.length === 1
      && success.announcements[0] === 'Execution ID copied',
    'Clipboard success must be announced only after a successful write.',
    'Clipboard success is announced after the write resolves.',
    success,
  );

  const failure = await exercise(async () => { throw new Error('denied'); });
  assert(
    'runtime.clipboard-failure',
    !failure.error
      && failure.returned === false
      && failure.writes.length === 1
      && failure.announcements.length === 1
      && /couldn[’']t copy execution id/i.test(failure.announcements[0]),
    'Clipboard failure must announce failure and never announce success.',
    'Clipboard failure produces a failure announcement with manual-copy guidance.',
    failure,
  );
}

function verifyEvidenceManifest(qaSource) {
  const evidenceDirectory = path.join(path.dirname(artifactPath), 'qa-evidence');
  const manifestPath = path.join(evidenceDirectory, 'manifest.json');
  let manifest = null;
  try {
    manifest = JSON.parse(fs.readFileSync(manifestPath, 'utf8'));
  } catch (error) {
    fail('evidence.manifest', 'The QA evidence manifest is missing or invalid JSON.', error.message);
    return;
  }

  const rawCaptures = Array.isArray(manifest.rawViewportCaptures) ? manifest.rawViewportCaptures : [];
  const rawFailures = [];
  for (const capture of rawCaptures) {
    const filename = path.basename(String(capture?.file || ''));
    if (!filename || filename !== capture.file || !filename.endsWith('.png')) {
      rawFailures.push({ file: capture?.file, reason: 'unsafe or non-PNG filename' });
      continue;
    }
    try {
      const buffer = fs.readFileSync(path.join(evidenceDirectory, filename));
      const pngMagic = buffer.subarray(0, 8).equals(Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]));
      const width = buffer.length >= 24 ? buffer.readUInt32BE(16) : null;
      const height = buffer.length >= 24 ? buffer.readUInt32BE(20) : null;
      if (!pngMagic || width !== capture.width || height !== capture.height) {
        rawFailures.push({ file: filename, expected: [capture.width, capture.height], actual: [width, height], pngMagic });
      }
      if (!qaSource.includes(filename)) rawFailures.push({ file: filename, reason: 'not referenced by QA record' });
    } catch (error) {
      rawFailures.push({ file: filename, reason: error.message });
    }
  }
  assert(
    'evidence.raw-viewports',
    rawCaptures.length >= 3 && rawFailures.length === 0,
    'Raw viewport evidence must contain at least three QA-referenced PNGs with exact recorded dimensions.',
    'Raw browser-viewport evidence files match their recorded PNG dimensions.',
    { count: rawCaptures.length, failures: rawFailures },
  );

  const correctedLegacy = Array.isArray(manifest.correctedLegacyExtensions) ? manifest.correctedLegacyExtensions : [];
  const legacyFailures = [];
  for (const filenameValue of correctedLegacy) {
    const filename = path.basename(String(filenameValue || ''));
    try {
      const buffer = fs.readFileSync(path.join(evidenceDirectory, filename));
      const jpegMagic = buffer.length >= 3 && buffer[0] === 0xff && buffer[1] === 0xd8 && buffer[2] === 0xff;
      if (filename !== filenameValue || !filename.endsWith('.jpg') || !jpegMagic) {
        legacyFailures.push({ file: filenameValue, jpegMagic });
      }
    } catch (error) {
      legacyFailures.push({ file: filenameValue, reason: error.message });
    }
  }
  assert(
    'evidence.correct-extensions',
    correctedLegacy.length === 8 && legacyFailures.length === 0,
    'Legacy JPEG evidence must use a .jpg extension and retain valid JPEG data.',
    'Mislabeled legacy evidence now uses extensions that match its JPEG data.',
    { count: correctedLegacy.length, failures: legacyFailures },
  );
}

function verifyRuntimeContracts(source) {
  const requirements = [
    ['runtime.surface-stack', /surfaceStack\s*:\s*\[\][\s\S]*function\s+rememberSurface[\s\S]*openerExecutionId/, 'Nested surfaces must retain a return stack and exact Activity opener.'],
    ['runtime.amount-focus', /wallet-amount-input[\s\S]*focus\(\{?preventScroll[\s\S]*setSelectionRange/, 'Amount input must restore focus and caret after a render.'],
    ['runtime.modal-isolation', /wallet-header[\s\S]*wallet-bottom-nav[\s\S]*data-modal-background[\s\S]*setAttribute\(['"]inert/, 'Modal rendering must isolate header, navigation, and background.'],
    ['runtime.activity-back', /data-action=["']activity-back["'][\s\S]*action\s*===\s*["']activity-back["']/, 'Activity detail must expose and handle Back.'],
    ['runtime.keep-token', /function\s+persistKeptToken[\s\S]*activityRows\.attention\s*=\s*activityRows\.attention\.filter[\s\S]*activityRows\.completed\.unshift/, 'Keep token must persist the outcome into Completed Activity.'],
    ['runtime.fresh-recovery', /hydrateFreshIntentFromHolding[\s\S]*different-token[\s\S]*fresh-recovery/, 'Different-token recovery must hydrate a fresh holding-based intent and consent.'],
    ['runtime.signed-boundary', /signed\s*:\s*\{\s*canCancel\s*:\s*false\s*,\s*canStopAfterCurrent\s*:\s*false\s*,\s*reconciliationOnly\s*:\s*true/, 'Signed requests must expose reconciliation-only controls.'],
    ['runtime.stress-options', /Array\.from\(\{length\s*:\s*124\}[\s\S]*All 128 options shown/, 'The 128-option stress state must reveal every retained option when requested.'],
    ['runtime.visible-refresh', /^(?=[\s\S]*recoveryFeedback)(?=[\s\S]*Status refreshed just now)(?=[\s\S]*Just now)/, 'Recovery refresh must produce visible feedback and timestamp evidence.'],
    ['runtime.consent-to-activity', /function\s+persistExecutionToActivity[\s\S]*consent\.expected[\s\S]*activityRows\[bucket\]\.unshift[\s\S]*item\.consent\?\{\.\.\.item\.consent\}/, 'The exact consented option must persist into Activity and restore on reopen.'],
    ['runtime.execution-evidence', /const\s+executionEvidence\s*=\s*Object\.freeze[\s\S]*item\?\.evidence[\s\S]*executionEvidence\[item(?:\?\.)?\.timelineState\]/, 'Activity evidence must be keyed to the selected execution and timeline state.'],
    ['runtime.full-holding-copy', /holdingPayload\s*=\s*holdingData\s*\?[^;]*holdingData\.full/, 'Holding copy actions must use the full address rather than display truncation.'],
    ['runtime.offline-review-blocked', /offline\s*:\s*\{[^}]*quote\s*:\s*false[^}]*Reconnect and refresh before reviewing/, 'Offline entry must not expose stale option details or review.'],
    ['runtime.warning-consent', /data-warning-key[\s\S]*element\.dataset\.warningKey[\s\S]*state\.activeWarnings/, 'Financial warnings must persist from entry into review consent.'],
    ['runtime.material-route-continuity', /persistedConsent\?\.fixtureId[\s\S]*materialRefreshByFixture[\s\S]*previousExpected\s*:\s*persistedConsent\?\.expected/, 'Material refreshes must preserve the consented route and prior option economics.'],
    ['runtime.dynamic-stop-copy', /name\s*===\s*["']stop["'][\s\S]*planned outcome is \$\{consent\?\.expected/, 'Stop confirmation must derive the planned outcome from the active consent.'],
    ['accessibility.roving-composites', /role=["']radiogroup["'][\s\S]*querySelectorAll\('\[role="radiogroup"\], \[role="listbox"\]'\)[\s\S]*ArrowDown[\s\S]*Home[\s\S]*End/, 'Composite pickers and route options must expose one roving tab stop with Arrow/Home/End handling.'],
    ['accessibility.persistent-mobile-nav', /grid-template-rows\s*:\s*auto minmax\(0,1fr\) auto[\s\S]*wallet-main[^}]*overflow-y\s*:\s*auto[\s\S]*wallet-bottom-nav[^}]*position\s*:\s*relative/, 'Mobile navigation must remain in a persistent app-shell row outside the scrolling main content.'],
    ['accessibility.field-errors', /invalidField\s*:\s*["']recipient["'][\s\S]*invalidField\s*:\s*["']receive-asset["'][\s\S]*invalidField\s*:\s*["']source-address["'][\s\S]*aria-describedby/, 'Validation errors must identify and describe the actual invalid control.'],
    ['accessibility.control-contrast', /--control-border\s*:\s*#747a9b[\s\S]*--control-border\s*:\s*#767c96[\s\S]*wallet-picker-row[\s\S]*border\s*:\s*1px solid var\(--control-border\)/, 'Interactive control boundaries must use the validated 3:1 contrast token in both themes.'],
  ];
  for (const [id, expression, message] of requirements) {
    assert(id, expression.test(source), message, message.replace('must', 'does'));
  }

  const staleOptionActions = /name\s*===\s*["']expired["'][\s\S]{0,180}data-action=["']refresh-quote["']/.test(source)
    && /name\s*===\s*["']unavailable["'][\s\S]{0,180}data-action=["']show-available-options["']/.test(source);
  assert(
    'runtime.stale-options-disabled',
    staleOptionActions,
    'Expired or unavailable options still expose “Use this option”.',
    'Expired and unavailable options expose refresh/compare actions instead of selection.',
  );
}

function verifyQuoteEvaluationController(source) {
  const forbiddenState = new Proxy(Object.create(null), {
    get(_target, property) {
      throw new Error(`Quote controller read global state.${String(property)}.`);
    },
    set(_target, property) {
      throw new Error(`Quote controller wrote global state.${String(property)}.`);
    },
  });
  const evaluated = evaluateFunction(source, 'createQuoteEvaluationController', { state: forbiddenState });
  const factoryIsExecutable = Boolean(
    evaluated.extracted
    && !evaluated.error
    && typeof evaluated.value === 'function',
  );
  assert(
    'runtime.quote-controller.executable',
    factoryIsExecutable,
    'Missing or non-executable `createQuoteEvaluationController` implementation.',
    'The artifact exposes an executable quote-evaluation controller.',
    evaluated.error?.message,
  );
  if (!factoryIsExecutable) return;

  const globalNavigationDependency = /\bstate\s*\.\s*(?:section|flow)\b/.test(evaluated.extracted);
  assert(
    'runtime.quote-controller.navigation-source',
    !globalNavigationDependency,
    'Quote completion still depends on the current section or scripted flow.',
    'Quote completion has no section or scripted-flow dependency.',
  );

  function harness() {
    const scheduler = createFakeScheduler();
    const transitions = [];
    const controller = evaluated.value({
      schedule: scheduler.schedule,
      cancelScheduled: scheduler.cancelScheduled,
      onTransition(value) {
        transitions.push(value);
      },
      completionDelay: 450,
      timeoutDelay: 4000,
    });
    if (!controller || typeof controller.begin !== 'function'
        || typeof controller.cancel !== 'function'
        || typeof controller.snapshot !== 'function') {
      throw new TypeError('Controller must return begin(), cancel(), and snapshot().');
    }
    return {
      controller,
      scheduler,
      transitions,
      states() {
        return transitions.map(quoteStateOf);
      },
    };
  }

  function runCase(id, failureMessage, successMessage, operation) {
    try {
      const detail = operation();
      assert(id, detail?.ok === true, failureMessage, successMessage, detail);
    } catch (error) {
      fail(id, failureMessage, error.message);
    }
  }

  runCase(
    'runtime.quote-controller.completion',
    'A quote request does not transition immediately to checking and then to its requested outcome.',
    'A quote request transitions from checking to its requested terminal outcome.',
    () => {
      const test = harness();
      test.controller.begin({ intentKey: 'intent:completion', outcome: 'quoted-multiple' });
      const immediate = test.states();
      const completion = test.scheduler.runFirst(450);
      const afterCompletion = test.states();
      const beforeLateTimeout = afterCompletion.length;
      test.scheduler.runFirst(4000, { force: true });
      const snapshot = test.controller.snapshot();
      return {
        ok: immediate.at(-1) === 'checking'
          && completion.ran
          && afterCompletion.at(-1) === 'quoted-multiple'
          && test.states().length === beforeLateTimeout
          && quoteStateOf(snapshot) === 'quoted-multiple',
        immediate,
        final: test.states(),
        snapshot: quoteStateOf(snapshot),
      };
    },
  );

  runCase(
    'runtime.quote-controller.timeout',
    'A request whose completion never wins does not reach a terminal timeout.',
    'A request whose completion never wins reaches timeout and ignores late completion.',
    () => {
      const test = harness();
      test.controller.begin({ intentKey: 'intent:timeout', outcome: 'quoted-multiple' });
      const droppedCompletion = test.scheduler.dropFirst(450);
      const timeout = test.scheduler.runFirst(4000);
      const afterTimeout = test.states();
      const transitionCount = afterTimeout.length;
      test.scheduler.run(droppedCompletion, { force: true });
      const snapshot = test.controller.snapshot();
      return {
        ok: Boolean(droppedCompletion)
          && timeout.ran
          && afterTimeout.at(-1) === 'timeout'
          && test.states().length === transitionCount
          && quoteStateOf(snapshot) === 'timeout',
        states: test.states(),
        snapshot: quoteStateOf(snapshot),
      };
    },
  );

  runCase(
    'runtime.quote-controller.retry',
    'Retry does not start a fresh request after timeout.',
    'Retry starts a fresh request and can recover from timeout.',
    () => {
      const test = harness();
      test.controller.begin({ intentKey: 'intent:retry:1', outcome: 'no-route' });
      test.scheduler.dropFirst(450);
      test.scheduler.runFirst(4000);
      test.controller.begin({ intentKey: 'intent:retry:2', outcome: 'quoted-single' });
      const completion = test.scheduler.runFirst(450, { newest: true });
      const states = test.states();
      return {
        ok: completion.ran
          && states.join('|') === 'checking|timeout|checking|quoted-single'
          && quoteStateOf(test.controller.snapshot()) === 'quoted-single',
        states,
      };
    },
  );

  runCase(
    'runtime.quote-controller.latest-wins',
    'An older request can overwrite a newer quote intent.',
    'Only the latest quote intent can publish a terminal result.',
    () => {
      const test = harness();
      test.controller.begin({ intentKey: 'intent:old', outcome: 'no-route' });
      const oldTasks = [...test.scheduler.tasks.values()];
      test.controller.begin({ intentKey: 'intent:new', outcome: 'quoted-multiple' });
      oldTasks.forEach((task) => test.scheduler.run(task, { force: true }));
      const afterStaleCallbacks = test.states();
      const completion = test.scheduler.runFirst(450, { newest: true });
      const states = test.states();
      return {
        ok: afterStaleCallbacks.join('|') === 'checking|checking'
          && completion.ran
          && states.at(-1) === 'quoted-multiple'
          && !states.includes('no-route'),
        afterStaleCallbacks,
        states,
      };
    },
  );

  runCase(
    'runtime.quote-controller.navigation-independent',
    'Navigation or an open customer surface can strand quote evaluation.',
    'Quote evaluation completes independently of navigation and open surfaces.',
    () => {
      const test = harness();
      test.controller.begin({ intentKey: 'intent:surface-independent', outcome: 'quoted-single' });
      const surfaceChangedWhilePending = true;
      const completion = test.scheduler.runFirst(450);
      const states = test.states();
      return {
        ok: surfaceChangedWhilePending
          && completion.ran
          && states.join('|') === 'checking|quoted-single',
        states,
      };
    },
  );

  runCase(
    'runtime.quote-controller.cancellation',
    'Cancelling quote evaluation leaves callbacks able to publish later states.',
    'Cancellation invalidates and cancels all pending quote callbacks.',
    () => {
      const test = harness();
      test.controller.begin({ intentKey: 'intent:cancel', outcome: 'quoted-multiple' });
      const scheduled = [...test.scheduler.tasks.values()];
      test.controller.cancel();
      const countAfterCancel = test.transitions.length;
      scheduled.forEach((task) => test.scheduler.run(task, { force: true }));
      return {
        ok: scheduled.length === 2
          && scheduled.every((task) => task.cancelled)
          && test.transitions.length === countAfterCancel,
        scheduled: scheduled.map(({ delay, cancelled, ran }) => ({ delay, cancelled, ran })),
        states: test.states(),
      };
    },
  );

  runCase(
    'runtime.quote-controller.stale-callbacks',
    'A completion or timeout callback can publish after the request is terminal.',
    'Late completion and timeout callbacks are ignored after a terminal result.',
    () => {
      const test = harness();
      test.controller.begin({ intentKey: 'intent:terminal', outcome: 'service-error' });
      const scheduled = [...test.scheduler.tasks.values()];
      const completion = scheduled.find((task) => task.delay === 450);
      const timeout = scheduled.find((task) => task.delay === 4000);
      test.scheduler.run(completion);
      const countAfterTerminal = test.transitions.length;
      test.scheduler.run(timeout, { force: true });
      test.scheduler.run(completion, { force: true });
      return {
        ok: test.states().at(-1) === 'service-error'
          && test.transitions.length === countAfterTerminal,
        states: test.states(),
      };
    },
  );
}

function verifyRemediatedUiContracts(source) {
  verifyEntryLifecycleSemantics(source);
  verifyAccessibilityVariantControls(source);
  verifyCombinedBrandIdentity(source);
  verifyReviewProgressiveDisclosure(source);
}

function verifyEntryLifecycleSemantics(source) {
  const entryFunction = extractFunction(source, 'entryConfig') ?? '';
  const readyBase = extractInitializer(entryFunction, ['readyBase', 'base'])?.literal ?? '';
  const baseIsReady = /loading\s*:\s*false\b/.test(readyBase)
    && /quote\s*:\s*true\b/.test(readyBase)
    && /cta\s*:\s*["']Review swap["']/.test(readyBase);
  const checking = findNamedObjectLiteral(entryFunction, 'checking') ?? '';
  const terminalNames = ['quoted-single', 'quoted-multiple', 'no-route', 'service-error', 'quote-timeout'];
  const terminalDetails = terminalNames.map((name) => {
    const literal = findNamedObjectLiteral(entryFunction, name);
    const directReference = new RegExp(`["']${name}["']\\s*:\\s*(?:readyBase|base)\\b`).test(entryFunction);
    return {
      name,
      present: Boolean(literal || directReference),
      loadingSafe: Boolean((literal || directReference)
        && !/loading\s*:\s*true\b/.test(literal ?? '')
        && (/loading\s*:\s*false\b/.test(literal ?? '') || baseIsReady)),
    };
  });
  assert(
    'runtime.entry.explicit-loading-semantics',
    baseIsReady
      && /loading\s*:\s*true\b/.test(checking)
      && terminalDetails.every((item) => item.present && item.loadingSafe),
    'Entry states do not explicitly separate genuine loading from terminal outcomes.',
    'Checking is busy while every ready/error/timeout outcome is explicitly non-loading.',
    { baseIsReady, checkingIsLoading: /loading\s*:\s*true\b/.test(checking), terminalDetails },
  );

  const single = findNamedObjectLiteral(entryFunction, 'quoted-single') ?? '';
  const multiple = findNamedObjectLiteral(entryFunction, 'quoted-multiple') ?? '';
  const renderEntry = extractFunction(source, 'renderEntryPreview') ?? '';
  const readyStatesUseReadyBase = [single, multiple].every((literal) => (
    !/quote\s*:\s*false\b/.test(literal)
      && !/cta\s*:\s*["'](?!Review swap)[^"']+["']/.test(literal)
  ));
  const rendererShowsRouteAndReview = /config\.quote\s*\?\s*quoteStrip/.test(renderEntry)
    && /config\.cta\s*===\s*["']Review swap["']\s*\?\s*["']review-swap["']/.test(renderEntry);
  assert(
    'runtime.entry.ready-route-review',
    baseIsReady && readyStatesUseReadyBase && rendererShowsRouteAndReview,
    'A ready quote can render without route options or an enabled Review action.',
    'Ready quote states always render route options and the Review action.',
    { baseIsReady, readyStatesUseReadyBase, rendererShowsRouteAndReview },
  );

  verifyEntryBalanceAndRecoveryContracts(source, entryFunction, renderEntry);
}

function verifyEntryBalanceAndRecoveryContracts(source, entryFunction, renderEntry) {
  const state = {
    activeJourney: 'cross-chain',
    selectedPay: null,
    selectedReceive: null,
    selectedSourceAddress: {
      balance: '0.250 ETH',
      balances: { ETH: ['0.250 ETH', '$802.95'] },
    },
    amountDraft: '1.00',
  };
  const journeyFixtures = {
    'cross-chain': {
      pay: { asset: 'ETH', network: 'Ethereum', amount: '1.00', balance: '2.481 ETH' },
      receive: { asset: 'USDC', network: 'Arbitrum One' },
    },
  };
  const numericAmount = (value) => Number(String(value ?? '').replaceAll(',', '').match(/[0-9.]+/)?.[0] || 0);
  const evaluated = evaluateFunction(source, 'entryOutcomeForCurrentIntent', {
    state,
    journeyFixtures,
    numericAmount,
  });
  let lowerBalanceOutcome = null;
  let sufficientBalanceOutcome = null;
  let evaluationError = evaluated.error;
  if (!evaluationError && typeof evaluated.value === 'function') {
    try {
      lowerBalanceOutcome = evaluated.value();
      state.selectedSourceAddress = {
        balance: '2.481 ETH',
        balances: { ETH: ['2.481 ETH', '$7,970.78'] },
      };
      sufficientBalanceOutcome = evaluated.value();
    } catch (error) {
      evaluationError = error;
    }
  }
  const outcomeSource = evaluated.extracted ?? '';
  const sourceContract = /selectedSourceAddress\?\.balances/.test(outcomeSource)
    && /amount\s*>\s*spendable[\s\S]{0,80}return\s+["']insufficient["']/.test(outcomeSource);
  assert(
    'runtime.entry.selected-address-insufficient',
    !evaluationError
      && sourceContract
      && lowerBalanceOutcome === 'insufficient'
      && sufficientBalanceOutcome === 'quoted-multiple',
    'Quote evaluation does not reject an amount above the selected address’s spendable balance.',
    'Quote evaluation uses the selected address’s spendable balance before publishing a ready quote.',
    {
      lowerBalanceOutcome,
      sufficientBalanceOutcome,
      sourceContract,
      error: evaluationError?.message,
    },
  );

  const focusStates = ['blank', 'malformed', 'zero', 'below-minimum', 'insufficient'];
  const focusActions = Object.fromEntries(focusStates.map((name) => {
    const literal = findNamedObjectLiteral(entryFunction, name) ?? '';
    return [name, /action\s*:\s*["']focus-amount["']/.test(literal)];
  }));
  const partial = findNamedObjectLiteral(entryFunction, 'partial') ?? '';
  const suspicious = findNamedObjectLiteral(entryFunction, 'suspicious-token') ?? '';
  const handler = extractFunction(source, 'handleCustomerAction') ?? '';
  const suspiciousIndex = handler.indexOf('suspicious-token');
  const suspiciousRecoveryRegion = suspiciousIndex >= 0
    ? handler.slice(suspiciousIndex, suspiciousIndex + 520)
    : '';
  const actionContracts = {
    focusConfigs: Object.values(focusActions).every(Boolean),
    partialConfig: /action\s*:\s*["']open-receive-asset["']/.test(partial),
    rendererUsesAction: /const\s+ctaAction\s*=\s*config\.action\s*\|\|/.test(renderEntry),
    focusHandler: /action\s*===\s*["']focus-amount["'][\s\S]{0,260}wallet-amount-input[\s\S]{0,180}\.focus\(/.test(handler),
    receiveAssetHandler: /action\s*===\s*["']open-receive-asset["']/.test(handler)
      && /customerSurface\s*=\s*[^;]*open-receive-asset[^;]*["']receive["']/.test(handler),
    suspiciousEnabled: /cta\s*:\s*["']Choose another asset["']/.test(suspicious)
      && !/disabled\s*:\s*true\b/.test(suspicious),
    suspiciousRecovery: (/action\s*:\s*["']open-receive-asset["']/.test(suspicious)
      || (/pickerFamily\s*=\s*["']asset["']/.test(suspiciousRecoveryRegion)
        && /customerSurface\s*=\s*["']receive["']/.test(suspiciousRecoveryRegion))),
  };
  assert(
    'interactions.entry-recovery-actions',
    Object.values(actionContracts).every(Boolean),
    'An incomplete, invalid, insufficient, or suspicious entry state exposes a non-executable recovery CTA.',
    'Entry recovery CTAs focus the amount or open the receiving-asset picker, including the enabled suspicious-token alternative.',
    { focusActions, ...actionContracts },
  );
}

function verifyAccessibilityVariantControls(source) {
  const controlValues = [
    'text-scale-100', 'text-scale-200', 'motion-standard', 'motion-reduced',
    'theme-light', 'theme-dark', 'viewport-375', 'viewport-390',
    'viewport-768', 'viewport-1024', 'viewport-1440',
  ];
  const dynamicControlAttribute = /data-a11y-control\s*=\s*["'][^"']*\$\{[^}]+\}[^"']*["']/.test(source);
  const missingControls = controlValues.filter((value) => {
    const directAttribute = source.includes(`data-a11y-control="${value}"`)
      || source.includes(`data-a11y-control='${value}'`);
    const splitAt = value.lastIndexOf('-');
    const setting = value.slice(0, splitAt);
    const option = value.slice(splitAt + 1);
    const declaredChoice = new RegExp(`choice\\(\\s*["']${setting}["']\\s*,\\s*["']${option}["']`).test(source);
    const declaredViewport = setting === 'viewport'
      && /data-a11y-control=["']viewport-\$\{width\}["']/.test(source)
      && new RegExp(`["']${option}["']`).test(source);
    const declaredForDynamicAttribute = dynamicControlAttribute && (declaredChoice || declaredViewport);
    return !directAttribute && !declaredForDynamicAttribute;
  });
  const hasReset = /data-a11y-action\s*=\s*["']reset["']/.test(source);
  const hasStateDerivedPressed = /aria-pressed\s*=\s*["']\$\{[^}]+\}["']/.test(source);
  const hasVisibleCheck = /(?:ri-check(?:-line)?|checkmark|✓)/i.test(source);
  assert(
    'accessibility.variant-controls-selected',
    missingControls.length === 0 && hasReset && hasStateDerivedPressed && hasVisibleCheck,
    'Accessibility variants do not expose complete, visible, state-derived selection controls.',
    'Accessibility variants expose paired selections, visible checks, and a reset action.',
    { missingControls, hasReset, hasStateDerivedPressed, hasVisibleCheck },
  );

  const focusContracts = {
    stableKey: /data-focus-key\s*=/.test(source),
    capture: /document\.activeElement\?\.dataset\.focusKey/.test(source)
      || /document\.activeElement[\s\S]{0,100}dataset\.focusKey/.test(source),
    restoreLookup: /\[data-focus-key=[^\]]+\]/.test(source)
      || /querySelectorAll\(\s*["']\[data-focus-key\]["']\s*\)[\s\S]{0,180}dataset\.focusKey\s*===\s*focusKey/.test(source),
    restoreFocus: /focus\(\{?preventScroll/.test(source) || /\.focus\(\)/.test(source),
  };
  assert(
    'accessibility.variant-controls-focus',
    Object.values(focusContracts).every(Boolean),
    'Variant rerenders do not restore focus by stable control identity.',
    'Variant rerenders capture and restore focus by stable control identity.',
    focusContracts,
  );

  const resetBranch = extractFunction(source, 'resetAccessibilityTests') ?? '';
  const resetDefaults = {
    viewport: /viewport\s*=\s*["']390["']/.test(resetBranch),
    theme: /theme\s*=\s*["']dark["']/.test(resetBranch),
    scale: /scale\s*=\s*1\b/.test(resetBranch),
    motion: /motion\s*=\s*["'](?:standard|full)["']/.test(resetBranch),
  };
  assert(
    'accessibility.variant-controls-reset',
    Object.values(resetDefaults).every(Boolean),
    'Reset tests does not restore the canonical 390px/dark/100%/standard configuration.',
    'Reset tests restores the canonical 390px/dark/100%/standard configuration.',
    resetDefaults,
  );
}

function verifyCombinedBrandIdentity(source) {
  const brandFunction = extractFunction(source, 'brandLogo') ?? '';
  const compactBranch = brandFunction.lastIndexOf('if (compact)');
  const fullIdentityBranch = compactBranch >= 0 ? brandFunction.slice(compactBranch) : brandFunction;
  const contract = {
    officialIcon: /logo\/icon\.svg/.test(brandFunction) && /\$\{icon\}/.test(fullIdentityBranch),
    darkWordmark: /logo\/logo_dark\.svg/.test(brandFunction),
    lightWordmark: /logo\/logo\.svg/.test(brandFunction),
    singleAnnouncement: (/role=["']img["'][^>]*aria-label=["']Gleec["']/.test(fullIdentityBranch)
      && !/alt=["']Gleec["']/.test(fullIdentityBranch))
      || (/alt=["']Gleec["']/.test(fullIdentityBranch)
        && /icon\.svg[^>]*alt=["']["']/.test(brandFunction)),
  };
  assert(
    'branding.combined-icon-wordmark',
    Object.values(contract).every(Boolean),
    'The wallet header brand does not combine the official icon and theme-aware wordmark as one accessible identity.',
    'The wallet header combines the official icon and theme-aware wordmark as one accessible identity.',
    contract,
  );
}

function verifyReviewProgressiveDisclosure(source) {
  const renderReview = extractFunction(source, 'renderReviewPreview') ?? '';
  const reviewContracts = {
    summary: /data-review-summary/.test(renderReview),
    costs: /Costs (?:&|&amp;) protection/.test(renderReview),
    route: /Route (?:&|&amp;) identities/.test(renderReview),
    permission: /data-review-permission|review-permission-shield/.test(renderReview),
    nativePermission: /No token approval needed\.?/.test(source),
    exactPermission: /for this swap only\s+—\s+never unlimited\./.test(source),
    totalCost: /Total cost/.test(renderReview),
    completion: /Estimated completion/.test(renderReview),
    maximumCost: /Maximum network cost/.test(renderReview),
  };
  assert(
    'review.progressive-disclosure',
    Object.values(reviewContracts).every(Boolean),
    'Review does not implement the approved concise summary and progressive-disclosure hierarchy.',
    'Review keeps decision facts visible and moves supporting detail into two focused disclosures.',
    reviewContracts,
  );

  const stateContracts = {
    revalidating: /["']revalidating["']/.test(source),
    failed: /["']revalidation-failed["']/.test(source),
    busy: /revalidating[\s\S]{0,900}aria-busy/.test(source)
      || /aria-busy[\s\S]{0,900}revalidating/.test(source),
    retry: /revalidation-failed[\s\S]{0,900}(?:retry|refresh)/i.test(source),
  };
  assert(
    'review.revalidation-states',
    Object.values(stateContracts).every(Boolean),
    'Review is missing deterministic revalidation loading and recovery states.',
    'Review exposes deterministic revalidation, failure, and retry behavior.',
    stateContracts,
  );
}

function verifyQaResult(source, artifactSource) {
  const heading = /^##\s+Final result\s*$/im.exec(source);
  let resultLine = null;
  if (heading) {
    resultLine = source
      .slice((heading.index ?? 0) + heading[0].length)
      .split('\n')
      .map((line) => line.trim())
      .find(Boolean) ?? null;
  }
  assert(
    'qa.final-result-section',
    Boolean(heading && resultLine),
    'The design QA record is missing an explicit `## Final result` section.',
    'The design QA record includes an explicit final result.',
    resultLine,
  );
  if (resultLine) {
    assert(
      'qa.final-result-pass',
      /^(?:pass|passed)\b/i.test(resultLine),
      'The design QA final result is not PASS/Passed.',
      'The design QA final result is PASS/Passed.',
      resultLine,
    );
  }

  const expectedHash = sha256(artifactSource);
  assert(
    'qa.artifact-hash',
    source.includes(expectedHash),
    'The QA record is not bound to the current artifact SHA-256.',
    'The QA record records the current artifact SHA-256.',
    { expectedHash },
  );

  const fixtureLiteral = evaluateLiteral(extractInitializer(artifactSource, ['canonicalJourneyFixtures', 'journeyFixtures']));
  const fixtureCount = Object.keys(journeyCollection(fixtureLiteral) || {}).length;
  const expectedAssertionCount = fixtureCount ? fixtureCount * 11 + 8 : null;
  if (expectedAssertionCount) {
    const assertionRecord = new RegExp(`${expectedAssertionCount}\\/${expectedAssertionCount}\\s+(?:fixture\\s+)?assertions?`, 'i');
    assert(
      'qa.fixture-assertion-count',
      assertionRecord.test(source),
      `The QA record does not record the current ${expectedAssertionCount}/${expectedAssertionCount} fixture assertion count.`,
      'The QA record matches the artifact fixture assertion count.',
    );
  }
}

function verifyRemediationCopy(source) {
  const obsoleteApproval = sourceMatches(source, />\s*Approval cost\s*</gi);
  assert(
    'copy.approval-network-cost',
    obsoleteApproval.length === 0,
    'The customer UI still labels approval gas as “Approval cost” instead of “Approval network cost.”',
    'Approval gas is not presented as a separate provider/swap fee.',
    obsoleteApproval,
  );

  const ambiguousClaim = sourceMatches(source, /funds\s+remain\s+at\s+the\s+last\s+confirmed\s+location/gi);
  assert(
    'copy.ambiguous-broadcast',
    ambiguousClaim.length === 0,
    'Ambiguous-broadcast copy still fabricates a current fund location.',
    'Ambiguous-broadcast copy does not fabricate a current fund location.',
    ambiguousClaim,
  );

  assert(
    'copy.mixed-not-reserved',
    /middle\s+(?:exchange|order)[\s\S]{0,120}(?:isn[’']t|is\s+not)\s+reserved/i.test(source),
    'Missing the required mixed-route disclosure that the middle exchange/order is not reserved.',
    'The mixed-route not-reserved disclosure is present.',
  );
}

function printResults() {
  const payload = {
    artifact: artifactPath,
    qa: qaPath,
    artifactSha256: artifact === null ? null : sha256(artifact),
    qaSha256: qa === null ? null : sha256(qa),
    result: failures.length === 0 ? 'PASS' : 'FAIL',
    totals: { passed: passes.length, warnings: warnings.length, failed: failures.length },
    failures,
    warnings,
    passes,
  };

  if (jsonOutput) {
    process.stdout.write(`${JSON.stringify(payload, null, 2)}\n`);
    return;
  }

  process.stdout.write(`Gleec Unified Swap design verification: ${payload.result}\n`);
  process.stdout.write(`Artifact: ${artifactPath}\n`);
  process.stdout.write(`QA record: ${qaPath}\n`);
  process.stdout.write(`Checks: ${passes.length} passed, ${warnings.length} warnings, ${failures.length} failed\n`);

  if (failures.length > 0) {
    process.stdout.write('\nFailures\n');
    failures.forEach((entry, index) => {
      process.stdout.write(`${index + 1}. [${entry.id}] ${entry.message}\n`);
      if (entry.detail !== undefined) process.stdout.write(`   ${JSON.stringify(entry.detail)}\n`);
    });
  }
  if (warnings.length > 0) {
    process.stdout.write('\nWarnings\n');
    warnings.forEach((entry, index) => {
      process.stdout.write(`${index + 1}. [${entry.id}] ${entry.message}\n`);
      if (entry.detail !== undefined) process.stdout.write(`   ${JSON.stringify(entry.detail)}\n`);
    });
  }
}
