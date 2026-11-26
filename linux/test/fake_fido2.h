#ifndef RUNNER_TEST_FAKE_FIDO2_H_
#define RUNNER_TEST_FAKE_FIDO2_H_

#include <fido.h>

#include <condition_variable>
#include <mutex>
#include <string>
#include <vector>

// A scripted stand-in for libfido2.so.1. The bridge reaches it through the
// same dlopen path as the real library; the harness steers it through
// fake_scenario().
namespace fake {

struct Device {
  std::string path, maker, product;
  bool fido2 = true, hmac_secret = true, pin = true, uv = false;
  int retries = 8, uv_retries = -1;
  int touch_after = -1;  // Polls before this key reports a touch.
};

struct Scenario {
  std::vector<Device> devices;
  int assert_status = FIDO_OK;
  int assertions = 1;
  bool hmac_output = true;
  bool block_until_cancel = false;

  bool log_handler_set = false;
  std::string rp, pin;
  bool pin_null = true;
  std::vector<unsigned char> client_data_hash, salt;
  size_t allowed = 0;
  int extensions = 0;
  fido_opt_t uv = FIDO_OPT_OMIT;
  std::vector<std::string> cancelled;
  int opened = 0, closed = 0;

  std::mutex mutex;
  std::condition_variable changed;

  void Reset() {
    devices.clear();
    assert_status = FIDO_OK;
    assertions = 1;
    hmac_output = true;
    block_until_cancel = false;
    rp.clear();
    pin.clear();
    pin_null = true;
    client_data_hash.clear();
    salt.clear();
    allowed = 0;
    extensions = 0;
    uv = FIDO_OPT_OMIT;
    cancelled.clear();
    opened = closed = 0;
  }
};

}  // namespace fake

extern "C" fake::Scenario* fake_scenario();

#endif  // RUNNER_TEST_FAKE_FIDO2_H_
