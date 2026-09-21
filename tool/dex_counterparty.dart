// ignore_for_file: avoid_print

/// Runs a second KDF node that offers a real order for the DEX taker test.
///
/// The taker half of `dex_tests` sells DOC to buy MARTY, so it needs somebody
/// offering MARTY. Nobody does: the testnet pair has no standing maker, and the
/// only other order in the book is the maker half's own, placed from the same
/// wallet on the same node - which the self-trade guard correctly refuses. The
/// suite has therefore been red on every branch since 2026-08-12, failing at
/// `tapAndPump(BestOrder-table-item-MARTY)` with `Bad state: No element`,
/// because the row it wants is never built.
///
/// This process is that missing counterparty. It runs the same KDF build the
/// app ships, on a different funded wallet reserved by `getCounterpartyWif`, so
/// the order it places is somebody else's as far as the app is concerned. The
/// order reaches the app the way any real order would, over the p2p network -
/// this does not stub the orderbook.
///
/// Usage:
///
/// ```
/// dart run tool/dex_counterparty.dart --kdf <path-to-kdf> [--slot 0]
/// ```
///
/// Prints `DEX_COUNTERPARTY_READY` once the order is visible in its own
/// orderbook, then idles until it is signalled, cancelling its orders on the
/// way out. Every other line is prefixed so the CI log stays readable.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import '../test_integration/helpers/get_funded_wif.dart';

const _readyMarker = 'DEX_COUNTERPARTY_READY';
const _netId = 6133;

/// Offered side: the coin the taker is trying to buy.
const _base = 'MARTY';

/// Wanted side: the coin the taker is selling.
const _rel = 'DOC';

/// Priced so the taker's 0.01 DOC buys a round amount and the order is the
/// cheapest MARTY on the book, which is what `best_orders` surfaces first.
const _price = '0.4';

/// Far more than the taker's 0.01 DOC can consume, so one run cannot exhaust
/// it and a retry does not need a fresh order.
const _volume = '0.1';

Future<void> main(List<String> args) async {
  final options = _Options.parse(args);
  final log = _Log('counterparty');

  // Each of these reads a file the build produced. A missing or unexpected one
  // used to throw straight out of `main`, which exits with a stack trace and no
  // indication of which path was at fault - and, from CI, with the process
  // simply gone.
  final Map<String, dynamic> coinsConfig;
  final List<dynamic> coinsList;
  final List<String> seedNodes;
  try {
    coinsConfig = _readJsonMap(options.coinsConfigPath);
    coinsList = _readJsonList(options.coinsPath);
    seedNodes = _seedNodesFor(options.seedNodesPath);
  } on Object catch (error) {
    log
      ..line('FAILED: could not read the generated coin configuration: $error')
      ..line('  coins:        ${options.coinsPath}')
      ..line('  coins config: ${options.coinsConfigPath}')
      ..line('  seed nodes:   ${options.seedNodesPath}');
    for (final path in [
      options.coinsPath,
      options.coinsConfigPath,
      options.seedNodesPath,
    ]) {
      final file = File(path);
      log.line(
        '  $path exists=${file.existsSync()} '
        'size=${file.existsSync() ? file.lengthSync() : 0}',
      );
    }
    exit(1);
  }
  log.line('coins=${coinsList.length} seednodes=${seedNodes.length}');

  final rpcPassword = _generateRpcPassword();
  final passphrase = getCounterpartyWif(options.slot);
  final dbDir = await Directory.systemTemp.createTemp('dex_counterparty_');

  final startParams = <String, dynamic>{
    'mm2': 1,
    'allow_weak_password': false,
    'rpc_password': rpcPassword,
    'netid': _netId,
    'gui': 'gleec-wallet-dex-counterparty',
    'passphrase': passphrase,
    'dbdir': dbDir.path,
    'rpcport': options.rpcPort,
    'rpcip': '127.0.0.1',
    'rpc_local_only': true,
    'allow_registrations': true,
    'https': false,
    // Deliberately NOT 'coins': the list goes to the child through
    // MM_COINS_PATH below, exactly as KdfOperationsLocalExecutable does it and
    // for the reason it gives - a single argv string is capped, and on Linux
    // that cap is MAX_ARG_STRLEN, 32 pages, 131072 bytes. Compact-encoded this
    // list is ~282 KB, so passing it here made execve fail with E2BIG on every
    // Linux run while macOS, whose limit is a 1 MiB total, started fine.
    // Left on deliberately. The whole point is that the order leaves this node
    // and reaches the browser's own KDF the way a stranger's order would.
    'disable_p2p': false,
    if (seedNodes.isNotEmpty) 'seednodes': seedNodes,
  };

  final coinsFile = File('${dbDir.path}/kdf_coins.json');
  await coinsFile.writeAsString(jsonEncode(coinsList), flush: true);

  // Checked before spawning so a missing or non-executable binary says so,
  // instead of surfacing as an opaque ProcessException out of Process.start.
  final binary = File(options.kdfPath);
  if (!binary.existsSync()) {
    log.line('FAILED: no KDF binary at ${options.kdfPath}');
    exit(1);
  }
  final stat = binary.statSync();
  log.line(
    'kdf binary ${options.kdfPath} (${stat.size} bytes, ${stat.modeString()})',
  );

  log.line('starting kdf on port ${options.rpcPort}');
  final Process process;
  try {
    process = await Process.start(
      options.kdfPath,
      [jsonEncode(startParams)],
      environment: {...Platform.environment, 'MM_COINS_PATH': coinsFile.path},
    );
  } on Object catch (error) {
    // Rendered without argv. ProcessException.toString() appends the whole
    // command line, and that argv element carries the wallet passphrase.
    final detail = error is ProcessException
        ? '${error.message} (errno ${error.errorCode})'
        : '$error';
    log.line('FAILED: could not start the KDF binary: $detail');
    await dbDir.delete(recursive: true).catchError((Object _) => dbDir);
    exit(1);
  }

  // KDF's own output carries the startup config, which holds the passphrase, so
  // a line is forwarded only with the password redacted out of it.
  unawaited(
    process.stderr.transform(utf8.decoder).transform(const LineSplitter()).forEach((
      line,
    ) {
      final lowered = line.toLowerCase();
      if (lowered.contains('error') || lowered.contains('panic')) {
        log.line(
          'kdf: ${line.replaceAll(rpcPassword, '<rpc-password>').replaceAll(passphrase, '<passphrase>')}',
        );
      }
    }),
  );
  unawaited(process.stdout.drain<void>());
  // An exit before the RPC answers is the difference between "KDF is slow" and
  // "KDF is gone", and the startup timeout alone cannot tell them apart.
  unawaited(
    process.exitCode.then((code) => log.line('kdf exited with code $code')),
  );

  final rpc = _Rpc(
    Uri.parse('http://127.0.0.1:${options.rpcPort}'),
    rpcPassword,
    passphrase,
    log,
  );

  var cleanedUp = false;
  Future<void> cleanUp(String why) async {
    if (cleanedUp) return;
    cleanedUp = true;
    log.line('stopping ($why)');
    await _reportSwaps(rpc, log);
    try {
      await rpc
          .call({
            'method': 'cancel_all_orders',
            'cancel_by': {'type': 'All'},
          })
          .timeout(const Duration(seconds: 10));
      log.line('orders cancelled');
    } on Object catch (error) {
      log.line('could not cancel orders: $error');
    }
    process.kill(ProcessSignal.sigterm);
    await Future<void>.delayed(const Duration(seconds: 2));
    process.kill(ProcessSignal.sigkill);
    await dbDir.delete(recursive: true).catchError((Object _) => dbDir);
  }

  for (final signal in [ProcessSignal.sigint, ProcessSignal.sigterm]) {
    signal.watch().listen((_) async {
      await cleanUp(signal.toString());
      exit(0);
    });
  }

  try {
    await rpc.waitUntilReady(options.startupTimeout);
    log.line('kdf is up');

    for (final coin in [_base, _rel]) {
      await _activate(rpc, coin, coinsConfig, log);
    }

    final balance = await _balanceOf(rpc, _base);
    log.line('$_base balance=$balance');
    if (balance <= Decimalish.parse(_volume)) {
      throw StateError(
        'Counterparty wallet ${options.slot} holds $balance $_base, which is '
        'not enough to offer $_volume. Reserved wallets are funded from the '
        'same faucet as the app under test; top this one up or move to '
        'another slot.',
      );
    }

    log.line('placing $_volume $_base at $_price $_rel');
    final order = await rpc.call({
      'method': 'setprice',
      'base': _base,
      'rel': _rel,
      'price': _price,
      'volume': _volume,
      'cancel_previous': true,
    });
    final uuid = (order['result'] as Map?)?['uuid'];
    log.line('order uuid=$uuid');

    await _waitUntilOnBook(rpc, log, options.bookTimeout);
    print(_readyMarker);
  } on Object catch (error, stack) {
    log.line('FAILED: $error');
    log.line('$stack');
    await cleanUp('startup failure');
    exit(1);
  }

  // Idle. The suite kills this process when it is done with the order.
  await ProcessSignal.sigterm.watch().first;
  await cleanUp('signalled');
}

/// Reports any swap this node took part in, before it shuts down.
///
/// The taker side can only say that the swap did not reach success. This side
/// knows whether the order was taken at all and which event it stopped on,
/// which is the difference between "nobody matched us" and "we matched and the
/// swap stalled" - and those have opposite fixes.
Future<void> _reportSwaps(_Rpc rpc, _Log log) async {
  try {
    final response = await rpc
        .call({'method': 'my_recent_swaps', 'limit': 10})
        .timeout(const Duration(seconds: 15));
    final swaps = ((response['result'] as Map?)?['swaps'] as List?) ?? [];
    if (swaps.isEmpty) {
      log.line('no swaps: the order was never taken');
      return;
    }
    log.line('took part in ${swaps.length} swap(s)');
    for (final entry in swaps) {
      final swap = entry as Map<String, dynamic>;
      final events = (swap['events'] as List? ?? [])
          .map((e) => ((e as Map)['event'] as Map?)?['type'])
          .whereType<String>()
          .toList();
      log.line(
        '  uuid=${swap['uuid']} type=${swap['type']} '
        'pair=${swap['my_coin']}/${swap['other_coin']}',
      );
      log.line('  events: ${events.join(' -> ')}');
    }
  } on Object catch (error) {
    log.line('could not read swaps: $error');
  }
}

Future<void> _activate(
  _Rpc rpc,
  String coin,
  Map<String, dynamic> coinsConfig,
  _Log log,
) async {
  final entry = coinsConfig[coin] as Map<String, dynamic>?;
  if (entry == null) {
    throw StateError('$coin is missing from the coins configuration');
  }
  // TCP only. This is a native process on a CI runner, not the browser, so the
  // WSS endpoints the app uses buy nothing here and SSL adds a failure mode.
  final servers = (entry['electrum'] as List? ?? [])
      .cast<Map<String, dynamic>>()
      .where((server) => server['protocol'] == 'TCP')
      .map((server) => {'url': server['url']})
      .toList();
  if (servers.isEmpty) {
    throw StateError('$coin has no plaintext electrum servers to connect to');
  }

  log.line('activating $coin over ${servers.length} electrum servers');
  final response = await rpc.call({
    'method': 'electrum',
    'coin': coin,
    'servers': servers,
    'mm2': 1,
  });
  log.line('$coin activated: ${response['address'] ?? response['result']}');
}

Future<Decimalish> _balanceOf(_Rpc rpc, String coin) async {
  final response = await rpc.call({'method': 'my_balance', 'coin': coin});

  return Decimalish.parse('${response['balance'] ?? '0'}');
}

/// Waits until the order is actually on this node's book.
///
/// Placing an order and assuming it is live is how the suite got into this
/// state in the first place. A `setprice` that is accepted but never reaches
/// the book leaves the app waiting on a row that will not come, so the ready
/// marker is only printed once the order can be read back.
Future<void> _waitUntilOnBook(_Rpc rpc, _Log log, Duration timeout) async {
  final deadline = DateTime.now().add(timeout);
  var attempt = 0;
  while (DateTime.now().isBefore(deadline)) {
    attempt++;
    final book = await rpc.call({
      'method': 'orderbook',
      'base': _base,
      'rel': _rel,
    });
    final asks = (book['asks'] as List? ?? []).length;
    log.line('orderbook attempt $attempt: $asks ask(s) for $_base/$_rel');
    if (asks > 0) return;
    await Future<void>.delayed(const Duration(seconds: 3));
  }
  throw TimeoutException(
    'The order never appeared on the $_base/$_rel book within $timeout',
  );
}

class _Rpc {
  _Rpc(this.endpoint, this._password, this._passphrase, this._log);

  final Uri endpoint;
  final String _password;
  final String _passphrase;
  final _Log _log;
  final HttpClient _client = HttpClient();

  Future<Map<String, dynamic>> call(Map<String, dynamic> body) async {
    final request = await _client.postUrl(endpoint);
    request.headers.contentType = ContentType.json;
    request.write(jsonEncode({...body, 'userpass': _password}));
    final response = await request.close();
    final text = await response.transform(utf8.decoder).join();
    if (response.statusCode != 200) {
      throw StateError(
        'RPC ${body['method']} answered ${response.statusCode}: '
        '${_redact(text)}',
      );
    }
    final decoded = jsonDecode(text);
    if (decoded is! Map<String, dynamic>) {
      throw StateError(
        'RPC ${body['method']} answered a ${decoded.runtimeType}',
      );
    }
    if (decoded['error'] != null) {
      throw StateError(
        'RPC ${body['method']} failed: ${_redact('${decoded['error']}')}',
      );
    }
    return decoded;
  }

  Future<void> waitUntilReady(Duration timeout) async {
    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      try {
        final version = await call({'method': 'version'});
        _log.line('kdf version=${version['result']}');
        return;
      } on Object {
        await Future<void>.delayed(const Duration(seconds: 1));
      }
    }
    throw TimeoutException('KDF RPC did not become ready within $timeout');
  }

  /// Keeps the RPC password and the wallet passphrase out of what is printed.
  ///
  /// The passphrase matters because this log is read from a public CI job and
  /// uploaded as an artifact. Today's wallets are the public test ones in
  /// `get_funded_wif.dart`, so nothing secret is at stake - but the redaction
  /// has to be real before anyone points this at a wallet that is.
  String _redact(String text) => text
      .replaceAll(_password, '<rpc-password>')
      .replaceAll(_passphrase, '<passphrase>');
}

class _Log {
  _Log(this.prefix);

  final String prefix;

  void line(String message) => print('[$prefix] $message');
}

/// Just enough decimal to compare a balance against an offer.
///
/// Balances arrive as strings and can carry more precision than a double
/// represents exactly; comparing them as text would be worse.
class Decimalish {
  const Decimalish(this._scaled);

  /// Reads a plain decimal string such as `12.3456`.
  factory Decimalish.parse(String value) {
    final parts = value.split('.');
    final whole = BigInt.parse(parts.first.isEmpty ? '0' : parts.first);
    final fractionText = parts.length > 1 ? parts[1] : '';
    final padded = fractionText.padRight(_scale, '0').substring(0, _scale);

    return Decimalish(
      whole * BigInt.from(10).pow(_scale) + BigInt.parse(padded),
    );
  }

  static const int _scale = 12;

  final BigInt _scaled;

  bool operator <=(Decimalish other) => _scaled <= other._scaled;

  @override
  String toString() {
    final divisor = BigInt.from(10).pow(_scale);

    return '${_scaled ~/ divisor}.'
        '${(_scaled % divisor).toString().padLeft(_scale, '0')}';
  }
}

class _Options {
  _Options({
    required this.kdfPath,
    required this.slot,
    required this.rpcPort,
    required this.coinsPath,
    required this.coinsConfigPath,
    required this.seedNodesPath,
    required this.startupTimeout,
    required this.bookTimeout,
  });

  factory _Options.parse(List<String> args) {
    String? valueOf(String name) {
      final index = args.indexOf('--$name');

      return index >= 0 && index + 1 < args.length ? args[index + 1] : null;
    }

    final kdfPath = valueOf('kdf');
    if (kdfPath == null) {
      stderr.writeln('Usage: dart run tool/dex_counterparty.dart --kdf <path>');
      exit(64);
    }

    const assets = 'sdk/packages/komodo_defi_framework/assets/config';

    return _Options(
      kdfPath: kdfPath,
      slot: int.parse(valueOf('slot') ?? '0'),
      rpcPort: int.parse(valueOf('rpc-port') ?? '7791'),
      coinsPath: valueOf('coins') ?? '$assets/coins.json',
      coinsConfigPath: valueOf('coins-config') ?? '$assets/coins_config.json',
      seedNodesPath: valueOf('seed-nodes') ?? '$assets/seed_nodes.json',
      startupTimeout: Duration(seconds: int.parse(valueOf('startup') ?? '120')),
      bookTimeout: Duration(seconds: int.parse(valueOf('book') ?? '180')),
    );
  }

  final String kdfPath;
  final int slot;
  final int rpcPort;
  final String coinsPath;
  final String coinsConfigPath;
  final String seedNodesPath;
  final Duration startupTimeout;
  final Duration bookTimeout;
}

Map<String, dynamic> _readJsonMap(String path) =>
    jsonDecode(File(path).readAsStringSync()) as Map<String, dynamic>;

List<dynamic> _readJsonList(String path) =>
    jsonDecode(File(path).readAsStringSync()) as List<dynamic>;

/// The same netid the app uses, so both nodes meet on the same network.
List<String> _seedNodesFor(String path) {
  final nodes = _readJsonList(path).cast<Map<String, dynamic>>();

  return nodes
      .where((node) => node['netid'] == _netId)
      .map((node) => '${node['host']}')
      .toList();
}

String _generateRpcPassword() {
  const alphabet = 'abcdefghijkmnopqrstuvwxyzABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  final random = Random.secure();

  // KDF rejects weak passwords, so this needs a digit and both cases; drawing
  // 24 characters from the pool above makes that overwhelmingly likely, and
  // the explicit tail guarantees it.
  final body = List.generate(
    24,
    (_) => alphabet[random.nextInt(alphabet.length)],
  ).join();

  return 'Cp$body-7';
}
