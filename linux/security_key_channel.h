#ifndef RUNNER_SECURITY_KEY_CHANNEL_H_
#define RUNNER_SECURITY_KEY_CHANNEL_H_

#include <flutter_linux/flutter_linux.h>

// User-verified FIDO2 assertions with hmac-secret through libfido2, loaded
// on first use. It stores nothing and never sees the wallet credential.
typedef struct _SecurityKeyChannel SecurityKeyChannel;

SecurityKeyChannel* security_key_channel_new(FlBinaryMessenger* messenger);
void security_key_channel_free(SecurityKeyChannel* channel);

#endif  // RUNNER_SECURITY_KEY_CHANNEL_H_
