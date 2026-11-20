#ifndef RUNNER_PASSKEY_CHANNEL_H_
#define RUNNER_PASSKEY_CHANNEL_H_

#include <flutter/binary_messenger.h>
#include <windows.h>

#include <memory>

// One user-verified WebAuthn assertion with the PRF extension, through the
// Windows WebAuthn API. It stores nothing and never sees the wallet credential.
class PasskeyChannel {
public:
  PasskeyChannel(HWND window, flutter::BinaryMessenger *messenger);
  ~PasskeyChannel();

  PasskeyChannel(const PasskeyChannel &) = delete;
  PasskeyChannel &operator=(const PasskeyChannel &) = delete;

  // Must run before Flutter's window-message dispatch. Returns true only for
  // this channel's own completion message; a session lock also cancels the
  // ceremony but is left for the credential vault to handle.
  bool HandleMessage(UINT message, WPARAM wparam);

private:
  struct Impl;
  std::unique_ptr<Impl> impl_;
};

#endif // RUNNER_PASSKEY_CHANNEL_H_
