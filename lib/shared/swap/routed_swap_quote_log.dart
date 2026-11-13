part of 'routed_swap_source.dart';

/// One line per failed routed quote or catalog read, for the app's exportable
/// log: which step failed, in KDF's words. A provider that can't be reached
/// and an approval that can't be estimated share a type and a copy, and only
/// the words tell them apart.
///
/// [DiagnosticSanitizer] drops a whole record over a bracket, a URL, a long
/// hex run or a sensitive label, so KDF's text is cleaned first, and a line
/// it would still drop is written without the text. An address, an amount or
/// raw error data is never written.
abstract final class _RoutedQuoteLog {
  static const _quoteHead = 'Swap quote failed: source=routed';
  static const _catalogHead = 'Swap catalog failed: source=routed';
  static const _maxText = 160;

  static final _control = RegExp(r'[\x00-\x1f\x7f]');
  static final _url = RegExp(r'[a-z][a-z0-9+.-]*://\S*', caseSensitive: false);
  static final _opening = RegExp(r'[{\[]');
  static final _closing = RegExp(r'[}\]]');
  static final _prefixedHex = RegExp(r'0x[0-9a-f]{6,}', caseSensitive: false);
  static final _longHex = RegExp(r'[0-9a-f]{32,}', caseSensitive: false);
  static final _space = RegExp(r'\s+');
  static final _unsafeToken = RegExp(r'[^A-Za-z0-9_.:-]');

  static String timedOut(
    AssetId from,
    AssetId to,
    SwapQuoteOrder order,
    Duration after,
  ) => '${_quote(from, to, order)} kind=timeout after=${after.inSeconds}s';

  static String refused(
    AssetId from,
    AssetId to,
    SwapQuoteOrder order,
    SwapQuoteFailureKind kind,
    RoutedSwapRpcException error,
  ) => _withText(
    '${_quote(from, to, order)} kind=${kind.name} ${_typed(error)}',
    error,
  );

  static String unexpected(
    AssetId from,
    AssetId to,
    SwapQuoteOrder order,
    Object error,
  ) =>
      '${_quote(from, to, order)} kind=unknown '
      'error=${DiagnosticSanitizer.safeError(error)}';

  static String catalog(Object error, {required Duration timeout}) =>
      switch (error) {
        TimeoutException() =>
          '$_catalogHead kind=timeout after=${timeout.inSeconds}s',
        final RoutedSwapRpcException rpc => _withText(
          '$_catalogHead ${_typed(rpc)}',
          rpc,
        ),
        _ => '$_catalogHead error=${DiagnosticSanitizer.safeError(error)}',
      };

  static String _quote(AssetId from, AssetId to, SwapQuoteOrder order) =>
      '$_quoteHead pair=${from.id}/${to.id} order=${order.name}';

  /// The error's type, the parameter it names, and the provider's request id
  /// when one can be written whole.
  static String _typed(RoutedSwapRpcException error) {
    final param = switch (error) {
      RoutedSwapAmountOutOfBoundsException(:final param) ||
      RoutedSwapInvalidParamException(:final param) => _token(param),
      _ => '',
    };
    final request = _token(error.providerRequestId ?? '');
    return [
      'type=${_token(error.errorType)}',
      if (param.isNotEmpty) 'param=$param',
      if (request.isNotEmpty && !_longHex.hasMatch(request)) 'request=$request',
    ].join(' ');
  }

  /// [line] with KDF's message, unless the sanitizer would drop it. An
  /// out-of-bounds message quotes the amount, so it is left out.
  static String _withText(String line, RoutedSwapRpcException error) {
    if (error is RoutedSwapAmountOutOfBoundsException) return line;
    final text = _clean(error.message);
    if (text.isEmpty) return line;
    final full = '$line message=$text';
    return DiagnosticSanitizer.sanitizeMessage(full) == null
        ? '$line text=omitted'
        : full;
  }

  static String _clean(String text) {
    final clean = text
        .replaceAll(_control, ' ')
        .replaceAll(_url, '<url>')
        .replaceAll(_opening, '(')
        .replaceAll(_closing, ')')
        .replaceAll(_prefixedHex, '0x…')
        .replaceAll(_longHex, '…')
        .replaceAll(_space, ' ')
        .trim();
    return clean.length <= _maxText
        ? clean
        : '${clean.substring(0, _maxText - 1)}…';
  }

  static String _token(String value) {
    final token = value.replaceAll(_unsafeToken, '');
    return token.length <= 64 ? token : token.substring(0, 64);
  }
}
