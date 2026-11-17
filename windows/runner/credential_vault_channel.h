#ifndef RUNNER_CREDENTIAL_VAULT_CHANNEL_H_
#define RUNNER_CREDENTIAL_VAULT_CHANNEL_H_

#include <flutter/binary_messenger.h>
#include <windows.h>

#include <memory>

// User-scoped DPAPI storage with an optional Windows Hello application gate.
// Hello is deliberately NOT described as cryptographically bound to DPAPI.
class CredentialVaultChannel {
public:
  CredentialVaultChannel(HWND window, flutter::BinaryMessenger *messenger);
  ~CredentialVaultChannel();

  CredentialVaultChannel(const CredentialVaultChannel &) = delete;
  CredentialVaultChannel &operator=(const CredentialVaultChannel &) = delete;

  // Must run before Flutter's window-message dispatch. Async results are
  // delivered here, on the same thread that owns the Flutter messenger.
  bool HandleMessage(UINT message, WPARAM wparam);

private:
  struct Impl;
  std::unique_ptr<Impl> impl_;
};

#endif // RUNNER_CREDENTIAL_VAULT_CHANNEL_H_
