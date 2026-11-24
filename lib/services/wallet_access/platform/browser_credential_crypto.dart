part of 'browser_credential_vault.dart';

// Keep the v1 structured-clone fields and CryptoKey objects readable across
// compilers and releases. An encrypted record is never converted with dartify.
extension type BrowserCredentialRecord.raw(JSObject _) implements JSObject {
  external factory BrowserCredentialRecord({
    required int schema,
    required String key,
    required int revision,
    required String protection,
    required String origin,
    web.CryptoKey unattendedKey,
    String rpId,
    String credentialId,
    String enrollmentId,
    JSObject userHandle,
    JSObject prfInput,
    JSObject publicKey,
    int algorithm,
  });

  external JSAny? get schema;
  external String get key;
  @JS('revision')
  external JSAny? get rawRevision;
  @JS('revision')
  external set rawRevision(JSAny? value);
  int? get revision => _safeInteger(rawRevision);
  external String get protection;
  external String get origin;
  external String? get rpId;
  external String? get credentialId;
  external String? get enrollmentId;
  external JSObject? get userHandle;
  external JSObject? get prfInput;
  external JSObject? get publicKey;
  @JS('algorithm')
  external JSAny? get rawAlgorithm;
  int? get algorithm => _safeInteger(rawAlgorithm);
  external web.CryptoKey? get unattendedKey;
  external JSObject? get iv;
  external set iv(JSObject value);
  external JSObject? get ciphertext;
  external set ciphertext(JSObject value);
}

@JS('Object.assign')
external JSObject _assign(JSObject target, JSObject source);

BrowserCredentialRecord _copyRecord(BrowserCredentialRecord record) =>
    BrowserCredentialRecord.raw(_assign(JSObject(), record));

@JS('ArrayBuffer.isView')
external bool _isBufferView(JSAny? value);

extension type _BufferView(JSObject _) implements JSObject {
  external JSArrayBuffer get buffer;
  external int get byteOffset;
  external int get byteLength;
}

extension type _MutableBytes(JSUint8Array _) implements JSUint8Array {
  external void fill(int value);
}

JSUint8Array _byteView(JSAny? value) {
  if (value.isA<JSUint8Array>()) return value as JSUint8Array;
  if (value.isA<JSArrayBuffer>()) return JSUint8Array(value as JSArrayBuffer);
  if (_isBufferView(value)) {
    final view = value as _BufferView;
    return JSUint8Array(view.buffer, view.byteOffset, view.byteLength);
  }
  _fail('invalidResponse');
}

Uint8List _bytes(JSAny? value) => _byteView(value).toDart;

String _base64Url(List<int> value) =>
    base64Url.encode(value).replaceAll('=', '');

final _urlAlphabet = RegExp(r'^[A-Za-z0-9_-]+$');

Uint8List _fromBase64Url(Object? value) {
  if (value is! String || !_urlAlphabet.hasMatch(value)) {
    _fail('invalidResponse');
  }
  try {
    return base64Url.decode(base64Url.normalize(value));
  } on FormatException {
    _fail('invalidResponse');
  }
}

JSObject _object(Map<String, Object?> values) => values.jsify() as JSObject;

extension type _PrfOutput(JSObject _) implements JSObject {
  external JSAny? get enabled;
  external _PrfValues? get results;
}

extension type _PrfValues(JSObject _) implements JSObject {
  external JSObject? get first;
}

extension type _CredentialExtensions(JSObject _) implements JSObject {
  external _PrfOutput? get prf;
}

// Keep BufferSource values opaque until the byte conversion. Existing records
// and test providers can use either ArrayBuffer or a view of one.
extension type _PublicKeyResponse(JSObject _) implements JSObject {
  external JSObject? get rawId;
  external JSObject? get response;
  external _CredentialExtensions? getClientExtensionResults();
}

extension type _ClientDataResponse(JSObject _) implements JSObject {
  external JSObject? get clientDataJSON;
}

extension type _AssertionResponse(JSObject _) implements _ClientDataResponse {
  external JSObject? get userHandle;
  external JSObject? get authenticatorData;
  external JSObject? get signature;
}

extension type _AttestationResponse(JSObject _) implements _ClientDataResponse {
  external JSObject? getAuthenticatorData();
  external JSObject? getPublicKey();
  external JSAny? getPublicKeyAlgorithm();
}

// WebAuthn ES256 signatures are DER. WebCrypto verifies their P1363 encoding.
Uint8List _es256Signature(Uint8List input) {
  if (input.length < 8 ||
      input.length > 72 ||
      input[0] != 0x30 ||
      input[1] != input.length - 2) {
    _fail('invalidResponse');
  }
  final output = Uint8List(64);
  var offset = 2;
  for (var part = 0; part < 2; part++) {
    if (offset + 2 > input.length || input[offset++] != 0x02) {
      _fail('invalidResponse');
    }
    final length = input[offset++];
    if (length == 0 ||
        length > 33 ||
        offset + length > input.length ||
        (input[offset] & 0x80) != 0) {
      _fail('invalidResponse');
    }
    var integer = Uint8List.sublistView(input, offset, offset + length);
    offset += length;
    if (integer.length > 1 && integer[0] == 0) {
      if ((integer[1] & 0x80) == 0) _fail('invalidResponse');
      integer = Uint8List.sublistView(integer, 1);
    }
    if (integer.length > 32) _fail('invalidResponse');
    output.setAll(part * 32 + 32 - integer.length, integer);
  }
  if (offset != input.length) _fail('invalidResponse');
  return output;
}

extension _BrowserCredentialCrypto on BrowserCredentialVault {
  JSUint8Array _random(int length) {
    final bytes = JSUint8Array(JSArrayBuffer(length));
    _crypto.getRandomValues(bytes);
    return bytes;
  }

  String _identifier() => _base64Url(_random(18).toDart);

  JSArray<JSString> _cipherUsages() => ['encrypt'.toJS, 'decrypt'.toJS].toJS;

  Future<web.CryptoKey> _createLocalKey() async =>
      (await _subtle
              .generateKey(
                _object({'name': 'AES-GCM', 'length': 256}),
                false,
                _cipherUsages(),
              )
              .toDart)
          as web.CryptoKey;

  JSObject _cipherParams(BrowserCredentialRecord record, JSObject iv) =>
      _object({
        'name': 'AES-GCM',
        'iv': iv,
        'additionalData': utf8
            .encode(
              jsonEncode([
                _schema,
                record.key,
                record.protection,
                record.origin,
                record.rpId ?? '',
                record.credentialId ?? '',
                record.enrollmentId ?? '',
              ]),
            )
            .toJS,
        'tagLength': 128,
      });

  Future<String> _decrypt(
    BrowserCredentialRecord record,
    web.CryptoKey key,
  ) async {
    try {
      final iv = _byteView(record.iv);
      final cipher = _byteView(record.ciphertext);
      if (iv.toDart.length != 12 || cipher.toDart.length < 17) {
        _fail('envelopeCorrupt');
      }
      final plaintext = _byteView(
        await _subtle.decrypt(_cipherParams(record, iv), key, cipher).toDart,
      );
      try {
        return _secret(utf8.decode(plaintext.toDart));
      } finally {
        _MutableBytes(plaintext).fill(0);
      }
    } on Object {
      _fail('envelopeCorrupt');
    }
  }

  Future<void> _sealAndCommit(
    BrowserCredentialRecord? previous,
    BrowserCredentialRecord next,
    String value,
    web.CryptoKey key,
    _Operation operation,
  ) async {
    final encoded = utf8.encode(value);
    final plaintext = encoded.toJS;
    try {
      final iv = _random(12);
      next.iv = iv;
      next.ciphertext =
          (await _subtle
                  .encrypt(_cipherParams(next, iv), key, plaintext)
                  .toDart)
              as JSObject;
    } finally {
      encoded.fillRange(0, encoded.length, 0);
      _MutableBytes(plaintext).fill(0);
    }

    _assertCurrent(operation);
    final slot = await _store.stage(next, _identifier());
    try {
      final persisted = _validate(await _store.getStaged(slot), next.key);
      if (persisted.revision != next.revision ||
          await _decrypt(persisted, key) != value) {
        _fail('storageFailed');
      }
      _assertCurrent(operation);
      await _store.promote(
        next.key,
        previous?.revision,
        slot,
        next.revision!,
        operation.signal,
      );
      // Invalidate other tabs as soon as the old unlock path is replaced.
      _notify(next.key, next);
      final active = _validate(await _store.get(next.key), next.key);
      if (active.revision != next.revision ||
          active.protection != next.protection ||
          await _decrypt(active, key) != value) {
        _fail('storageFailed');
      }
      _assertCurrent(operation);
    } finally {
      // Staged rows are never read as active. Later promotion or deletion
      // also removes any rows left behind by a crash.
      try {
        await _store.discardStage(slot);
      } on Object {
        // Preserve the result of the commit.
      }
    }
  }

  Future<web.CryptoKey> _unlockKey(
    BrowserCredentialRecord record,
    _Operation operation, {
    bool allowHandoff = false,
  }) async {
    if (record.protection == _browserLocal) {
      return record.unattendedKey ?? _fail('envelopeCorrupt');
    }
    return _prfKey(record, operation, allowHandoff: allowHandoff);
  }

  Uint8List _verifyClient(
    _ClientDataResponse response,
    String type,
    JSUint8Array challenge,
    _Origin expected,
  ) {
    final raw = _bytes(response.clientDataJSON);
    if (raw.length > 16384) _fail('invalidResponse');
    final Object? data;
    try {
      data = jsonDecode(utf8.decode(raw));
    } on FormatException {
      _fail('invalidResponse');
    }
    if (data is! Map ||
        data['type'] != type ||
        data['origin'] != expected.url ||
        data['crossOrigin'] == true ||
        (data.containsKey('topOrigin') && data['topOrigin'] != expected.url) ||
        !passkeyBytesEqual(
          _fromBase64Url(data['challenge']),
          challenge.toDart,
        )) {
      _fail('invalidResponse');
    }
    return raw;
  }

  Future<Uint8List> _digest(JSObject input) async =>
      _bytes(await _subtle.digest('SHA-256'.toJS, input).toDart);

  Future<Uint8List> _verifyAuthenticator(JSAny? raw, _Origin origin) async {
    final data = _bytes(raw);
    if (data.length < 37 ||
        (data[32] & 0x05) != 0x05 ||
        !passkeyBytesEqual(
          Uint8List.sublistView(data, 0, 32),
          await _digest(utf8.encode(origin.host).toJS),
        )) {
      _fail('invalidResponse');
    }
    return data;
  }

  Future<web.CryptoKey> _importPublicKey(JSObject? spki, int? algorithm) async {
    final options = switch (algorithm) {
      -7 => _object({'name': 'ECDSA', 'namedCurve': 'P-256'}),
      -257 => _object({'name': 'RSASSA-PKCS1-v1_5', 'hash': 'SHA-256'}),
      _ => _fail('invalidResponse'),
    };
    if (spki == null) _fail('invalidResponse');
    try {
      return await _subtle
          .importKey('spki', spki, options, false, ['verify'.toJS].toJS)
          .toDart;
    } on Object {
      _fail('invalidResponse');
    }
  }

  web.AuthenticationExtensionsClientInputs _prfInput(JSObject input) =>
      web.AuthenticationExtensionsClientInputs(
        prf: web.AuthenticationExtensionsPRFInputs(
          eval: web.AuthenticationExtensionsPRFValues(first: input),
        ),
      );

  _PrfOutput? _prfResult(_PublicKeyResponse credential) {
    if (!credential.has('getClientExtensionResults')) return null;
    return credential.getClientExtensionResults()?.prf;
  }

  void _discardPasskeyOutput(web.Credential? response) {
    try {
      if (response?.type != 'public-key') return;
      final output = _prfResult(response as _PublicKeyResponse)?.results?.first;
      if (output != null) _MutableBytes(_byteView(output)).fill(0);
    } on Object {
      // Discard malformed provider output without surfacing its details.
    }
  }

  Future<web.CryptoKey> _prfKey(
    BrowserCredentialRecord record,
    _Operation operation, {
    JSUint8Array? creationOutput,
    bool allowHandoff = false,
  }) async {
    _assertCurrent(operation);
    final expected = _origin();
    if (record.rpId != expected.host || record.prfInput == null) {
      _fail('invalidResponse');
    }
    final challenge = _random(32);
    final credentialId = _fromBase64Url(record.credentialId);
    final credentials = _credentials ?? _fail('unsupported');
    final options = web.CredentialRequestOptions(
      publicKey: web.PublicKeyCredentialRequestOptions(
        challenge: challenge,
        rpId: expected.host,
        timeout: _passkeyPromptTimeout.inMilliseconds,
        userVerification: 'required',
        allowCredentials: [
          web.PublicKeyCredentialDescriptor(
            type: 'public-key',
            id: credentialId.toJS,
          ),
        ].toJS,
        extensions: _prfInput(record.prfInput!),
      ),
      signal: operation.signal,
    );
    final response = await _completePasskeyPrompt(
      operation,
      () => credentials.get(options).toDart,
      allowHandoff: allowHandoff,
    );
    _assertCurrent(operation);
    if (response == null || response.type != 'public-key') {
      _fail('invalidResponse');
    }
    final credential = response as _PublicKeyResponse;
    if (!passkeyBytesEqual(_bytes(credential.rawId), credentialId)) {
      _fail('invalidResponse');
    }
    final assertion =
        (credential.response as _AssertionResponse?) ??
        _fail('invalidResponse');
    final userHandle = assertion.userHandle;
    if (userHandle != null &&
        !passkeyBytesEqual(_bytes(userHandle), _bytes(record.userHandle))) {
      _fail('invalidResponse');
    }
    final client = _verifyClient(
      assertion,
      'webauthn.get',
      challenge,
      expected,
    );
    final authenticator = await _verifyAuthenticator(
      assertion.authenticatorData,
      expected,
    );
    final publicKey = await _importPublicKey(
      record.publicKey,
      record.algorithm,
    );
    final signature = _bytes(assertion.signature);
    final signed = BytesBuilder(copy: false)
      ..add(authenticator)
      ..add(await _digest(client.toJS));
    final es256 = record.algorithm == -7;
    final valid = await _subtle
        .verify(
          es256
              ? _object({'name': 'ECDSA', 'hash': 'SHA-256'})
              : 'RSASSA-PKCS1-v1_5'.toJS,
          publicKey,
          (es256 ? _es256Signature(signature) : signature).toJS,
          signed.takeBytes().toJS,
        )
        .toDart;
    if (!_sameObject(valid, true.toJS)) _fail('invalidResponse');

    final result = _prfResult(credential)?.results?.first;
    if (result == null) _fail('prfUnavailable');
    final output = _byteView(result);
    try {
      if (output.toDart.length != 32 ||
          (creationOutput != null &&
              !passkeyBytesEqual(output.toDart, creationOutput.toDart))) {
        _fail('prfUnavailable');
      }
      return await _subtle
          .importKey('raw', output, 'AES-GCM'.toJS, false, _cipherUsages())
          .toDart;
    } finally {
      _MutableBytes(output).fill(0);
    }
  }

  Future<Map<String, Object?>> _registerPasskey(
    String key,
    String value,
    String label,
    BrowserCredentialRecord? previous,
    _Operation operation,
  ) async {
    final expected = _origin();
    _requirePasskeyEnrollment();
    final challenge = _random(32);
    final prfInput = _random(32);
    final userHandle = _random(32);
    final enrollmentId = _identifier();
    final displayName = label.length <= 64 ? label : label.substring(0, 64);
    final options = web.CredentialCreationOptions(
      publicKey: web.PublicKeyCredentialCreationOptions(
        challenge: challenge,
        rp: web.PublicKeyCredentialRpEntity(
          id: expected.host,
          name: 'Gleec Wallet',
        ),
        user: web.PublicKeyCredentialUserEntity(
          id: userHandle,
          name: '$displayName · ${enrollmentId.substring(0, 8)}',
          displayName: displayName,
        ),
        pubKeyCredParams: [
          web.PublicKeyCredentialParameters(type: 'public-key', alg: -7),
          web.PublicKeyCredentialParameters(type: 'public-key', alg: -257),
        ].toJS,
        authenticatorSelection: web.AuthenticatorSelectionCriteria(
          residentKey: 'required',
          userVerification: 'required',
        ),
        attestation: 'none',
        timeout: _passkeyPromptTimeout.inMilliseconds,
        extensions: _prfInput(prfInput),
      ),
      signal: operation.signal,
    );
    final response = await _completePasskeyPrompt(
      operation,
      () => _credentials!.create(options).toDart,
      allowHandoff: true,
    );
    _assertCurrent(operation);
    if (response == null || response.type != 'public-key') {
      _fail('invalidResponse');
    }
    final credential = response as _PublicKeyResponse;
    final rawId = _bytes(credential.rawId);
    if (rawId.isEmpty) _fail('invalidResponse');
    final attestation =
        (credential.response as _AttestationResponse?) ??
        _fail('invalidResponse');
    _verifyClient(attestation, 'webauthn.create', challenge, expected);
    if (!attestation.has('getAuthenticatorData') ||
        !attestation.has('getPublicKey') ||
        !attestation.has('getPublicKeyAlgorithm')) {
      _fail('unsupported');
    }
    final authenticator = await _verifyAuthenticator(
      attestation.getAuthenticatorData(),
      expected,
    );
    if ((authenticator[32] & 0x40) == 0 || authenticator.length < 55) {
      _fail('invalidResponse');
    }
    final length = (authenticator[53] << 8) | authenticator[54];
    if (length == 0 ||
        authenticator.length < 55 + length ||
        !passkeyBytesEqual(
          Uint8List.sublistView(authenticator, 55, 55 + length),
          rawId,
        )) {
      _fail('invalidResponse');
    }
    final prf = _prfResult(credential);
    if (!_sameObject(prf?.enabled, true.toJS)) _fail('prfUnavailable');
    final result = prf?.results?.first;
    final creationOutput = result == null ? null : _byteView(result);
    final publicKey = attestation.getPublicKey();
    final algorithm =
        _safeInteger(attestation.getPublicKeyAlgorithm()) ??
        _fail('invalidResponse');
    final web.CryptoKey encryptionKey;
    final BrowserCredentialRecord next;
    try {
      if (creationOutput != null && creationOutput.toDart.length != 32) {
        _fail('prfUnavailable');
      }
      if (publicKey == null) _fail('unsupported');
      await _importPublicKey(publicKey, algorithm);
      next = BrowserCredentialRecord(
        schema: _schema,
        key: key,
        revision: (previous?.revision ?? 0) + 1,
        protection: _passkeyPrf,
        origin: expected.url,
        rpId: expected.host,
        credentialId: _base64Url(rawId),
        enrollmentId: enrollmentId,
        userHandle: userHandle,
        prfInput: prfInput,
        publicKey: publicKey,
        algorithm: algorithm,
      );
      // The first assertion proves the saved passkey can open the envelope.
      encryptionKey = await _prfKey(
        next,
        operation,
        creationOutput: creationOutput,
        allowHandoff: true,
      );
    } finally {
      if (creationOutput != null) _MutableBytes(creationOutput).fill(0);
    }
    await _sealAndCommit(previous, next, value, encryptionKey, operation);
    return _metadata(next);
  }
}
