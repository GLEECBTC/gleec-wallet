/// Unsigned form input retained only while this wallet session remains open.
typedef SwapDraft = ({
  String? pay,
  String? receive,
  String input,
  bool fiat,
  double slippage,
});

/// A late widget disposal cannot restore amounts after a wallet boundary.
class SwapSessionDraft {
  Object _session = Object();
  SwapDraft? _draft;

  Object get session => _session;

  SwapDraft? read(Object session) =>
      identical(session, _session) ? _draft : null;

  void remember(Object session, SwapDraft? draft) {
    if (identical(session, _session)) _draft = draft;
  }

  void reset() {
    _session = Object();
    _draft = null;
  }
}
