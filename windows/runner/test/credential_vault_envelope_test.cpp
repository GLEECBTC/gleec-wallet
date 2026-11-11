// Standalone Windows test: uses the production implementation and real DPAPI.
// No wallet, recovery phrase, funded account, or Hello dialog is involved.
#include "../credential_vault_channel.cpp"

#include <iostream>
#include <stdexcept>

namespace {
void Check(bool condition, const char *label) {
  if (!condition)
    throw std::runtime_error(label);
}

template <class Action> void Rejects(Action action, const char *label) {
  try {
    action();
  } catch (const VaultFailure &failure) {
    Check(std::string(failure.code) == "invalidated", label);
    return;
  }
  throw std::runtime_error(label);
}

class TestMessenger : public flutter::BinaryMessenger {
public:
  mutable int device_lock_events = 0;
  flutter::BinaryMessageHandler handler;

  void Send(const std::string &channel, const uint8_t *message, size_t size,
            flutter::BinaryReply reply = nullptr) const override {
    Check(channel == "gleec.wallet/credential_vault", "channel identity");
    const auto call =
        flutter::StandardMethodCodec::GetInstance().DecodeMethodCall(message,
                                                                     size);
    Check(call && call->method_name() == "deviceLocked", "lock event");
    ++device_lock_events;
    if (reply)
      reply(nullptr, 0);
  }

  void SetMessageHandler(const std::string &channel,
                         flutter::BinaryMessageHandler value) override {
    Check(channel == "gleec.wallet/credential_vault", "handler identity");
    handler = std::move(value);
  }
};
} // namespace

int wmain(int argc, wchar_t *argv[]) {
  try {
    constexpr char key[] = "gleec.synthetic.windows-vault-test";
    constexpr char canary[] = "UNFUNDED_SYNTHETIC_WINDOWS_CREDENTIAL_CANARY";
    if (argc == 3 && std::wstring(argv[1]) == L"--write-account-probe") {
      WriteAtomic(std::filesystem::path(argv[2]),
                  Encrypt(key, canary, true, 7));
      std::cout << "Synthetic DPAPI account probe written.\n";
      return 0;
    }
    if (argc == 3 && std::wstring(argv[1]) == L"--verify-foreign-account") {
      const auto foreign = ReadFileBytes(std::filesystem::path(argv[2]));
      Check(RequiresAuthentication(foreign) && Revision(foreign) == 7,
            "valid account probe header");
      Rejects([&]() { Decrypt(foreign, key); }, "foreign account isolation");
      std::cout << "Foreign account could not decrypt the synthetic probe.\n";
      return 0;
    }
    Check(argc == 1, "supported validation arguments");
    const auto envelope = Encrypt(key, canary, true, 7);
    Check(RequiresAuthentication(envelope), "protected policy retained");
    Check(Revision(envelope) == 7, "record revision retained");
    auto plaintext = Decrypt(envelope, key);
    Check(plaintext == canary, "DPAPI round trip");
    Wipe(plaintext);
    Check(std::search(envelope.begin(), envelope.end(), std::begin(canary),
                      std::end(canary) - 1) == envelope.end(),
          "no credential plaintext in envelope");

    Rejects([&]() { Decrypt(envelope, "different-wallet"); }, "wallet binding");
    auto changed = envelope;
    changed[kMagic.size()] = 0;
    Rejects([&]() { Decrypt(changed, key); }, "policy downgrade rejected");
    changed = envelope;
    changed[kMagic.size() + 1] ^= 1;
    Rejects([&]() { Decrypt(changed, key); }, "revision tampering rejected");
    changed = envelope;
    changed.back() ^= 1;
    Rejects([&]() { Decrypt(changed, key); }, "ciphertext tampering rejected");
    changed.resize(kEnvelopePrefixSize);
    Rejects([&]() { Decrypt(changed, key); }, "truncation rejected");

    wchar_t temporary[MAX_PATH + 1]{};
    Check(GetTempPathW(MAX_PATH, temporary) != 0, "temporary directory");
    GUID id{};
    Check(SUCCEEDED(CoCreateGuid(&id)), "temporary file identity");
    wchar_t suffix[40]{};
    Check(StringFromGUID2(id, suffix, 40) != 0, "temporary file suffix");
    const auto path = std::filesystem::path(temporary) /
                      (std::wstring(suffix) + L".gleec-vault-test");
    try {
      WriteAtomic(path, envelope);
      Check(ReadFileBytes(path) == envelope, "atomic write readback");
      const auto replacement = Encrypt(key, canary, true, 8);
      WriteAtomic(path, replacement);
      Check(ReadFileBytes(path) == replacement, "atomic replacement readback");
      Check(DeleteFileW(path.c_str()) != FALSE, "temporary file deletion");
    } catch (...) {
      DeleteFileW(path.c_str());
      throw;
    }

    TestMessenger messenger;
    const HWND window =
        CreateWindowExW(0, L"STATIC", L"Gleec vault test", 0, 0, 0, 0, 0,
                        HWND_MESSAGE, nullptr, nullptr, nullptr);
    Check(window != nullptr, "test message window");
    {
      CredentialVaultChannel channel(window, &messenger);
      Check(static_cast<bool>(messenger.handler), "handler registered");
      Check(channel.HandleMessage(WM_WTSSESSION_CHANGE, WTS_SESSION_LOCK),
            "session lock handled");
      Check(messenger.device_lock_events == 1, "one device lock event");
    }
    Check(!messenger.handler, "handler removed before messenger destruction");
    DestroyWindow(window);
    std::cout << "Windows credential envelope and channel checks passed.\n";
    return 0;
  } catch (const std::exception &) {
    std::cerr << "Windows credential validation failed.\n";
  } catch (...) {
    std::cerr << "Windows credential validation failed.\n";
  }
  return 1;
}
