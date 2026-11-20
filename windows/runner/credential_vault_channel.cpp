#include "credential_vault_channel.h"

#include <bcrypt.h>
#include <flutter/encodable_value.h>
#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>
#include <roapi.h>
#include <shlobj.h>
#include <wincrypt.h>
#include <winrt/Windows.Foundation.h>
#include <winrt/Windows.Security.Credentials.UI.h>
#include <wtsapi32.h>

// Window-bound Hello is a Windows 11 desktop API. Older SDKs and operating
// systems retain DPAPI storage, but must report device authentication absent.
#if __has_include(<userconsentverifierinterop.h>)
#include <userconsentverifierinterop.h>
#define GLEEC_HAS_HELLO_INTEROP 1
#endif

#include <algorithm>
#include <array>
#include <cstdint>
#include <deque>
#include <filesystem>
#include <mutex>
#include <string>
#include <unordered_map>
#include <utility>
#include <vector>

namespace {
using Value = flutter::EncodableValue;
using Map = flutter::EncodableMap;
using Result = flutter::MethodResult<Value>;
using Bytes = std::vector<unsigned char>;
// The interop headers also expose ABI::Windows::Foundation::AsyncStatus in
// the global namespace. Use a distinct name for the projected C++/WinRT enum.
using WinrtAsyncStatus = winrt::Windows::Foundation::AsyncStatus;
using winrt::Windows::Security::Credentials::UI::UserConsentVerificationResult;
using winrt::Windows::Security::Credentials::UI::UserConsentVerifier;
using winrt::Windows::Security::Credentials::UI::
    UserConsentVerifierAvailability;

constexpr UINT kCompletionMessage = WM_APP + 0x475;
constexpr size_t kMaximumRecordSize = 1024 * 1024;
constexpr std::array<unsigned char, 8> kMagic = {'G', 'L', 'E', 'E',
                                                 'C', 'V', '0', '1'};
constexpr size_t kEnvelopePrefixSize = kMagic.size() + 1 + 8;

// Errors crossing the channel are closed labels, never native exception text.
struct VaultFailure {
  const char *code;
};

template <class Container> void Wipe(Container &bytes) {
  if (!bytes.empty())
    SecureZeroMemory(bytes.data(), bytes.size() * sizeof(bytes[0]));
  bytes.clear();
}

struct SensitiveBytes {
  Bytes bytes;
  ~SensitiveBytes() { Wipe(bytes); }
};

struct LocalData {
  DATA_BLOB blob{};
  ~LocalData() {
    if (blob.pbData) {
      SecureZeroMemory(blob.pbData, blob.cbData);
      LocalFree(blob.pbData);
    }
  }
};

struct FileHandle {
  HANDLE value = INVALID_HANDLE_VALUE;
  ~FileHandle() {
    if (value != INVALID_HANDLE_VALUE)
      CloseHandle(value);
  }
};

std::wstring KeyHash(const std::string &key) {
  BCRYPT_ALG_HANDLE algorithm = nullptr;
  BCRYPT_HASH_HANDLE hash = nullptr;
  std::array<unsigned char, 32> digest{};
  const auto opened = BCryptOpenAlgorithmProvider(
      &algorithm, BCRYPT_SHA256_ALGORITHM, nullptr, 0);
  if (opened < 0)
    throw VaultFailure{"storageFailed"};
  const auto created =
      BCryptCreateHash(algorithm, &hash, nullptr, 0, nullptr, 0, 0);
  const auto added =
      created < 0
          ? created
          : BCryptHashData(
                hash, reinterpret_cast<PUCHAR>(const_cast<char *>(key.data())),
                static_cast<ULONG>(key.size()), 0);
  const auto finished =
      added < 0 ? added
                : BCryptFinishHash(hash, digest.data(),
                                   static_cast<ULONG>(digest.size()), 0);
  if (hash)
    BCryptDestroyHash(hash);
  BCryptCloseAlgorithmProvider(algorithm, 0);
  if (finished < 0)
    throw VaultFailure{"storageFailed"};
  constexpr wchar_t hex[] = L"0123456789abcdef";
  std::wstring result;
  result.reserve(digest.size() * 2);
  for (const auto byte : digest) {
    result.push_back(hex[byte >> 4]);
    result.push_back(hex[byte & 15]);
  }
  return result;
}

// Serialize the compare-and-commit interval across native processes too. The
// UI must never wait for another process (which may itself be showing Hello).
class ScopedVaultMutex {
public:
  explicit ScopedVaultMutex(const std::string &key) {
    const auto name = L"Local\\GleecCredentialVault-" + KeyHash(key);
    handle_ = CreateMutexW(nullptr, FALSE, name.c_str());
    if (!handle_) {
      throw VaultFailure{
          GetLastError() == ERROR_ACCESS_DENIED ? "busy" : "storageFailed"};
    }
    const DWORD wait = WaitForSingleObject(handle_, 0);
    if (wait != WAIT_OBJECT_0 && wait != WAIT_ABANDONED) {
      CloseHandle(handle_);
      handle_ = nullptr;
      throw VaultFailure{wait == WAIT_TIMEOUT ? "busy" : "storageFailed"};
    }
  }

  ~ScopedVaultMutex() {
    if (handle_) {
      ReleaseMutex(handle_);
      CloseHandle(handle_);
    }
  }

  ScopedVaultMutex(const ScopedVaultMutex &) = delete;
  ScopedVaultMutex &operator=(const ScopedVaultMutex &) = delete;

private:
  HANDLE handle_ = nullptr;
};

std::filesystem::path VaultDirectory() {
  PWSTR local = nullptr;
  if (FAILED(SHGetKnownFolderPath(FOLDERID_LocalAppData, KF_FLAG_CREATE,
                                  nullptr, &local))) {
    throw VaultFailure{"storageFailed"};
  }
  const auto directory =
      std::filesystem::path(local) / L"Gleec" / L"CredentialVault-v1";
  CoTaskMemFree(local);
  std::error_code error;
  std::filesystem::create_directories(directory, error);
  if (error)
    throw VaultFailure{"storageFailed"};
  return directory;
}

Bytes ReadFileBytes(const std::filesystem::path &path) {
  FileHandle file{CreateFileW(path.c_str(), GENERIC_READ, FILE_SHARE_READ,
                              nullptr, OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL,
                              nullptr)};
  if (file.value == INVALID_HANDLE_VALUE) {
    if (GetLastError() == ERROR_FILE_NOT_FOUND)
      return {};
    throw VaultFailure{"storageFailed"};
  }
  LARGE_INTEGER length{};
  if (!GetFileSizeEx(file.value, &length) || length.QuadPart <= 0 ||
      length.QuadPart > static_cast<LONGLONG>(kMaximumRecordSize)) {
    throw VaultFailure{"invalidated"};
  }
  Bytes bytes(static_cast<size_t>(length.QuadPart));
  DWORD count = 0;
  if (!ReadFile(file.value, bytes.data(), static_cast<DWORD>(bytes.size()),
                &count, nullptr) ||
      count != bytes.size())
    throw VaultFailure{"storageFailed"};
  return bytes;
}

bool RequiresAuthentication(const Bytes &envelope) {
  if (envelope.size() <= kEnvelopePrefixSize ||
      !std::equal(kMagic.begin(), kMagic.end(), envelope.begin()) ||
      envelope[kMagic.size()] > 1)
    throw VaultFailure{"invalidated"};
  return envelope[kMagic.size()] == 1;
}

int64_t Revision(const Bytes &envelope) {
  RequiresAuthentication(envelope);
  uint64_t revision = 0;
  for (size_t i = 0; i < 8; ++i) {
    revision |= static_cast<uint64_t>(envelope[kMagic.size() + 1 + i])
                << (i * 8);
  }
  if (revision == 0 || revision >= static_cast<uint64_t>(INT64_MAX)) {
    throw VaultFailure{"invalidated"};
  }
  return static_cast<int64_t>(revision);
}

std::string Decrypt(const Bytes &envelope, const std::string &key) {
  Revision(envelope);
  DATA_BLOB encrypted{
      static_cast<DWORD>(envelope.size() - kEnvelopePrefixSize),
      const_cast<BYTE *>(envelope.data() + kEnvelopePrefixSize)};
  LocalData plaintext;
  if (!CryptUnprotectData(&encrypted, nullptr, nullptr, nullptr, nullptr,
                          CRYPTPROTECT_UI_FORBIDDEN, &plaintext.blob)) {
    throw VaultFailure{"invalidated"};
  }
  const auto *begin = plaintext.blob.pbData;
  const size_t minimum = kEnvelopePrefixSize + 4 + key.size();
  if (plaintext.blob.cbData < minimum ||
      !std::equal(envelope.begin(), envelope.begin() + kEnvelopePrefixSize,
                  begin)) {
    throw VaultFailure{"invalidated"};
  }
  uint32_t key_length = 0;
  for (size_t i = 0; i < 4; ++i) {
    key_length |= static_cast<uint32_t>(begin[kEnvelopePrefixSize + i])
                  << (i * 8);
  }
  if (key_length != key.size() ||
      !std::equal(
          key.begin(), key.end(),
          reinterpret_cast<const char *>(begin + kEnvelopePrefixSize + 4))) {
    throw VaultFailure{"invalidated"};
  }
  return std::string(reinterpret_cast<const char *>(begin + minimum),
                     plaintext.blob.cbData - minimum);
}

Bytes Encrypt(const std::string &key, const std::string &value,
              bool protected_record, int64_t revision) {
  SensitiveBytes plaintext;
  plaintext.bytes.insert(plaintext.bytes.end(), kMagic.begin(), kMagic.end());
  plaintext.bytes.push_back(static_cast<unsigned char>(protected_record));
  for (size_t i = 0; i < 8; ++i) {
    plaintext.bytes.push_back(static_cast<unsigned char>(
        (static_cast<uint64_t>(revision) >> (i * 8)) & 0xff));
  }
  for (size_t i = 0; i < 4; ++i) {
    plaintext.bytes.push_back(
        static_cast<unsigned char>((key.size() >> (i * 8)) & 0xff));
  }
  plaintext.bytes.insert(plaintext.bytes.end(), key.begin(), key.end());
  plaintext.bytes.insert(plaintext.bytes.end(), value.begin(), value.end());
  DATA_BLOB input{static_cast<DWORD>(plaintext.bytes.size()),
                  plaintext.bytes.data()};
  LocalData encrypted;
  // No CRYPTPROTECT_LOCAL_MACHINE: another Windows account must not decrypt it.
  if (!CryptProtectData(&input, L"Gleec wallet credential", nullptr, nullptr,
                        nullptr, CRYPTPROTECT_UI_FORBIDDEN, &encrypted.blob)) {
    throw VaultFailure{"storageFailed"};
  }
  Bytes result(kMagic.begin(), kMagic.end());
  result.push_back(static_cast<unsigned char>(protected_record));
  result.insert(result.end(), plaintext.bytes.begin() + kMagic.size() + 1,
                plaintext.bytes.begin() + kEnvelopePrefixSize);
  result.insert(result.end(), encrypted.blob.pbData,
                encrypted.blob.pbData + encrypted.blob.cbData);
  return result;
}

void WriteAtomic(const std::filesystem::path &path, const Bytes &bytes) {
  GUID id{};
  if (FAILED(CoCreateGuid(&id)))
    throw VaultFailure{"storageFailed"};
  wchar_t suffix[40]{};
  if (!StringFromGUID2(id, suffix, 40))
    throw VaultFailure{"storageFailed"};
  const auto temporary =
      path.parent_path() / (std::wstring(suffix) + L".pending");
  try {
    {
      FileHandle file{CreateFileW(temporary.c_str(), GENERIC_WRITE, 0, nullptr,
                                  CREATE_NEW, FILE_ATTRIBUTE_NORMAL, nullptr)};
      DWORD count = 0;
      if (file.value == INVALID_HANDLE_VALUE ||
          !WriteFile(file.value, bytes.data(), static_cast<DWORD>(bytes.size()),
                     &count, nullptr) ||
          count != bytes.size() || !FlushFileBuffers(file.value)) {
        throw VaultFailure{"storageFailed"};
      }
    }
    if (!MoveFileExW(temporary.c_str(), path.c_str(),
                     MOVEFILE_REPLACE_EXISTING | MOVEFILE_WRITE_THROUGH)) {
      throw VaultFailure{"storageFailed"};
    }
  } catch (...) {
    DeleteFileW(temporary.c_str());
    throw;
  }
}

const Value *Argument(const Map &arguments, const char *name) {
  const auto found = arguments.find(Value(name));
  return found == arguments.end() ? nullptr : &found->second;
}

std::string StringArgument(const Map &arguments, const char *name, size_t limit,
                           bool required = true) {
  const auto *value = Argument(arguments, name);
  const auto *text = value ? std::get_if<std::string>(value) : nullptr;
  if (!text || text->empty() || text->size() > limit) {
    if (!required && !value)
      return {};
    throw VaultFailure{"storageFailed"};
  }
  return *text;
}

bool BoolArgument(const Map &arguments, const char *name) {
  const auto *value = Argument(arguments, name);
  if (!value)
    return false;
  const auto *boolean = std::get_if<bool>(value);
  if (!boolean)
    throw VaultFailure{"storageFailed"};
  return *boolean;
}

bool HasHelloInterop() {
#ifdef GLEEC_HAS_HELLO_INTEROP
  try {
    return static_cast<bool>(
        winrt::get_activation_factory<UserConsentVerifier,
                                      IUserConsentVerifierInterop>());
  } catch (...) {
  }
#endif
  return false;
}

const char *VerificationError(UserConsentVerificationResult result) {
  switch (result) {
  case UserConsentVerificationResult::Verified:
    return nullptr;
  case UserConsentVerificationResult::Canceled:
    return "canceled";
  case UserConsentVerificationResult::DeviceBusy:
    return "busy";
  case UserConsentVerificationResult::RetriesExhausted:
    return "lockedOut";
  default:
    return "unavailable";
  }
}

void Fail(Result &result, const char *code) {
  result.Error(code, "Wallet credential operation did not complete.");
}
} // namespace

struct CredentialVaultChannel::Impl {
  enum class Action { capabilities, read, write, remove, prepareRemove };
  struct Pending {
    uint64_t id = 0;
    Action action = Action::read;
    std::string key;
    std::string value;
    std::filesystem::path path;
    Bytes snapshot;
    bool protected_record = false;
    bool authorized_cleanup = false;
    bool authorize_deletion_read = false;
    ULONGLONG deletion_authorization_expires = 0;
    std::unique_ptr<Result> result;
    ~Pending() { Wipe(value); }
  };
  struct DeletionAuthorization {
    std::string key;
    Bytes snapshot;
    ULONGLONG expires;
  };
  struct Completion {
    uint64_t id;
    bool available = false;
    const char *error = nullptr;
  };
  struct Delivery {
    std::mutex mutex;
    bool alive = true;
    HWND window;
    std::deque<Completion> completions;
  };

  HWND window;
  bool ro_initialized = false;
  bool notifications_registered = false;
  uint64_t next_id = 0;
  std::shared_ptr<Delivery> delivery = std::make_shared<Delivery>();
  std::unique_ptr<Pending> pending;
  std::unordered_map<std::string, DeletionAuthorization>
      deletion_authorizations;
  std::unordered_map<std::string, DeletionAuthorization>
      deletion_read_authorizations;
  winrt::Windows::Foundation::IAsyncInfo async_operation{nullptr};
  std::unique_ptr<flutter::MethodChannel<Value>> channel;

  Impl(HWND owner, flutter::BinaryMessenger *messenger) : window(owner) {
    delivery->window = owner;
    ro_initialized = SUCCEEDED(RoInitialize(RO_INIT_SINGLETHREADED));
    channel = std::make_unique<flutter::MethodChannel<Value>>(
        messenger, "gleec.wallet/credential_vault",
        &flutter::StandardMethodCodec::GetInstance());
    channel->SetMethodCallHandler([this](const auto &call, auto result) {
      HandleCall(call, std::move(result));
    });
    notifications_registered =
        WTSRegisterSessionNotification(owner, NOTIFY_FOR_THIS_SESSION) != FALSE;
  }

  ~Impl() {
    channel->SetMethodCallHandler(nullptr);
    Cancel();
    {
      std::lock_guard<std::mutex> lock(delivery->mutex);
      delivery->alive = false;
      delivery->completions.clear();
    }
    if (notifications_registered)
      WTSUnRegisterSessionNotification(window);
    channel.reset();
    if (ro_initialized)
      RoUninitialize();
  }

  static void Deliver(const std::weak_ptr<Delivery> &weak,
                      Completion completion) {
    if (auto target = weak.lock()) {
      std::lock_guard<std::mutex> lock(target->mutex);
      if (!target->alive)
        return;
      target->completions.push_back(completion);
      PostMessageW(target->window, kCompletionMessage, 0, 0);
    }
  }

  void Cancel() {
    deletion_authorizations.clear();
    deletion_read_authorizations.clear();
    if (async_operation) {
      try {
        async_operation.Cancel();
      } catch (...) {
      }
      async_operation = nullptr;
    }
    if (pending) {
      Fail(*pending->result, "canceled");
      pending.reset();
    }
  }

  void HandleCall(const flutter::MethodCall<Value> &call,
                  std::unique_ptr<Result> result) {
    if (call.method_name() == "cancel") {
      Cancel();
      result->Success();
      return;
    }
    if (call.method_name() == "repairInvalidated") {
      Fail(*result, "unavailable");
      return;
    }
    if (call.method_name() == "savePassword") {
      // Credential Locker is not the user's chosen password manager. Do not
      // silently store another copy there or claim a browser-manager save.
      result->Success(Value("unavailable"));
      return;
    }
    if (pending) {
      Fail(*result, "busy");
      return;
    }
    auto request = std::make_unique<Pending>();
    request->id = ++next_id;
    request->result = std::move(result);
    try {
      if (call.method_name() == "capabilities") {
        VaultDirectory();
        request->action = Action::capabilities;
        pending = std::move(request);
        CheckAvailability();
        return;
      }
      const auto *args =
          call.arguments() ? std::get_if<Map>(call.arguments()) : nullptr;
      if (!args)
        throw VaultFailure{"storageFailed"};
      request->key = StringArgument(*args, "key", 512);
      request->path = VaultDirectory() / (KeyHash(request->key) + L".vault");
      request->snapshot = ReadFileBytes(request->path);
      if (call.method_name() == "metadata") {
        if (request->snapshot.empty()) {
          request->result->Success();
          return;
        }
        // Authenticate the public protection/revision fields against DPAPI's
        // inner record. Never send credential bytes across the channel here.
        auto verification = Decrypt(request->snapshot, request->key);
        Wipe(verification);
        request->result->Success(Value(Map{
            {Value("protection"), Value("osAccountProtected")},
            {Value("enrolled"),
             Value(RequiresAuthentication(request->snapshot))},
            {Value("revision"), Value(Revision(request->snapshot))},
        }));
        return;
      }
      const bool existing_protected = !request->snapshot.empty() &&
                                      RequiresAuthentication(request->snapshot);
      const bool requested_protection =
          BoolArgument(*args, "requireAuthentication");
      request->protected_record = existing_protected || requested_protection;
      if (call.method_name() == "read") {
        request->action = Action::read;
        request->authorize_deletion_read =
            StringArgument(*args, "purpose", 32, false) == "delete";
        if (request->snapshot.empty()) {
          request->result->Success();
          return;
        }
      } else if (call.method_name() == "write") {
        request->action = Action::write;
        request->value = StringArgument(*args, "value", kMaximumRecordSize / 2);
      } else if (call.method_name() == "delete") {
        request->action = Action::remove;
        const auto authorization =
            StringArgument(*args, "authorization", 128, false);
        if (!authorization.empty()) {
          const auto found = deletion_authorizations.find(authorization);
          if (found == deletion_authorizations.end())
            throw VaultFailure{"invalidated"};
          auto grant = std::move(found->second);
          deletion_authorizations.erase(found);
          if (grant.key != request->key ||
              grant.snapshot != request->snapshot ||
              grant.expires < GetTickCount64())
            throw VaultFailure{"invalidated"};
          request->authorized_cleanup = true;
        } else if (request->snapshot.empty()) {
          request->result->Success();
          return;
        }
      } else if (call.method_name() == "prepareDelete") {
        request->action = Action::prepareRemove;
        const auto found = deletion_read_authorizations.find(request->key);
        if (found != deletion_read_authorizations.end()) {
          auto grant = std::move(found->second);
          deletion_read_authorizations.erase(found);
          request->authorized_cleanup = grant.snapshot == request->snapshot &&
                                        grant.expires >= GetTickCount64();
          if (request->authorized_cleanup)
            request->deletion_authorization_expires = grant.expires;
        }
      } else {
        request->result->NotImplemented();
        return;
      }
      std::string reason = StringArgument(*args, "reason", 256, false);
      if (reason.empty())
        reason = "Unlock your Gleec wallet";
      pending = std::move(request);
      if (pending->protected_record && !pending->authorized_cleanup)
        BeginHello(reason);
      else
        CompleteOperation();
    } catch (const VaultFailure &failure) {
      if (request)
        Fail(*request->result, failure.code);
      else
        FailPending(failure.code);
    } catch (...) {
      if (request)
        Fail(*request->result, "storageFailed");
      else
        FailPending("storageFailed");
    }
  }

  void FailPending(const char *code) {
    if (!pending)
      return;
    Fail(*pending->result, code);
    pending.reset();
    async_operation = nullptr;
  }

  void CheckAvailability() {
    if (!ro_initialized || !HasHelloInterop()) {
      ReturnCapabilities(false);
      return;
    }
    try {
      auto operation = UserConsentVerifier::CheckAvailabilityAsync();
      async_operation = operation;
      const auto id = pending->id;
      std::weak_ptr<Delivery> weak = delivery;
      operation.Completed(
          [weak, id](const auto &completed, WinrtAsyncStatus status) {
            bool available = false;
            if (status == WinrtAsyncStatus::Completed) {
              try {
                available = completed.GetResults() ==
                            UserConsentVerifierAvailability::Available;
              } catch (...) {
              }
            }
            Deliver(weak, Completion{id, available, nullptr});
          });
    } catch (...) {
      ReturnCapabilities(false);
    }
  }

  void ReturnCapabilities(bool available) {
    pending->result->Success(Value(Map{
        {Value("available"), Value(true)},
        {Value("protection"), Value("osAccountProtected")},
        {Value("deviceAuthentication"), Value(available)},
    }));
    pending.reset();
    async_operation = nullptr;
  }

  void BeginHello(const std::string &reason) {
#ifdef GLEEC_HAS_HELLO_INTEROP
    if (!ro_initialized) {
      FailPending("unavailable");
      return;
    }
    try {
      const auto interop =
          winrt::get_activation_factory<UserConsentVerifier,
                                        IUserConsentVerifierInterop>();
      winrt::Windows::Foundation::IAsyncOperation<UserConsentVerificationResult>
          operation{nullptr};
      const auto message = winrt::to_hstring(reason);
      winrt::check_hresult(interop->RequestVerificationForWindowAsync(
          window, reinterpret_cast<HSTRING>(winrt::get_abi(message)),
          winrt::guid_of<decltype(operation)>(), winrt::put_abi(operation)));
      async_operation = operation;
      const auto id = pending->id;
      std::weak_ptr<Delivery> weak = delivery;
      operation.Completed(
          [weak, id](const auto &completed, WinrtAsyncStatus status) {
            const char *error = "unavailable";
            if (status == WinrtAsyncStatus::Canceled)
              error = "canceled";
            if (status == WinrtAsyncStatus::Completed) {
              try {
                error = VerificationError(completed.GetResults());
              } catch (...) {
              }
            }
            Deliver(weak, Completion{id, false, error});
          });
    } catch (...) {
      FailPending("unavailable");
    }
#else
    FailPending("unavailable");
#endif
  }

  void CompleteOperation() {
    auto request = std::move(pending);
    async_operation = nullptr;
    try {
      const ScopedVaultMutex lock(request->key);
      // A different process or pending operation must not replace the record
      // underneath the verification ceremony.
      if (ReadFileBytes(request->path) != request->snapshot)
        throw VaultFailure{"busy"};
      if (!request->snapshot.empty() && !request->authorized_cleanup) {
        auto previous = Decrypt(request->snapshot, request->key);
        if (request->action == Action::read) {
          if (request->authorize_deletion_read)
            deletion_read_authorizations.insert_or_assign(
                request->key,
                DeletionAuthorization{request->key, request->snapshot,
                                      GetTickCount64() + 60000});
          request->result->Success(Value(previous));
          Wipe(previous);
          return;
        }
        Wipe(previous);
      }
      if (request->action == Action::prepareRemove) {
        std::array<unsigned char, 32> random{};
        if (BCryptGenRandom(nullptr, random.data(),
                            static_cast<ULONG>(random.size()),
                            BCRYPT_USE_SYSTEM_PREFERRED_RNG) < 0)
          throw VaultFailure{"storageFailed"};
        constexpr char hex[] = "0123456789abcdef";
        std::string token;
        token.reserve(random.size() * 2);
        for (const auto byte : random) {
          token.push_back(hex[byte >> 4]);
          token.push_back(hex[byte & 15]);
        }
        const auto now = GetTickCount64();
        for (auto entry = deletion_authorizations.begin();
             entry != deletion_authorizations.end();) {
          if (entry->second.expires < now)
            entry = deletion_authorizations.erase(entry);
          else
            ++entry;
        }
        deletion_authorizations.emplace(
            token,
            DeletionAuthorization{request->key, request->snapshot,
                                  request->deletion_authorization_expires != 0
                                      ? request->deletion_authorization_expires
                                      : now + 60000});
        request->result->Success(Value(token));
        return;
      } else if (request->action == Action::write) {
        const int64_t revision =
            request->snapshot.empty() ? 1 : Revision(request->snapshot) + 1;
        if (revision == INT64_MAX)
          throw VaultFailure{"storageFailed"};
        const auto envelope = Encrypt(request->key, request->value,
                                      request->protected_record, revision);
        WriteAtomic(request->path, envelope);
        auto readback = Decrypt(ReadFileBytes(request->path), request->key);
        const bool matches = readback == request->value;
        Wipe(readback);
        if (!matches)
          throw VaultFailure{"storageFailed"};
      } else if (request->action == Action::remove) {
        if (!request->snapshot.empty() && !DeleteFileW(request->path.c_str()))
          throw VaultFailure{"storageFailed"};
      }
      request->result->Success();
    } catch (const VaultFailure &failure) {
      Fail(*request->result, failure.code);
    } catch (...) {
      Fail(*request->result, "storageFailed");
    }
  }

  bool HandleMessage(UINT message, WPARAM wparam) {
    if (message == WM_WTSSESSION_CHANGE && wparam == WTS_SESSION_LOCK) {
      Cancel();
      channel->InvokeMethod("deviceLocked", nullptr);
      return true;
    }
    if (message != kCompletionMessage)
      return false;
    std::deque<Completion> ready;
    {
      std::lock_guard<std::mutex> lock(delivery->mutex);
      ready.swap(delivery->completions);
    }
    for (const auto &completion : ready) {
      if (!pending || pending->id != completion.id)
        continue;
      if (pending->action == Action::capabilities)
        ReturnCapabilities(completion.available);
      else if (completion.error)
        FailPending(completion.error);
      else
        CompleteOperation();
    }
    return true;
  }
};

CredentialVaultChannel::CredentialVaultChannel(
    HWND window, flutter::BinaryMessenger *messenger)
    : impl_(std::make_unique<Impl>(window, messenger)) {}
CredentialVaultChannel::~CredentialVaultChannel() = default;
bool CredentialVaultChannel::HandleMessage(UINT message, WPARAM wparam) {
  return impl_->HandleMessage(message, wparam);
}
