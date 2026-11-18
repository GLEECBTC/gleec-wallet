#include "security_key_channel.h"

#include <cstdint>
#include <cstring>
#include <string>

namespace {

constexpr char kChannelName[] = "gleec.wallet/security_key";
constexpr char kMessage[] = "Security key request could not be completed";

}  // namespace

#ifdef GLEEC_SECURITY_KEY_STUB

// Built without libfido2 headers: the option is never offered.
struct _SecurityKeyChannel {
  FlMethodChannel* channel = nullptr;
};

static void HandleCall(FlMethodChannel*, FlMethodCall* call, gpointer) {
  if (std::strcmp(fl_method_call_get_name(call), "support") == 0) {
    g_autoptr(FlValue) result = fl_value_new_map();
    fl_value_set_string_take(result, "available", fl_value_new_bool(FALSE));
    fl_method_call_respond_success(call, result, nullptr);
  } else if (std::strcmp(fl_method_call_get_name(call), "cancel") == 0) {
    fl_method_call_respond_success(call, nullptr, nullptr);
  } else {
    fl_method_call_respond_error(call, "unavailable", kMessage, nullptr,
                                 nullptr);
  }
}

SecurityKeyChannel* security_key_channel_new(FlBinaryMessenger* messenger) {
  auto* self = new SecurityKeyChannel();
  g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();
  self->channel = fl_method_channel_new(messenger, kChannelName,
                                        FL_METHOD_CODEC(codec));
  fl_method_channel_set_method_call_handler(self->channel, HandleCall, self,
                                            nullptr);
  return self;
}

void security_key_channel_free(SecurityKeyChannel* self) {
  fl_method_channel_set_method_call_handler(self->channel, nullptr, nullptr,
                                            nullptr);
  g_object_unref(self->channel);
  delete self;
}

#else  // GLEEC_SECURITY_KEY_STUB

#include <deque>
#include <memory>
#include <mutex>
#include <thread>
#include <utility>

#include "security_key_channel_jobs.h"

struct _SecurityKeyChannel {
  struct Pending {
    uint64_t id = 0;
    FlMethodCall* call = nullptr;
    std::shared_ptr<security_key::Job> job;
  };

  FlMethodChannel* channel = nullptr;
  std::shared_ptr<security_key::Delivery> delivery =
      std::make_shared<security_key::Delivery>();
  std::unique_ptr<Pending> pending;
  uint64_t next_id = 0;
  // A cancelled request's worker may still hold the key, so a new request
  // waits for its outcome.
  uint64_t running = 0;

  void Handle(FlMethodCall* call);
  void Begin(FlMethodCall* call, std::shared_ptr<security_key::Job> job);
  void Cancel();
  void Deliver(std::deque<security_key::Outcome>& outcomes);
};

namespace {

using security_key::Bytes;
using security_key::Job;
using security_key::Outcome;

FlValue* Field(FlValue* args, const char* name, FlValueType type) {
  if (!args || fl_value_get_type(args) != FL_VALUE_TYPE_MAP)
    return nullptr;
  FlValue* value = fl_value_lookup_string(args, name);
  return value && fl_value_get_type(value) == type ? value : nullptr;
}

bool ReadBytes(FlValue* value, size_t min, size_t max, Bytes& out) {
  if (!value || fl_value_get_type(value) != FL_VALUE_TYPE_UINT8_LIST)
    return false;
  const size_t size = fl_value_get_length(value);
  if (size < min || size > max)
    return false;
  const uint8_t* data = fl_value_get_uint8_list(value);
  out.assign(data, data + size);
  return true;
}

bool ReadPath(FlValue* value, std::string& out) {
  if (!value || fl_value_get_type(value) != FL_VALUE_TYPE_STRING)
    return false;
  out = fl_value_get_string(value);
  return security_key::ValidPath(out);
}

int ReadTimeout(FlValue* args) {
  FlValue* value = Field(args, "timeoutMs", FL_VALUE_TYPE_INT);
  const int64_t millis = value ? fl_value_get_int(value) : 0;
  return millis > 0 && millis <= 300000 ? static_cast<int>(millis) : 120000;
}

std::shared_ptr<Job> ParseSelect(FlValue* args) {
  FlValue* paths = Field(args, "paths", FL_VALUE_TYPE_LIST);
  if (!paths || fl_value_get_length(paths) < 1 ||
      fl_value_get_length(paths) > security_key::kMaxDevices)
    return nullptr;
  auto job = std::make_shared<Job>();
  job->kind = security_key::Kind::kSelect;
  for (size_t i = 0; i < fl_value_get_length(paths); i++) {
    std::string path;
    if (!ReadPath(fl_value_get_list_value(paths, i), path))
      return nullptr;
    job->paths.push_back(path);
  }
  job->timeout_ms = ReadTimeout(args);
  return job;
}

std::shared_ptr<Job> ParseAssertion(FlValue* args) {
  auto job = std::make_shared<Job>();
  job->kind = security_key::Kind::kAssert;
  std::string path;
  FlValue* rp_id = Field(args, "rpId", FL_VALUE_TYPE_STRING);
  FlValue* allowed = Field(args, "allowCredentials", FL_VALUE_TYPE_LIST);
  if (!ReadPath(fl_value_lookup_string(args, "path"), path) || !rp_id ||
      !security_key::ValidRpId(fl_value_get_string(rp_id)) ||
      !ReadBytes(fl_value_lookup_string(args, "clientDataHash"), 32, 32,
                 job->client_data_hash) ||
      !ReadBytes(fl_value_lookup_string(args, "salt"), 32, 32, job->salt) ||
      !allowed || fl_value_get_length(allowed) > 16)
    return nullptr;
  job->paths.push_back(path);
  job->rp_id = fl_value_get_string(rp_id);
  for (size_t i = 0; i < fl_value_get_length(allowed); i++) {
    Bytes id;
    if (!ReadBytes(fl_value_get_list_value(allowed, i), 1, 1023, id))
      return nullptr;
    job->allowed.push_back(std::move(id));
  }
  FlValue* pin = fl_value_lookup_string(args, "pin");
  if (pin && fl_value_get_type(pin) != FL_VALUE_TYPE_NULL) {
    // CTAP's bounds; libfido2 takes a NUL-terminated string. Room for the
    // terminator up front: a reallocation would free a copy unwiped.
    job->pin.reserve(64);
    if (!ReadBytes(pin, 4, 63, job->pin) ||
        std::memchr(job->pin.data(), 0, job->pin.size())) {
      security_key::Wipe(job->pin);
      return nullptr;
    }
    job->pin.push_back(0);
  }
  job->timeout_ms = ReadTimeout(args);
  return job;
}

FlValue* BytesValue(const Bytes& bytes) {
  return fl_value_new_uint8_list(bytes.data(), bytes.size());
}

FlValue* TextValue(const std::string& text) {
  return text.empty() ? fl_value_new_null()
                      : fl_value_new_string(text.c_str());
}

FlValue* DevicesValue(const Outcome& outcome) {
  FlValue* list = fl_value_new_list();
  for (const auto& device : outcome.devices) {
    FlValue* entry = fl_value_new_map();
    fl_value_set_string_take(entry, "path",
                             fl_value_new_string(device.path.c_str()));
    fl_value_set_string_take(entry, "product", TextValue(device.product));
    fl_value_set_string_take(entry, "state",
                             fl_value_new_string(device.state));
    fl_value_set_string_take(entry, "hmacSecret",
                             fl_value_new_bool(device.hmac_secret));
    fl_value_set_string_take(entry, "pin", fl_value_new_bool(device.pin));
    fl_value_set_string_take(entry, "uv", fl_value_new_bool(device.uv));
    fl_value_set_string_take(entry, "pinRetries",
                             fl_value_new_int(device.pin_retries));
    fl_value_set_string_take(entry, "uvRetries",
                             fl_value_new_int(device.uv_retries));
    fl_value_append_take(list, entry);
  }
  return list;
}

FlValue* AssertionsValue(const Outcome& outcome) {
  FlValue* list = fl_value_new_list();
  for (const auto& candidate : outcome.candidates) {
    FlValue* entry = fl_value_new_map();
    fl_value_set_string_take(entry, "credentialId",
                             BytesValue(candidate.credential_id));
    fl_value_set_string_take(entry, "userHandle",
                             candidate.user_handle.empty()
                                 ? fl_value_new_null()
                                 : BytesValue(candidate.user_handle));
    fl_value_set_string_take(entry, "userName",
                             TextValue(candidate.user_name));
    fl_value_set_string_take(entry, "userDisplayName",
                             TextValue(candidate.display_name));
    fl_value_set_string_take(entry, "authenticatorData",
                             BytesValue(candidate.authenticator_data));
    fl_value_set_string_take(entry, "signature",
                             BytesValue(candidate.signature));
    fl_value_set_string_take(entry, "prf",
                             candidate.prf.empty()
                                 ? fl_value_new_null()
                                 : BytesValue(candidate.prf));
    fl_value_append_take(list, entry);
  }
  return list;
}

void Respond(FlMethodCall* call, Job& job, const Outcome& outcome) {
  if (outcome.error) {
    g_autoptr(FlValue) details = nullptr;
    if (outcome.retries >= 0) {
      details = fl_value_new_map();
      fl_value_set_string_take(details, "retries",
                               fl_value_new_int(outcome.retries));
    }
    fl_method_call_respond_error(call, outcome.error, kMessage, details,
                                 nullptr);
    return;
  }
  g_autoptr(FlValue) result = fl_value_new_map();
  switch (job.kind) {
  case security_key::Kind::kDevices:
    fl_value_set_string_take(result, "devices", DevicesValue(outcome));
    break;
  case security_key::Kind::kSelect:
    fl_value_set_string_take(result, "path",
                             fl_value_new_string(outcome.path.c_str()));
    break;
  case security_key::Kind::kAssert:
    fl_value_set_string_take(result, "assertions", AssertionsValue(outcome));
    break;
  }
  fl_method_call_respond_success(call, result, nullptr);
}

gboolean Drain(gpointer data) {
  auto* weak = static_cast<std::weak_ptr<security_key::Delivery>*>(data);
  if (auto delivery = weak->lock()) {
    std::deque<Outcome> ready;
    SecurityKeyChannel* owner;
    {
      std::lock_guard<std::mutex> lock(delivery->mutex);
      ready.swap(delivery->outcomes);
      owner = delivery->owner;
    }
    if (owner)
      owner->Deliver(ready);
    for (auto& outcome : ready)
      outcome.WipeSecrets();
  }
  delete weak;
  return G_SOURCE_REMOVE;
}

void HandleCall(FlMethodChannel*, FlMethodCall* call, gpointer user_data) {
  static_cast<SecurityKeyChannel*>(user_data)->Handle(call);
}

}  // namespace

void _SecurityKeyChannel::Handle(FlMethodCall* call) {
  const gchar* name = fl_method_call_get_name(call);
  FlValue* args = fl_method_call_get_args(call);
  if (std::strcmp(name, "support") == 0) {
    g_autoptr(FlValue) result = fl_value_new_map();
    fl_value_set_string_take(
        result, "available",
        fl_value_new_bool(security_key::Fido::Get() != nullptr));
    fl_method_call_respond_success(call, result, nullptr);
  } else if (std::strcmp(name, "cancel") == 0) {
    Cancel();
    fl_method_call_respond_success(call, nullptr, nullptr);
  } else if (std::strcmp(name, "devices") == 0) {
    auto job = std::make_shared<Job>();
    job->kind = security_key::Kind::kDevices;
    Begin(call, job);
  } else if (std::strcmp(name, "select") == 0) {
    Begin(call, ParseSelect(args));
  } else if (std::strcmp(name, "getAssertion") == 0) {
    Begin(call, ParseAssertion(args));
  } else {
    fl_method_call_respond_not_implemented(call, nullptr);
  }
}

void _SecurityKeyChannel::Begin(FlMethodCall* call, std::shared_ptr<Job> job) {
  const security_key::Fido* api = security_key::Fido::Get();
  if (!api) {
    if (job)
      security_key::Wipe(job->pin);
    fl_method_call_respond_error(call, "unavailable", kMessage, nullptr,
                                 nullptr);
    return;
  }
  if (!job) {
    fl_method_call_respond_error(call, "invalidResponse", kMessage, nullptr,
                                 nullptr);
    return;
  }
  if (pending || running) {
    security_key::Wipe(job->pin);
    fl_method_call_respond_error(call, "busy", kMessage, nullptr, nullptr);
    return;
  }
  job->id = ++next_id;
  pending = std::make_unique<Pending>();
  pending->id = job->id;
  pending->call = FL_METHOD_CALL(g_object_ref(call));
  pending->job = job;
  running = job->id;
  std::weak_ptr<security_key::Delivery> weak = delivery;
  std::thread([api, job, weak]() {
    Outcome outcome = security_key::Run(*api, *job);
    outcome.id = job->id;
    if (auto target = weak.lock()) {
      std::lock_guard<std::mutex> lock(target->mutex);
      if (target->owner) {
        target->outcomes.push_back(std::move(outcome));
        g_idle_add(Drain, new std::weak_ptr<security_key::Delivery>(target));
        return;
      }
    }
    outcome.WipeSecrets();
  }).detach();
}

// Answers the waiting call at once. The worker's eventual outcome no longer
// matches a pending request and is wiped unread.
void _SecurityKeyChannel::Cancel() {
  if (!pending)
    return;
  security_key::Interrupt(*pending->job);
  fl_method_call_respond_error(pending->call, "canceled", kMessage, nullptr,
                               nullptr);
  g_object_unref(pending->call);
  pending.reset();
}

void _SecurityKeyChannel::Deliver(std::deque<Outcome>& outcomes) {
  for (auto& outcome : outcomes) {
    if (running == outcome.id)
      running = 0;
    if (pending && pending->id == outcome.id) {
      std::unique_ptr<Pending> done = std::move(pending);
      Respond(done->call, *done->job, outcome);
      g_object_unref(done->call);
    }
  }
}

SecurityKeyChannel* security_key_channel_new(FlBinaryMessenger* messenger) {
  auto* self = new SecurityKeyChannel();
  self->delivery->owner = self;
  g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();
  self->channel = fl_method_channel_new(messenger, kChannelName,
                                        FL_METHOD_CODEC(codec));
  fl_method_channel_set_method_call_handler(self->channel, HandleCall, self,
                                            nullptr);
  return self;
}

void security_key_channel_free(SecurityKeyChannel* self) {
  fl_method_channel_set_method_call_handler(self->channel, nullptr, nullptr,
                                            nullptr);
  self->Cancel();
  {
    std::lock_guard<std::mutex> lock(self->delivery->mutex);
    self->delivery->owner = nullptr;
    for (auto& outcome : self->delivery->outcomes)
      outcome.WipeSecrets();
    self->delivery->outcomes.clear();
  }
  g_object_unref(self->channel);
  delete self;
}

#endif  // GLEEC_SECURITY_KEY_STUB
