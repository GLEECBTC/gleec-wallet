import 'credential_backend.dart';
import 'native_credential_backend.dart'
    if (dart.library.js_interop) 'web_credential_backend.dart'
    as platform;

CredentialBackend createCredentialBackend() =>
    platform.createCredentialBackend();
