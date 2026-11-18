#include "security_key_channel_jobs.h"

#include <dlfcn.h>
#include <glib.h>
#include <string.h>
#include <unistd.h>

#include <algorithm>
#include <cstring>
#include <utility>

namespace security_key {
namespace {

// libfido2 waits forever by default, and nothing can interrupt a worker that
// is still opening a key, so a stalled one must not get the request's wait.
constexpr int kOpenTimeoutMs = 3000;

void Silent(const char*) {}

template <class Function>
bool Bind(void* library, const char* name, Function& slot) {
  slot = reinterpret_cast<Function>(dlsym(library, name));
  return slot != nullptr;
}

const Fido* Load() {
  void* library = dlopen("libfido2.so.1", RTLD_NOW | RTLD_LOCAL);
  if (!library)
    return nullptr;
  auto* api = new Fido();
  bool complete = true;
#define GLEEC_FIDO_BIND(name)                                                  \
  complete = complete && Bind(library, #name, api->name);
  GLEEC_FIDO_SYMBOLS(GLEEC_FIDO_BIND)
#undef GLEEC_FIDO_BIND
  if (!complete) {
    delete api;
    dlclose(library);
    return nullptr;
  }
  api->fido_init(0);
  // FIDO_DEBUG in the environment would otherwise trace frames to stderr.
  api->fido_set_log_handler(Silent);
  return api;
}

std::string Text(const char* text, size_t limit) {
  if (!text)
    return std::string();
  gchar* valid =
      g_utf8_make_valid(text, static_cast<gssize>(strnlen(text, limit)));
  std::string out(valid);
  g_free(valid);
  return out;
}

Bytes Copy(const unsigned char* data, size_t size) {
  return data && size ? Bytes(data, data + size) : Bytes();
}

void Close(const Fido& api, fido_dev_t*& dev) {
  if (!dev)
    return;
  api.fido_dev_close(dev);
  api.fido_dev_free(&dev);
}

void Describe(const Fido& api, Device& device) {
  fido_dev_t* dev = api.fido_dev_new();
  fido_cbor_info_t* info = api.fido_cbor_info_new();
  if (dev && info && api.fido_dev_set_timeout(dev, kOpenTimeoutMs) == FIDO_OK &&
      api.fido_dev_open(dev, device.path.c_str()) == FIDO_OK) {
    // A U2F-only key is listed as ready without hmac-secret.
    if (!api.fido_dev_is_fido2(dev)) {
      device.state = "ready";
    } else if (api.fido_dev_get_cbor_info(dev, info) == FIDO_OK) {
      device.state = "ready";
      char** extensions = api.fido_cbor_info_extensions_ptr(info);
      for (size_t i = 0; i < api.fido_cbor_info_extensions_len(info); i++) {
        if (std::strcmp(extensions[i], "hmac-secret") == 0)
          device.hmac_secret = true;
      }
      char** names = api.fido_cbor_info_options_name_ptr(info);
      const bool* values = api.fido_cbor_info_options_value_ptr(info);
      for (size_t i = 0; i < api.fido_cbor_info_options_len(info); i++) {
        if (std::strcmp(names[i], "clientPin") == 0)
          device.pin = values[i];
        if (std::strcmp(names[i], "uv") == 0)
          device.uv = values[i];
      }
      int retries = 0;
      if (device.pin && api.fido_dev_get_retry_count(dev, &retries) == FIDO_OK)
        device.pin_retries = retries;
      if (device.uv &&
          api.fido_dev_get_uv_retry_count(dev, &retries) == FIDO_OK)
        device.uv_retries = retries;
    }
  }
  if (info)
    api.fido_cbor_info_free(&info);
  Close(api, dev);
}

Outcome ListDevices(const Fido& api) {
  Outcome outcome;
  fido_dev_info_t* list = api.fido_dev_info_new(kMaxDevices);
  size_t found = 0;
  if (!list ||
      api.fido_dev_info_manifest(list, kMaxDevices, &found) != FIDO_OK) {
    outcome.error = "unavailable";
  } else {
    for (size_t i = 0; i < found; i++) {
      const fido_dev_info_t* info = api.fido_dev_info_ptr(list, i);
      Device device;
      device.path = Text(api.fido_dev_info_path(info), 64);
      if (!ValidPath(device.path))
        continue;
      const std::string maker =
          Text(api.fido_dev_info_manufacturer_string(info), 64);
      const std::string product =
          Text(api.fido_dev_info_product_string(info), 64);
      device.product = maker.empty() || product.rfind(maker, 0) == 0
                           ? product
                           : maker + " " + product;
      // Enumeration reads sysfs, so a key the session may not open is still
      // listed; saying so beats reporting no key at all.
      if (access(device.path.c_str(), R_OK | W_OK) != 0)
        device.state = "noAccess";
      else
        Describe(api, device);
      outcome.devices.push_back(std::move(device));
    }
  }
  if (list)
    api.fido_dev_info_free(&list, kMaxDevices);
  return outcome;
}

// The key the user touches is the one used. A PIN is never sent to a key
// the user did not pick: a wrong guess spends that key's tries.
Outcome Select(const Fido& api, Job& job) {
  struct Waiting {
    std::string path;
    fido_dev_t* dev;
  };
  std::vector<Waiting> waiting;
  for (const auto& path : job.paths) {
    fido_dev_t* dev = api.fido_dev_new();
    if (dev && api.fido_dev_set_timeout(dev, kOpenTimeoutMs) == FIDO_OK &&
        api.fido_dev_open(dev, path.c_str()) == FIDO_OK &&
        api.fido_dev_get_touch_begin(dev) == FIDO_OK) {
      waiting.push_back({path, dev});
    } else {
      Close(api, dev);
    }
  }
  const gint64 deadline =
      g_get_monotonic_time() + static_cast<gint64>(job.timeout_ms) * 1000;
  std::string chosen;
  while (chosen.empty() && !waiting.empty() && !job.cancelled &&
         g_get_monotonic_time() < deadline) {
    for (auto it = waiting.begin(); it != waiting.end() && chosen.empty();) {
      int touched = 0;
      // libfido2 reports a removed key's failed reads as "not touched yet".
      if (access(it->path.c_str(), F_OK) != 0 ||
          api.fido_dev_get_touch_status(it->dev, &touched, 50) != FIDO_OK) {
        Close(api, it->dev);
        it = waiting.erase(it);
        continue;
      }
      if (touched)
        chosen = it->path;
      ++it;
    }
    if (chosen.empty())
      g_usleep(20000);
  }
  const bool gone = waiting.empty();
  for (auto& entry : waiting) {
    if (entry.path != chosen)
      api.fido_dev_cancel(entry.dev);
    Close(api, entry.dev);
  }
  Outcome outcome;
  if (job.cancelled)
    outcome.error = "canceled";
  else if (!chosen.empty())
    outcome.path = chosen;
  else
    outcome.error = gone ? "deviceGone" : "timeout";
  return outcome;
}

int Prepare(const Fido& api, fido_assert_t* assertion, const Job& job) {
  int status = api.fido_assert_set_rp(assertion, job.rp_id.c_str());
  if (status == FIDO_OK)
    status = api.fido_assert_set_clientdata_hash(
        assertion, job.client_data_hash.data(), job.client_data_hash.size());
  for (const auto& id : job.allowed) {
    if (status == FIDO_OK)
      status = api.fido_assert_allow_cred(assertion, id.data(), id.size());
  }
  if (status == FIDO_OK)
    status = api.fido_assert_set_extensions(assertion, FIDO_EXT_HMAC_SECRET);
  // Already the WebAuthn PRF salt: libfido2 passes hmac-secret input raw.
  if (status == FIDO_OK)
    status = api.fido_assert_set_hmac_salt(assertion, job.salt.data(),
                                           job.salt.size());
  // hmac-secret has a separate secret for verified requests, and only that
  // one opens an envelope.
  if (status == FIDO_OK)
    status = api.fido_assert_set_uv(assertion, FIDO_OPT_TRUE);
  return status;
}

void Collect(const Fido& api, const fido_assert_t* assertion,
             Outcome& outcome) {
  const size_t count = std::min<size_t>(api.fido_assert_count(assertion), 16);
  bool any_prf = false;
  for (size_t i = 0; i < count; i++) {
    Candidate candidate;
    candidate.credential_id = Copy(api.fido_assert_id_ptr(assertion, i),
                                   api.fido_assert_id_len(assertion, i));
    candidate.user_handle = Copy(api.fido_assert_user_id_ptr(assertion, i),
                                 api.fido_assert_user_id_len(assertion, i));
    candidate.user_name = Text(api.fido_assert_user_name(assertion, i), 256);
    candidate.display_name =
        Text(api.fido_assert_user_display_name(assertion, i), 256);
    candidate.signature = Copy(api.fido_assert_sig_ptr(assertion, i),
                               api.fido_assert_sig_len(assertion, i));
    if (candidate.credential_id.empty() ||
        !RawAuthenticatorData(api.fido_assert_authdata_ptr(assertion, i),
                              api.fido_assert_authdata_len(assertion, i),
                              candidate.authenticator_data)) {
      outcome.error = "invalidResponse";
      break;
    }
    if (api.fido_assert_hmac_secret_len(assertion, i) == 32) {
      candidate.prf = Copy(api.fido_assert_hmac_secret_ptr(assertion, i), 32);
      any_prf = true;
    }
    outcome.candidates.push_back(std::move(candidate));
  }
  if (!outcome.error && !any_prf)
    outcome.error = count ? "prfUnavailable" : "noCredential";
  if (outcome.error) {
    outcome.WipeSecrets();
    outcome.candidates.clear();
  }
}

Outcome Assert(const Fido& api, Job& job) {
  Outcome outcome;
  const std::string& path = job.paths.front();
  const bool pin = !job.pin.empty();
  fido_dev_t* dev = api.fido_dev_new();
  fido_assert_t* assertion = api.fido_assert_new();
  if (!dev || !assertion) {
    outcome.error = "unavailable";
  } else if (access(path.c_str(), R_OK | W_OK) != 0) {
    outcome.error = access(path.c_str(), F_OK) == 0 ? "noAccess" : "deviceGone";
  } else if (api.fido_dev_set_timeout(dev, kOpenTimeoutMs) != FIDO_OK ||
             api.fido_dev_open(dev, path.c_str()) != FIDO_OK ||
             api.fido_dev_set_timeout(dev, job.timeout_ms) != FIDO_OK) {
    outcome.error = "deviceGone";
  } else {
    int status = Prepare(api, assertion, job);
    if (status == FIDO_OK) {
      {
        std::lock_guard<std::mutex> lock(job.mutex);
        job.active = dev;
      }
      status = job.cancelled
                   ? FIDO_ERR_KEEPALIVE_CANCEL
                   : api.fido_dev_get_assert(
                         dev, assertion,
                         pin ? reinterpret_cast<const char*>(job.pin.data())
                             : nullptr);
      std::lock_guard<std::mutex> lock(job.mutex);
      job.active = nullptr;
    }
    Wipe(job.pin);
    if (status == FIDO_OK) {
      Collect(api, assertion, outcome);
    } else {
      outcome.error = job.cancelled ? "canceled" : FailureCode(status, pin);
      int retries = 0;
      if (status == FIDO_ERR_PIN_INVALID &&
          api.fido_dev_get_retry_count(dev, &retries) == FIDO_OK)
        outcome.retries = retries;
      if (status == FIDO_ERR_UV_INVALID &&
          api.fido_dev_get_uv_retry_count(dev, &retries) == FIDO_OK)
        outcome.retries = retries;
    }
  }
  Wipe(job.pin);
  if (assertion)
    api.fido_assert_free(&assertion);
  Close(api, dev);
  return outcome;
}

}  // namespace

void Wipe(Bytes& bytes) {
  if (!bytes.empty())
    explicit_bzero(bytes.data(), bytes.size());
  bytes.clear();
}

// The relying party is a host name. Restricting it keeps the client data
// the Dart side composes for it well-formed JSON.
bool ValidRpId(const std::string& rp_id) {
  if (rp_id.empty() || rp_id.size() > 253)
    return false;
  for (char c : rp_id) {
    if (!((c >= 'a' && c <= 'z') || (c >= '0' && c <= '9') || c == '-' ||
          c == '.'))
      return false;
  }
  return true;
}

// The native test harness points this at a temporary directory.
#ifndef GLEEC_SECURITY_KEY_PATH_PREFIX
#define GLEEC_SECURITY_KEY_PATH_PREFIX "/dev/hidraw"
#endif

bool ValidPath(const std::string& path) {
  static const std::string prefix = GLEEC_SECURITY_KEY_PATH_PREFIX;
  if (path.size() <= prefix.size() || path.size() > prefix.size() + 8 ||
      path.compare(0, prefix.size(), prefix) != 0)
    return false;
  return std::all_of(path.begin() + prefix.size(), path.end(),
                     [](char c) { return c >= '0' && c <= '9'; });
}

// libfido2 before 1.14 has no raw accessor; it keeps authenticator data as
// the CBOR byte string the key sent.
bool RawAuthenticatorData(const unsigned char* cbor, size_t size, Bytes& out) {
  if (!cbor || size < 2 || (cbor[0] & 0xe0) != 0x40)
    return false;
  const unsigned info = cbor[0] & 0x1f;
  size_t header = 1;
  size_t length = info;
  if (info == 24) {
    header = 2;
    length = cbor[1];
  } else if (info == 25 && size >= 3) {
    header = 3;
    length = (static_cast<size_t>(cbor[1]) << 8) | cbor[2];
  } else if (info >= 24) {
    return false;
  }
  if (header + length != size || length < 37)
    return false;
  out.assign(cbor + header, cbor + size);
  return true;
}

const char* FailureCode(int status, bool pin_supplied) {
  switch (status) {
  case FIDO_ERR_PIN_INVALID:
    return "pinInvalid";
  case FIDO_ERR_PIN_AUTH_BLOCKED:
    return "pinAuthBlocked";
  case FIDO_ERR_PIN_BLOCKED:
    return "pinBlocked";
  case FIDO_ERR_PIN_NOT_SET:
    return "pinNotSet";
  // Built-in verification was asked of a key that has only a PIN.
  case FIDO_ERR_PIN_REQUIRED:
  case FIDO_ERR_UNSUPPORTED_OPTION:
  case FIDO_ERR_INVALID_OPTION:
    return pin_supplied ? "unavailable" : "pinRequired";
  case FIDO_ERR_UV_INVALID:
    return "uvInvalid";
  case FIDO_ERR_UV_BLOCKED:
    return "uvBlocked";
  case FIDO_ERR_NO_CREDENTIALS:
    return "noCredential";
  case FIDO_ERR_UNSUPPORTED_EXTENSION:
    return "prfUnavailable";
  case FIDO_ERR_KEEPALIVE_CANCEL:
  case FIDO_ERR_OPERATION_DENIED:
    return "canceled";
  case FIDO_ERR_ACTION_TIMEOUT:
  case FIDO_ERR_USER_ACTION_TIMEOUT:
    return "timeout";
  case FIDO_ERR_TX:
  case FIDO_ERR_RX:
  case FIDO_ERR_RX_NOT_CBOR:
  case FIDO_ERR_RX_INVALID_CBOR:
    return "deviceGone";
  default:
    return "unavailable";
  }
}

const Fido* Fido::Get() {
  static const Fido* api = Load();
  return api;
}

Outcome Run(const Fido& api, Job& job) {
  switch (job.kind) {
  case Kind::kDevices:
    return ListDevices(api);
  case Kind::kSelect:
    return Select(api, job);
  case Kind::kAssert:
    return Assert(api, job);
  }
  return Outcome();
}

void Interrupt(Job& job) {
  job.cancelled = true;
  std::lock_guard<std::mutex> lock(job.mutex);
  const Fido* api = Fido::Get();
  if (job.active && api)
    api->fido_dev_cancel(job.active);
}

}  // namespace security_key
