#include "fake_fido2.h"

#include <chrono>
#include <cstring>

namespace {

fake::Scenario scenario;

using Blob = std::vector<unsigned char>;

Blob Pattern(unsigned char seed, size_t size) {
  Blob out(size);
  for (size_t i = 0; i < size; i++)
    out[i] = static_cast<unsigned char>(seed + i);
  return out;
}

// The key sends authenticator data as a CBOR byte string; libfido2 keeps it
// that way.
Blob CborBytes(const Blob& raw) {
  Blob out;
  if (raw.size() < 24) {
    out.push_back(static_cast<unsigned char>(0x40 | raw.size()));
  } else if (raw.size() < 256) {
    out = {0x58, static_cast<unsigned char>(raw.size())};
  } else {
    out = {0x59, static_cast<unsigned char>(raw.size() >> 8),
           static_cast<unsigned char>(raw.size() & 0xff)};
  }
  out.insert(out.end(), raw.begin(), raw.end());
  return out;
}

}  // namespace

struct fido_dev_info {
  std::string path, maker, product;
};

struct fido_dev {
  int index = -1;
  bool open = false;
  int polls = 0;
};

struct fido_cbor_info {
  std::vector<std::string> extension_text, option_text;
  std::vector<char*> extensions, names;
  bool values[8] = {};
};

struct fido_assert {
  struct Statement {
    Blob id, user_id, authdata, signature, hmac;
    std::string name, display_name;
  };
  std::vector<Statement> statements;
};

extern "C" {

fake::Scenario* fake_scenario() { return &scenario; }

void fido_init(int) {}
void fido_set_log_handler(fido_log_handler_t* handler) {
  scenario.log_handler_set = handler != nullptr;
}

fido_dev_info_t* fido_dev_info_new(size_t count) {
  return new fido_dev_info_t[count];
}
void fido_dev_info_free(fido_dev_info_t** list, size_t) {
  delete[] *list;
  *list = nullptr;
}
int fido_dev_info_manifest(fido_dev_info_t* list, size_t limit,
                           size_t* found) {
  *found = 0;
  for (const auto& device : scenario.devices) {
    if (*found == limit)
      break;
    list[(*found)++] = {device.path, device.maker, device.product};
  }
  return FIDO_OK;
}
const fido_dev_info_t* fido_dev_info_ptr(const fido_dev_info_t* list,
                                         size_t i) {
  return &list[i];
}
const char* fido_dev_info_path(const fido_dev_info_t* info) {
  return info->path.c_str();
}
const char* fido_dev_info_manufacturer_string(const fido_dev_info_t* info) {
  return info->maker.c_str();
}
const char* fido_dev_info_product_string(const fido_dev_info_t* info) {
  return info->product.c_str();
}

fido_dev_t* fido_dev_new(void) { return new fido_dev_t(); }
void fido_dev_free(fido_dev_t** dev) {
  delete *dev;
  *dev = nullptr;
}
int fido_dev_open(fido_dev_t* dev, const char* path) {
  for (size_t i = 0; i < scenario.devices.size(); i++) {
    if (scenario.devices[i].path == path) {
      dev->index = static_cast<int>(i);
      dev->open = true;
      std::lock_guard<std::mutex> lock(scenario.mutex);
      scenario.opened++;
      return FIDO_OK;
    }
  }
  return FIDO_ERR_INTERNAL;
}
int fido_dev_close(fido_dev_t* dev) {
  if (!dev->open)
    return FIDO_ERR_INVALID_ARGUMENT;
  dev->open = false;
  std::lock_guard<std::mutex> lock(scenario.mutex);
  scenario.closed++;
  return FIDO_OK;
}
bool fido_dev_is_fido2(const fido_dev_t* dev) {
  return scenario.devices[dev->index].fido2;
}
int fido_dev_cancel(fido_dev_t* dev) {
  std::lock_guard<std::mutex> lock(scenario.mutex);
  scenario.cancelled.push_back(scenario.devices[dev->index].path);
  scenario.changed.notify_all();
  return FIDO_OK;
}
int fido_dev_set_timeout(fido_dev_t*, int) { return FIDO_OK; }
int fido_dev_get_touch_begin(fido_dev_t*) { return FIDO_OK; }
int fido_dev_get_touch_status(fido_dev_t* dev, int* touched, int) {
  const int after = scenario.devices[dev->index].touch_after;
  *touched = after >= 0 && ++dev->polls > after;
  return FIDO_OK;
}
int fido_dev_get_retry_count(fido_dev_t* dev, int* retries) {
  *retries = scenario.devices[dev->index].retries;
  return FIDO_OK;
}
int fido_dev_get_uv_retry_count(fido_dev_t* dev, int* retries) {
  *retries = scenario.devices[dev->index].uv_retries;
  return FIDO_OK;
}

fido_cbor_info_t* fido_cbor_info_new(void) { return new fido_cbor_info_t(); }
void fido_cbor_info_free(fido_cbor_info_t** info) {
  delete *info;
  *info = nullptr;
}
int fido_dev_get_cbor_info(fido_dev_t* dev, fido_cbor_info_t* info) {
  const fake::Device& device = scenario.devices[dev->index];
  info->extension_text = {"credProtect"};
  if (device.hmac_secret)
    info->extension_text.push_back("hmac-secret");
  info->option_text = {"rk", "up", "clientPin"};
  info->values[0] = info->values[1] = true;
  info->values[2] = device.pin;
  if (device.uv) {
    info->option_text.push_back("uv");
    info->values[3] = true;
  }
  for (auto& text : info->extension_text)
    info->extensions.push_back(&text[0]);
  for (auto& text : info->option_text)
    info->names.push_back(&text[0]);
  return FIDO_OK;
}
char** fido_cbor_info_extensions_ptr(const fido_cbor_info_t* info) {
  return const_cast<char**>(info->extensions.data());
}
size_t fido_cbor_info_extensions_len(const fido_cbor_info_t* info) {
  return info->extensions.size();
}
char** fido_cbor_info_options_name_ptr(const fido_cbor_info_t* info) {
  return const_cast<char**>(info->names.data());
}
const bool* fido_cbor_info_options_value_ptr(const fido_cbor_info_t* info) {
  return info->values;
}
size_t fido_cbor_info_options_len(const fido_cbor_info_t* info) {
  return info->names.size();
}

fido_assert_t* fido_assert_new(void) { return new fido_assert_t(); }
void fido_assert_free(fido_assert_t** assertion) {
  delete *assertion;
  *assertion = nullptr;
}
int fido_assert_set_rp(fido_assert_t*, const char* rp) {
  scenario.rp = rp;
  return FIDO_OK;
}
int fido_assert_set_clientdata_hash(fido_assert_t*, const unsigned char* data,
                                    size_t size) {
  scenario.client_data_hash.assign(data, data + size);
  return FIDO_OK;
}
int fido_assert_allow_cred(fido_assert_t*, const unsigned char*, size_t) {
  scenario.allowed++;
  return FIDO_OK;
}
int fido_assert_set_extensions(fido_assert_t*, int extensions) {
  scenario.extensions = extensions;
  return FIDO_OK;
}
int fido_assert_set_hmac_salt(fido_assert_t*, const unsigned char* data,
                              size_t size) {
  if (size != 32 && size != 64)
    return FIDO_ERR_INVALID_ARGUMENT;
  scenario.salt.assign(data, data + size);
  return FIDO_OK;
}
int fido_assert_set_uv(fido_assert_t*, fido_opt_t uv) {
  scenario.uv = uv;
  return FIDO_OK;
}
int fido_dev_get_assert(fido_dev_t*, fido_assert_t* assertion,
                        const char* pin) {
  scenario.pin_null = pin == nullptr;
  scenario.pin = pin ? pin : "";
  if (scenario.block_until_cancel) {
    std::unique_lock<std::mutex> lock(scenario.mutex);
    scenario.changed.wait_for(lock, std::chrono::seconds(5),
                              [] { return !scenario.cancelled.empty(); });
    return FIDO_ERR_KEEPALIVE_CANCEL;
  }
  if (scenario.assert_status != FIDO_OK)
    return scenario.assert_status;
  for (int i = 0; i < scenario.assertions; i++) {
    fido_assert_t::Statement statement;
    statement.id = Pattern(static_cast<unsigned char>(0xc0 + i), 16);
    statement.user_id = Pattern(static_cast<unsigned char>(0x10 + i), 8);
    statement.name = "Wallet " + std::to_string(i);
    statement.display_name = "Display " + std::to_string(i);
    // The second statement is long enough to need a two-byte CBOR length.
    Blob raw = Pattern(0x01, i == 0 ? 37 : 300);
    raw[32] = 0x05;
    statement.authdata = CborBytes(raw);
    statement.signature = Pattern(0x30, 70);
    if (scenario.hmac_output)
      statement.hmac = Pattern(static_cast<unsigned char>(0xa0 + i), 32);
    assertion->statements.push_back(statement);
  }
  return FIDO_OK;
}
size_t fido_assert_count(const fido_assert_t* assertion) {
  return assertion->statements.size();
}

#define FAKE_BLOB(name, field)                                                 \
  const unsigned char* fido_assert_##name##_ptr(const fido_assert_t* a,        \
                                                size_t i) {                    \
    return a->statements[i].field.data();                                      \
  }                                                                            \
  size_t fido_assert_##name##_len(const fido_assert_t* a, size_t i) {          \
    return a->statements[i].field.size();                                      \
  }
FAKE_BLOB(id, id)
FAKE_BLOB(user_id, user_id)
FAKE_BLOB(authdata, authdata)
FAKE_BLOB(sig, signature)
FAKE_BLOB(hmac_secret, hmac)
#undef FAKE_BLOB

const char* fido_assert_user_name(const fido_assert_t* a, size_t i) {
  return a->statements[i].name.c_str();
}
const char* fido_assert_user_display_name(const fido_assert_t* a, size_t i) {
  return a->statements[i].display_name.c_str();
}

}  // extern "C"
