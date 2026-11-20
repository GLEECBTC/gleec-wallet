#include "passkey_channel.h"

#include <flutter/encodable_value.h>
#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>
#include <objbase.h>
#include <webauthn.h>
#include <wtsapi32.h>

#include <atomic>
#include <cstdint>
#include <cwchar>
#include <deque>
#include <mutex>
#include <string>
#include <thread>
#include <type_traits>
#include <utility>
#include <vector>

namespace {

using Value = flutter::EncodableValue;
using Result = flutter::MethodResult<Value>;
using Bytes = std::vector<uint8_t>;

constexpr UINT kCompletionMessage = WM_APP + 0x476;
constexpr char kMessage[] = "Passkey request could not be completed";

void Wipe(Bytes &bytes) {
  if (!bytes.empty())
    SecureZeroMemory(bytes.data(), bytes.size());
  bytes.clear();
}

// Loaded from System32 on first use. An import-table dependency would stop
// the app starting where webauthn.dll is missing, and a search-path load
// could pick up a planted copy.
struct WebAuthnApi {
  decltype(&WebAuthNGetApiVersionNumber) version = nullptr;
  decltype(&WebAuthNAuthenticatorGetAssertion) get_assertion = nullptr;
  decltype(&WebAuthNFreeAssertion) free_assertion = nullptr;
  decltype(&WebAuthNGetCancellationId) cancellation_id = nullptr;
  decltype(&WebAuthNCancelCurrentOperation) cancel = nullptr;
  decltype(&WebAuthNGetErrorName) error_name = nullptr;

  static const WebAuthnApi *Get() {
    static const WebAuthnApi api = Load();
    return api.get_assertion ? &api : nullptr;
  }

private:
  template <class Function>
  static bool Bind(HMODULE module, const char *name, Function &slot) {
    // FARPROC is the loader's generic function pointer type.
    slot = reinterpret_cast<Function>(
        reinterpret_cast<void *>(GetProcAddress(module, name)));
    return slot != nullptr;
  }

  static WebAuthnApi Load() {
    WebAuthnApi api;
    HMODULE module = LoadLibraryExW(L"webauthn.dll", nullptr,
                                    LOAD_LIBRARY_SEARCH_SYSTEM32);
    if (!module)
      return {};
    if (!Bind(module, "WebAuthNGetApiVersionNumber", api.version) ||
        !Bind(module, "WebAuthNAuthenticatorGetAssertion",
              api.get_assertion) ||
        !Bind(module, "WebAuthNFreeAssertion", api.free_assertion) ||
        !Bind(module, "WebAuthNGetCancellationId", api.cancellation_id) ||
        !Bind(module, "WebAuthNCancelCurrentOperation", api.cancel) ||
        !Bind(module, "WebAuthNGetErrorName", api.error_name)) {
      return {};
    }
    // PRF evaluation on assertions arrived with API version 4.
    if (api.version() < WEBAUTHN_API_VERSION_4)
      return {};
    return api;
  }
};

struct Job {
  uint64_t id = 0;
  HWND window = nullptr;
  std::wstring rp_id;
  std::string client_data;
  Bytes salt;
  std::vector<Bytes> allowed;
  DWORD timeout = 120000;
  GUID cancellation{};
  bool cancellable = false;
  // A cancel can arrive before the worker reaches the API, when there is no
  // operation yet for the cancellation ID to stop.
  std::atomic<bool> cancelled{false};
};

struct Outcome {
  uint64_t id = 0;
  const char *error = nullptr;
  Bytes credential_id, user_handle, authenticator_data, client_data,
      signature, prf;
};

std::string Base64Url(const Bytes &bytes) {
  static const char alphabet[] =
      "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_";
  std::string out;
  size_t i = 0;
  for (; i + 2 < bytes.size(); i += 3) {
    const uint32_t n = (bytes[i] << 16) | (bytes[i + 1] << 8) | bytes[i + 2];
    for (int shift : {18, 12, 6, 0})
      out.push_back(alphabet[(n >> shift) & 63]);
  }
  if (i + 1 == bytes.size()) {
    const uint32_t n = bytes[i] << 16;
    out.push_back(alphabet[(n >> 18) & 63]);
    out.push_back(alphabet[(n >> 12) & 63]);
  } else if (i + 2 == bytes.size()) {
    const uint32_t n = (bytes[i] << 16) | (bytes[i + 1] << 8);
    for (int shift : {18, 12, 6})
      out.push_back(alphabet[(n >> shift) & 63]);
  }
  return out;
}

// The relying party is a host name. Restricting it keeps the client data,
// which this bridge composes itself, well-formed JSON.
bool ValidRpId(const std::string &rp_id) {
  if (rp_id.empty() || rp_id.size() > 253)
    return false;
  for (char c : rp_id) {
    if (!((c >= 'a' && c <= 'z') || (c >= '0' && c <= '9') || c == '-' ||
          c == '.'))
      return false;
  }
  return true;
}

const char *FailureCode(const WebAuthnApi &api, HRESULT hr) {
  if (hr == NTE_USER_CANCELLED || hr == HRESULT_FROM_WIN32(ERROR_CANCELLED) ||
      hr == HRESULT_FROM_WIN32(ERROR_TIMEOUT))
    return "canceled";
  if (hr == NTE_NOT_FOUND)
    return "noCredential";
  // Also reported as NotAllowedError, but nothing was offered to decline.
  if (hr == NTE_DEVICE_NOT_FOUND)
    return "unavailable";
  // WebAuthn reports dismissal and timeout alike as NotAllowedError.
  PCWSTR name = api.error_name(hr);
  if (name && std::wcscmp(name, L"NotAllowedError") == 0)
    return "canceled";
  return "unavailable";
}

Outcome Run(const WebAuthnApi &api, Job &job) {
  Outcome outcome;
  outcome.id = job.id;
  // This thread runs no message loop, so it joins the multithreaded
  // apartment rather than creating a single-threaded one.
  const HRESULT com = CoInitializeEx(nullptr, COINIT_MULTITHREADED);
  std::vector<WEBAUTHN_CREDENTIAL> credentials;
  for (auto &id : job.allowed) {
    credentials.push_back({WEBAUTHN_CREDENTIAL_CURRENT_VERSION,
                           static_cast<DWORD>(id.size()), id.data(),
                           WEBAUTHN_CREDENTIAL_TYPE_PUBLIC_KEY});
  }
  // Without WEBAUTHN_AUTHENTICATOR_HMAC_SECRET_VALUES_FLAG these are PRF
  // inputs, which the platform hashes exactly as browsers do.
  WEBAUTHN_HMAC_SECRET_SALT salt{static_cast<DWORD>(job.salt.size()),
                                 job.salt.data(), 0, nullptr};
  WEBAUTHN_HMAC_SECRET_SALT_VALUES salts{&salt, 0, nullptr};
  WEBAUTHN_CLIENT_DATA client{
      WEBAUTHN_CLIENT_DATA_CURRENT_VERSION,
      static_cast<DWORD>(job.client_data.size()),
      reinterpret_cast<PBYTE>(job.client_data.data()),
      WEBAUTHN_HASH_ALGORITHM_SHA_256};
  WEBAUTHN_AUTHENTICATOR_GET_ASSERTION_OPTIONS options{};
  options.dwVersion = WEBAUTHN_AUTHENTICATOR_GET_ASSERTION_OPTIONS_VERSION_6;
  options.dwTimeoutMilliseconds = job.timeout;
  options.CredentialList = {static_cast<DWORD>(credentials.size()),
                            credentials.empty() ? nullptr : credentials.data()};
  options.dwAuthenticatorAttachment = WEBAUTHN_AUTHENTICATOR_ATTACHMENT_ANY;
  // A PRF evaluated without verification uses a different secret and would
  // not open the envelope.
  options.dwUserVerificationRequirement =
      WEBAUTHN_USER_VERIFICATION_REQUIREMENT_REQUIRED;
  options.pCancellationId = job.cancellable ? &job.cancellation : nullptr;
  options.pHmacSecretSaltValues = &salts;

  PWEBAUTHN_ASSERTION assertion = nullptr;
  const HRESULT hr =
      job.cancelled ? HRESULT_FROM_WIN32(ERROR_CANCELLED)
                    : api.get_assertion(job.window, job.rp_id.c_str(), &client,
                                        &options, &assertion);
  if (FAILED(hr) || !assertion) {
    outcome.error = FailureCode(api, hr);
  } else {
    const auto *secret = assertion->dwVersion >= WEBAUTHN_ASSERTION_VERSION_3
                             ? assertion->pHmacSecret
                             : nullptr;
    if (!secret || !secret->pbFirst ||
        secret->cbFirst != WEBAUTHN_CTAP_ONE_HMAC_SECRET_LENGTH) {
      outcome.error = "prfUnavailable";
    } else {
      const auto copy = [](const BYTE *data, DWORD size) {
        return data ? Bytes(data, data + size) : Bytes();
      };
      outcome.credential_id =
          copy(assertion->Credential.pbId, assertion->Credential.cbId);
      outcome.user_handle = copy(assertion->pbUserId, assertion->cbUserId);
      outcome.authenticator_data =
          copy(assertion->pbAuthenticatorData, assertion->cbAuthenticatorData);
      outcome.signature = copy(assertion->pbSignature, assertion->cbSignature);
      outcome.client_data = Bytes(job.client_data.begin(),
                                  job.client_data.end());
      outcome.prf = copy(secret->pbFirst, secret->cbFirst);
      SecureZeroMemory(secret->pbFirst, secret->cbFirst);
    }
    api.free_assertion(assertion);
  }
  Wipe(job.salt);
  if (SUCCEEDED(com))
    CoUninitialize();
  return outcome;
}

} // namespace

struct PasskeyChannel::Impl {
  struct Delivery {
    std::mutex mutex;
    bool alive = true;
    HWND window = nullptr;
    std::deque<Outcome> outcomes;
  };

  struct Pending {
    uint64_t id = 0;
    std::unique_ptr<Result> result;
    std::shared_ptr<Job> job;
  };

  HWND window;
  uint64_t next_id = 0;
  std::shared_ptr<Delivery> delivery = std::make_shared<Delivery>();
  std::unique_ptr<Pending> pending;
  // The worker of a cancelled request may still hold the system dialog, so
  // a new request waits for its outcome.
  uint64_t running = 0;
  std::unique_ptr<flutter::MethodChannel<Value>> channel;

  Impl(HWND owner, flutter::BinaryMessenger *messenger) : window(owner) {
    delivery->window = owner;
    channel = std::make_unique<flutter::MethodChannel<Value>>(
        messenger, "gleec.wallet/passkey",
        &flutter::StandardMethodCodec::GetInstance());
    channel->SetMethodCallHandler([this](const auto &call, auto result) {
      HandleCall(call, std::move(result));
    });
  }

  ~Impl() {
    channel->SetMethodCallHandler(nullptr);
    Cancel();
    {
      std::lock_guard<std::mutex> lock(delivery->mutex);
      delivery->alive = false;
      for (auto &outcome : delivery->outcomes)
        Wipe(outcome.prf);
      delivery->outcomes.clear();
    }
    channel.reset();
  }

  // Answers the waiting call at once; the worker's eventual outcome no
  // longer matches a pending request and is discarded.
  void Cancel() {
    if (!pending)
      return;
    pending->job->cancelled = true;
    if (pending->job->cancellable) {
      if (const auto *api = WebAuthnApi::Get())
        api->cancel(&pending->job->cancellation);
    }
    pending->result->Error("canceled", kMessage);
    pending.reset();
  }

  void HandleCall(const flutter::MethodCall<Value> &call,
                  std::unique_ptr<Result> result) {
    if (call.method_name() == "support") {
      result->Success(Value(flutter::EncodableMap{
          {Value("available"), Value(WebAuthnApi::Get() != nullptr)}}));
    } else if (call.method_name() == "cancel") {
      Cancel();
      result->Success();
    } else if (call.method_name() == "getAssertion") {
      Begin(call, std::move(result));
    } else {
      result->NotImplemented();
    }
  }

  void Begin(const flutter::MethodCall<Value> &call,
             std::unique_ptr<Result> result) {
    const WebAuthnApi *api = WebAuthnApi::Get();
    if (!api) {
      result->Error("unavailable", kMessage);
      return;
    }
    if (pending || running) {
      result->Error("busy", kMessage);
      return;
    }
    const auto *args = std::get_if<flutter::EncodableMap>(call.arguments());
    const auto field = [args](const char *name) -> const Value * {
      if (!args)
        return nullptr;
      auto found = args->find(Value(name));
      return found == args->end() ? nullptr : &found->second;
    };
    const auto *rp_id = field("rpId") ? std::get_if<std::string>(field("rpId"))
                                      : nullptr;
    const auto *challenge =
        field("challenge") ? std::get_if<Bytes>(field("challenge")) : nullptr;
    const auto *salt = field("salt") ? std::get_if<Bytes>(field("salt")) : nullptr;
    const auto *allowed =
        field("allowCredentials")
            ? std::get_if<flutter::EncodableList>(field("allowCredentials"))
            : nullptr;
    if (!rp_id || !ValidRpId(*rp_id) || !challenge || challenge->size() < 16 ||
        !salt || salt->size() != 32 || !allowed || allowed->size() > 16) {
      result->Error("invalidResponse", kMessage);
      return;
    }
    auto job = std::make_shared<Job>();
    for (const auto &entry : *allowed) {
      const auto *id = std::get_if<Bytes>(&entry);
      if (!id || id->empty() || id->size() > 1023) {
        result->Error("invalidResponse", kMessage);
        return;
      }
      job->allowed.push_back(*id);
    }
    if (const auto *timeout = field("timeoutMs")) {
      if (const auto *millis = std::get_if<int32_t>(timeout); millis && *millis > 0)
        job->timeout = static_cast<DWORD>(*millis);
    }
    job->id = ++next_id;
    job->window = window;
    job->rp_id = std::wstring(rp_id->begin(), rp_id->end());
    job->salt = *salt;
    // The challenge is this request's own; the PRF output, not this client
    // data, is what the Dart side relies on.
    job->client_data = "{\"type\":\"webauthn.get\",\"challenge\":\"" +
                       Base64Url(*challenge) + "\",\"origin\":\"https://" +
                       *rp_id + "\",\"crossOrigin\":false}";
    job->cancellable = SUCCEEDED(api->cancellation_id(&job->cancellation));
    pending = std::make_unique<Pending>();
    pending->id = job->id;
    pending->result = std::move(result);
    pending->job = job;
    running = job->id;
    std::weak_ptr<Delivery> weak = delivery;
    std::thread([api, job, weak]() {
      Outcome outcome = Run(*api, *job);
      if (auto target = weak.lock()) {
        std::lock_guard<std::mutex> lock(target->mutex);
        if (target->alive) {
          target->outcomes.push_back(std::move(outcome));
          PostMessageW(target->window, kCompletionMessage, 0, 0);
          return;
        }
      }
      Wipe(outcome.prf);
    }).detach();
  }

  bool HandleMessage(UINT message, WPARAM wparam) {
    if (message == WM_WTSSESSION_CHANGE && wparam == WTS_SESSION_LOCK) {
      Cancel();
      return false;
    }
    if (message != kCompletionMessage)
      return false;
    std::deque<Outcome> ready;
    {
      std::lock_guard<std::mutex> lock(delivery->mutex);
      ready.swap(delivery->outcomes);
    }
    for (auto &outcome : ready) {
      if (running == outcome.id)
        running = 0;
      if (pending && pending->id == outcome.id) {
        auto result = std::move(pending->result);
        pending.reset();
        if (outcome.error) {
          result->Error(outcome.error, kMessage);
        } else {
          result->Success(Value(flutter::EncodableMap{
              {Value("credentialId"), Value(outcome.credential_id)},
              {Value("userHandle"), outcome.user_handle.empty()
                                        ? Value()
                                        : Value(outcome.user_handle)},
              {Value("authenticatorData"), Value(outcome.authenticator_data)},
              {Value("clientDataJSON"), Value(outcome.client_data)},
              {Value("signature"), Value(outcome.signature)},
              {Value("prf"), Value(outcome.prf)},
          }));
        }
      }
      Wipe(outcome.prf);
    }
    return true;
  }
};

PasskeyChannel::PasskeyChannel(HWND window, flutter::BinaryMessenger *messenger)
    : impl_(std::make_unique<Impl>(window, messenger)) {}
PasskeyChannel::~PasskeyChannel() = default;
bool PasskeyChannel::HandleMessage(UINT message, WPARAM wparam) {
  return impl_->HandleMessage(message, wparam);
}
