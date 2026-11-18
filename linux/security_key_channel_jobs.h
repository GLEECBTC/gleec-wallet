#ifndef RUNNER_SECURITY_KEY_CHANNEL_JOBS_H_
#define RUNNER_SECURITY_KEY_CHANNEL_JOBS_H_

#include <fido.h>

#include <atomic>
#include <cstdint>
#include <deque>
#include <mutex>
#include <string>
#include <vector>

struct _SecurityKeyChannel;

namespace security_key {

using Bytes = std::vector<uint8_t>;

constexpr size_t kMaxDevices = 8;

void Wipe(Bytes& bytes);
bool ValidRpId(const std::string& rp_id);
bool ValidPath(const std::string& path);
bool RawAuthenticatorData(const unsigned char* cbor, size_t size, Bytes& out);
const char* FailureCode(int status, bool pin_supplied);

#define GLEEC_FIDO_SYMBOLS(X)                                                  \
  X(fido_init)                                                                 \
  X(fido_set_log_handler)                                                      \
  X(fido_dev_info_new)                                                         \
  X(fido_dev_info_free)                                                        \
  X(fido_dev_info_manifest)                                                    \
  X(fido_dev_info_ptr)                                                         \
  X(fido_dev_info_path)                                                        \
  X(fido_dev_info_manufacturer_string)                                         \
  X(fido_dev_info_product_string)                                              \
  X(fido_dev_new)                                                              \
  X(fido_dev_free)                                                             \
  X(fido_dev_open)                                                             \
  X(fido_dev_close)                                                            \
  X(fido_dev_is_fido2)                                                         \
  X(fido_dev_cancel)                                                           \
  X(fido_dev_set_timeout)                                                      \
  X(fido_dev_get_touch_begin)                                                  \
  X(fido_dev_get_touch_status)                                                 \
  X(fido_dev_get_retry_count)                                                  \
  X(fido_dev_get_uv_retry_count)                                               \
  X(fido_cbor_info_new)                                                        \
  X(fido_cbor_info_free)                                                       \
  X(fido_dev_get_cbor_info)                                                    \
  X(fido_cbor_info_extensions_ptr)                                             \
  X(fido_cbor_info_extensions_len)                                             \
  X(fido_cbor_info_options_name_ptr)                                           \
  X(fido_cbor_info_options_value_ptr)                                          \
  X(fido_cbor_info_options_len)                                                \
  X(fido_assert_new)                                                           \
  X(fido_assert_free)                                                          \
  X(fido_assert_set_rp)                                                        \
  X(fido_assert_set_clientdata_hash)                                           \
  X(fido_assert_allow_cred)                                                    \
  X(fido_assert_set_extensions)                                                \
  X(fido_assert_set_hmac_salt)                                                 \
  X(fido_assert_set_uv)                                                        \
  X(fido_dev_get_assert)                                                       \
  X(fido_assert_count)                                                         \
  X(fido_assert_id_ptr)                                                        \
  X(fido_assert_id_len)                                                        \
  X(fido_assert_user_id_ptr)                                                   \
  X(fido_assert_user_id_len)                                                   \
  X(fido_assert_user_name)                                                     \
  X(fido_assert_user_display_name)                                             \
  X(fido_assert_authdata_ptr)                                                  \
  X(fido_assert_authdata_len)                                                  \
  X(fido_assert_sig_ptr)                                                       \
  X(fido_assert_sig_len)                                                       \
  X(fido_assert_hmac_secret_ptr)                                               \
  X(fido_assert_hmac_secret_len)

// The header supplies only the types: every function is resolved from
// libfido2.so.1 at runtime, so a missing library cannot stop the app.
struct Fido {
#define GLEEC_FIDO_SLOT(name) decltype(&::name) name = nullptr;
  GLEEC_FIDO_SYMBOLS(GLEEC_FIDO_SLOT)
#undef GLEEC_FIDO_SLOT

  static const Fido* Get();
};

enum class Kind { kDevices, kSelect, kAssert };

struct Job {
  ~Job() { Wipe(pin); }

  uint64_t id = 0;
  Kind kind = Kind::kDevices;
  std::vector<std::string> paths;
  std::string rp_id;
  Bytes client_data_hash, salt;
  // NUL-terminated for libfido2, or empty to use built-in verification.
  Bytes pin;
  std::vector<Bytes> allowed;
  int timeout_ms = 120000;
  std::atomic<bool> cancelled{false};
  std::mutex mutex;
  fido_dev_t* active = nullptr;  // Guarded by mutex.
};

struct Device {
  std::string path, product;
  const char* state = "unreadable";  // ready, noAccess or unreadable.
  bool hmac_secret = false, pin = false, uv = false;
  int pin_retries = -1, uv_retries = -1;
};

struct Candidate {
  Bytes credential_id, user_handle, authenticator_data, signature, prf;
  std::string user_name, display_name;
};

struct Outcome {
  uint64_t id = 0;
  const char* error = nullptr;
  int retries = -1;
  std::string path;
  std::vector<Device> devices;
  std::vector<Candidate> candidates;

  void WipeSecrets() {
    for (auto& candidate : candidates)
      Wipe(candidate.prf);
  }
};

// Worker outcomes waiting for the platform thread. [owner] is read and
// cleared under [mutex] and used only on the platform thread.
struct Delivery {
  std::mutex mutex;
  std::deque<Outcome> outcomes;
  _SecurityKeyChannel* owner = nullptr;
};

// Blocks until the key answers, the request times out or it is interrupted.
Outcome Run(const Fido& api, Job& job);

// Stops [job] from another thread. A selection notices within one poll; an
// assertion is sent CTAPHID_CANCEL, which the key answers by ending it.
void Interrupt(Job& job);

}  // namespace security_key

#endif  // RUNNER_SECURITY_KEY_CHANNEL_JOBS_H_
