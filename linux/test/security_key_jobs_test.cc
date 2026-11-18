// Drives the bridge's libfido2 work against fake_fido2.cc, loaded through
// the same dlopen path as the real library. Run by
// check_security_key_bridge.sh.

#include <dlfcn.h>
#include <sys/stat.h>
#include <unistd.h>

#include <chrono>
#include <cstdio>
#include <cstring>
#include <fstream>
#include <memory>
#include <thread>

#include "../security_key_channel_jobs.h"
#include "fake_fido2.h"

namespace sk = security_key;

namespace {

int failures = 0;

#define CHECK(condition)                                                       \
  do {                                                                         \
    if (!(condition)) {                                                        \
      std::fprintf(stderr, "%s:%d: CHECK failed: %s\n", __FILE__, __LINE__,    \
                   #condition);                                                \
      failures++;                                                              \
    }                                                                          \
  } while (0)

fake::Scenario* scenario = nullptr;

std::string Key(int n) {
  return GLEEC_SECURITY_KEY_PATH_PREFIX + std::to_string(n);
}

void Plug(int n, mode_t mode = 0600) {
  std::ofstream(Key(n)).put('\0');
  chmod(Key(n).c_str(), mode);
}

fake::Device Device(int n) {
  fake::Device device;
  device.path = Key(n);
  device.maker = "Maker";
  device.product = "Maker Key " + std::to_string(n);
  return device;
}

std::shared_ptr<sk::Job> AssertJob(int key, const char* pin) {
  auto job = std::make_shared<sk::Job>();
  job->kind = sk::Kind::kAssert;
  job->paths = {Key(key)};
  job->rp_id = "dex.gleec.com";
  job->client_data_hash.assign(32, 0x11);
  job->salt.assign(32, 0x22);
  job->allowed = {sk::Bytes(16, 0xc0)};
  if (pin) {
    job->pin.assign(pin, pin + std::strlen(pin));
    job->pin.push_back(0);
  }
  return job;
}

void Helpers() {
  CHECK(sk::ValidRpId("dex.gleec.com"));
  CHECK(!sk::ValidRpId("dex.gleec.com\""));
  CHECK(!sk::ValidRpId("DEX.gleec.com"));
  CHECK(!sk::ValidRpId(""));
  CHECK(sk::ValidPath(Key(3)));
  CHECK(!sk::ValidPath(Key(3) + "/../x"));
  CHECK(!sk::ValidPath("/etc/passwd"));

  sk::Bytes raw;
  std::vector<unsigned char> one(39, 0x01);
  one[0] = 0x58;
  one[1] = 37;
  CHECK(sk::RawAuthenticatorData(one.data(), one.size(), raw));
  CHECK(raw.size() == 37);
  std::vector<unsigned char> two(303, 0x01);
  two[0] = 0x59;
  two[1] = 0x01;
  two[2] = 0x2c;
  CHECK(sk::RawAuthenticatorData(two.data(), two.size(), raw));
  CHECK(raw.size() == 300);
  one[1] = 36;  // Length disagrees with the buffer.
  CHECK(!sk::RawAuthenticatorData(one.data(), one.size(), raw));
  std::vector<unsigned char> text = {0x78, 37};  // A text string.
  text.resize(39, 'a');
  CHECK(!sk::RawAuthenticatorData(text.data(), text.size(), raw));
  std::vector<unsigned char> short_form = {0x41, 0x00};
  CHECK(!sk::RawAuthenticatorData(short_form.data(), short_form.size(), raw));

  CHECK(std::strcmp(sk::FailureCode(FIDO_ERR_PIN_INVALID, true),
                    "pinInvalid") == 0);
  CHECK(std::strcmp(sk::FailureCode(FIDO_ERR_PIN_AUTH_BLOCKED, true),
                    "pinAuthBlocked") == 0);
  CHECK(std::strcmp(sk::FailureCode(FIDO_ERR_PIN_BLOCKED, true),
                    "pinBlocked") == 0);
  CHECK(std::strcmp(sk::FailureCode(FIDO_ERR_PIN_REQUIRED, false),
                    "pinRequired") == 0);
  CHECK(std::strcmp(sk::FailureCode(FIDO_ERR_PIN_REQUIRED, true),
                    "unavailable") == 0);
  CHECK(std::strcmp(sk::FailureCode(FIDO_ERR_NO_CREDENTIALS, true),
                    "noCredential") == 0);
  CHECK(std::strcmp(sk::FailureCode(FIDO_ERR_ACTION_TIMEOUT, true),
                    "timeout") == 0);
  CHECK(std::strcmp(sk::FailureCode(FIDO_ERR_RX, true), "deviceGone") == 0);
  CHECK(std::strcmp(sk::FailureCode(FIDO_ERR_KEEPALIVE_CANCEL, true),
                    "canceled") == 0);
}

void Devices() {
  scenario->Reset();
  fake::Device pin_key = Device(0);
  pin_key.retries = 5;
  fake::Device u2f = Device(1);
  u2f.fido2 = false;
  fake::Device bio = Device(2);
  bio.pin = false;
  bio.uv = true;
  bio.uv_retries = 3;
  bio.hmac_secret = false;
  scenario->devices = {pin_key, u2f, bio};
  Plug(0);
  Plug(1);
  Plug(2);
  sk::Job job;
  sk::Outcome outcome = sk::Run(*sk::Fido::Get(), job);
  CHECK(!outcome.error);
  CHECK(outcome.devices.size() == 3);
  if (outcome.devices.size() != 3)
    return;
  CHECK(std::strcmp(outcome.devices[0].state, "ready") == 0);
  CHECK(outcome.devices[0].hmac_secret && outcome.devices[0].pin);
  CHECK(!outcome.devices[0].uv && outcome.devices[0].pin_retries == 5);
  CHECK(outcome.devices[0].product == "Maker Key 0");
  CHECK(std::strcmp(outcome.devices[1].state, "ready") == 0);
  CHECK(!outcome.devices[1].hmac_secret);
  CHECK(outcome.devices[2].uv && outcome.devices[2].uv_retries == 3);
  CHECK(!outcome.devices[2].pin && !outcome.devices[2].hmac_secret);
  CHECK(scenario->opened == scenario->closed);

  if (geteuid() != 0) {
    chmod(Key(1).c_str(), 0);
    outcome = sk::Run(*sk::Fido::Get(), job);
    CHECK(outcome.devices.size() == 3 &&
          std::strcmp(outcome.devices[1].state, "noAccess") == 0);
  } else {
    std::printf("skipped: noAccess needs a non-root user\n");
  }
}

void Selection() {
  scenario->Reset();
  fake::Device first = Device(0), second = Device(1);
  second.touch_after = 3;
  scenario->devices = {first, second};
  Plug(0);
  Plug(1);
  sk::Job job;
  job.kind = sk::Kind::kSelect;
  job.paths = {Key(0), Key(1)};
  job.timeout_ms = 2000;
  sk::Outcome outcome = sk::Run(*sk::Fido::Get(), job);
  CHECK(!outcome.error && outcome.path == Key(1));
  // The key not chosen stops blinking.
  CHECK(scenario->cancelled.size() == 1 && scenario->cancelled[0] == Key(0));
  CHECK(scenario->opened == scenario->closed);

  scenario->devices[1].touch_after = -1;
  job.timeout_ms = 200;
  outcome = sk::Run(*sk::Fido::Get(), job);
  CHECK(outcome.error && std::strcmp(outcome.error, "timeout") == 0);

  sk::Job removed;
  removed.kind = sk::Kind::kSelect;
  removed.paths = {Key(0)};
  removed.timeout_ms = 2000;
  unlink(Key(0).c_str());
  outcome = sk::Run(*sk::Fido::Get(), removed);
  CHECK(outcome.error && std::strcmp(outcome.error, "deviceGone") == 0);

  Plug(0);
  sk::Job interrupted;
  interrupted.kind = sk::Kind::kSelect;
  interrupted.paths = {Key(0), Key(1)};
  interrupted.timeout_ms = 5000;
  std::thread stop([&interrupted] {
    std::this_thread::sleep_for(std::chrono::milliseconds(100));
    sk::Interrupt(interrupted);
  });
  const auto started = std::chrono::steady_clock::now();
  outcome = sk::Run(*sk::Fido::Get(), interrupted);
  stop.join();
  CHECK(outcome.error && std::strcmp(outcome.error, "canceled") == 0);
  CHECK(std::chrono::steady_clock::now() - started < std::chrono::seconds(2));
}

void Assertions() {
  scenario->Reset();
  fake::Device key = Device(0);
  key.retries = 4;
  scenario->devices = {key};
  Plug(0);

  auto job = AssertJob(0, "1234");
  sk::Outcome outcome = sk::Run(*sk::Fido::Get(), *job);
  CHECK(!outcome.error && outcome.candidates.size() == 1);
  CHECK(scenario->rp == "dex.gleec.com");
  CHECK(scenario->client_data_hash == sk::Bytes(32, 0x11));
  CHECK(scenario->salt == sk::Bytes(32, 0x22));
  CHECK(scenario->allowed == 1);
  CHECK(scenario->extensions == FIDO_EXT_HMAC_SECRET);
  CHECK(scenario->uv == FIDO_OPT_TRUE);
  CHECK(!scenario->pin_null && scenario->pin == "1234");
  CHECK(job->pin.empty());
  CHECK(scenario->opened == scenario->closed);
  if (!outcome.candidates.empty()) {
    const sk::Candidate& candidate = outcome.candidates[0];
    CHECK(candidate.authenticator_data.size() == 37);
    CHECK(candidate.authenticator_data[32] == 0x05);
    CHECK(candidate.prf.size() == 32 && candidate.prf[0] == 0xa0);
    CHECK(candidate.credential_id.size() == 16);
    CHECK(candidate.user_handle.size() == 8);
    CHECK(candidate.user_name == "Wallet 0");
    CHECK(candidate.signature.size() == 70);
  }
  outcome.WipeSecrets();
  CHECK(outcome.candidates.empty() || outcome.candidates[0].prf.empty());

  scenario->assertions = 2;
  scenario->allowed = 0;
  job = AssertJob(0, nullptr);
  job->allowed.clear();
  outcome = sk::Run(*sk::Fido::Get(), *job);
  CHECK(!outcome.error && outcome.candidates.size() == 2);
  CHECK(scenario->pin_null && scenario->allowed == 0);
  if (outcome.candidates.size() == 2) {
    CHECK(outcome.candidates[1].authenticator_data.size() == 300);
    CHECK(outcome.candidates[1].display_name == "Display 1");
  }

  scenario->assertions = 1;
  scenario->hmac_output = false;
  outcome = sk::Run(*sk::Fido::Get(), *AssertJob(0, "1234"));
  CHECK(outcome.error && std::strcmp(outcome.error, "prfUnavailable") == 0);
  CHECK(outcome.candidates.empty());

  scenario->hmac_output = true;
  scenario->assert_status = FIDO_ERR_PIN_INVALID;
  outcome = sk::Run(*sk::Fido::Get(), *AssertJob(0, "0000"));
  CHECK(outcome.error && std::strcmp(outcome.error, "pinInvalid") == 0);
  CHECK(outcome.retries == 4);

  scenario->assert_status = FIDO_ERR_PIN_REQUIRED;
  outcome = sk::Run(*sk::Fido::Get(), *AssertJob(0, nullptr));
  CHECK(outcome.error && std::strcmp(outcome.error, "pinRequired") == 0);

  scenario->assert_status = FIDO_OK;
  scenario->block_until_cancel = true;
  auto blocked = AssertJob(0, "1234");
  std::thread stop([blocked] {
    std::this_thread::sleep_for(std::chrono::milliseconds(100));
    sk::Interrupt(*blocked);
  });
  outcome = sk::Run(*sk::Fido::Get(), *blocked);
  stop.join();
  CHECK(outcome.error && std::strcmp(outcome.error, "canceled") == 0);
  CHECK(scenario->cancelled.size() == 1);
  CHECK(blocked->pin.empty());

  scenario->block_until_cancel = false;
  unlink(Key(0).c_str());
  outcome = sk::Run(*sk::Fido::Get(), *AssertJob(0, "1234"));
  CHECK(outcome.error && std::strcmp(outcome.error, "deviceGone") == 0);
}

}  // namespace

int main() {
  CHECK(sk::Fido::Get() != nullptr);
  void* library = dlopen("libfido2.so.1", RTLD_NOW | RTLD_NOLOAD);
  auto* get = library ? reinterpret_cast<fake::Scenario* (*)()>(
                            dlsym(library, "fake_scenario"))
                      : nullptr;
  if (!get) {
    std::fprintf(stderr, "the fake libfido2 was not the one loaded\n");
    return 1;
  }
  scenario = get();
  CHECK(scenario->log_handler_set);
  Helpers();
  Devices();
  Selection();
  Assertions();
  if (failures) {
    std::printf("%d check(s) failed\n", failures);
    return 1;
  }
  std::printf("all checks passed\n");
  return 0;
}
