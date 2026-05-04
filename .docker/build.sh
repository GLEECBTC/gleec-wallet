#!/bin/bash

DEFAULT_BUILD_TARGET="web"
DEFAULT_BUILD_MODE="release"

if [ "$#" -eq 0 ]; then
    BUILD_TARGET=$DEFAULT_BUILD_TARGET
    BUILD_MODE=$DEFAULT_BUILD_MODE
elif [ "$#" -eq 2 ]; then
    BUILD_TARGET=$1
    BUILD_MODE=$2
else
    echo "Usage: $0 [<build_target> <build_mode>]\nE.g. $0 web release"
    exit 1
fi

echo "Building with target: $BUILD_TARGET, mode: $BUILD_MODE"

# Ensure submodule is initialized and pinned to the recorded commit
if command -v git >/dev/null 2>&1; then
    echo "Ensuring SDK submodule is initialized and pinned..."
    # Keep local submodule config in sync with .gitmodules (e.g., update=checkout)
    git submodule sync --recursive || true
    # Clean submodules to discard local changes and untracked files
    git submodule foreach --recursive "git reset --hard && git clean -fdx" || true
    # Initialize and checkout recorded commits (pinned)
    git submodule update --init --recursive --checkout || true
    # Enable on-demand fetch for submodules (helps when switching branches)
    git config fetch.recurseSubmodules on-demand || true
fi

if [ "$(uname)" = "Darwin" ]; then
    PLATFORM_FLAG="--platform linux/amd64"
else
    PLATFORM_FLAG=""
fi

HOST_UID=$(id -u)
HOST_GID=$(id -g)

# Use fallback UID/GID if running as root to avoid conflicts
# in GitHub Actions where the UID/GID may be 0.
# android-sdk.dockerfile attempts to create a user with the 
# provided UID/GID, so 0 is not a valid choice (already exists).
if [ "$HOST_UID" = "0" ]; then
    HOST_UID=1000
    HOST_GID=1000
fi

docker build $PLATFORM_FLAG --build-arg BUILD_USER_ID=$HOST_UID -f .docker/android-sdk.dockerfile . -t komodo/android-sdk:35
docker build $PLATFORM_FLAG -f .docker/komodo-wallet-android.dockerfile . -t komodo/komodo-wallet

# Create the build directory ourselves to prevent it from being created by the Docker daemon (as root)
mkdir -p ./build

COMMIT_HASH=$(git rev-parse --short HEAD | cut -c1-7)
BUILD_DATE=$(date -u '+%Y-%m-%dT%H:%MZ')

# Only pass GITHUB_API_PUBLIC_READONLY_TOKEN as environment variable
ENV_ARGS=""
if [ -n "$GITHUB_API_PUBLIC_READONLY_TOKEN" ]; then
    ENV_ARGS="-e GITHUB_API_PUBLIC_READONLY_TOKEN=$GITHUB_API_PUBLIC_READONLY_TOKEN"
fi

# Build command logic
BUILD_COMMAND="flutter build $BUILD_TARGET --no-pub --$BUILD_MODE"
if [ "$BUILD_TARGET" = "web" ]; then
    BUILD_COMMAND="$BUILD_COMMAND --wasm"
fi
# Prepare build command with feedback service credentials
BUILD_CMD="$BUILD_COMMAND"
# Add commit hash and build date to build command
BUILD_CMD="$BUILD_CMD --dart-define=COMMIT_HASH=$COMMIT_HASH"
BUILD_CMD="$BUILD_CMD --dart-define=BUILD_DATE=$BUILD_DATE"

# Check and add the shared Trello board and list IDs if they are available
HAVE_TRELLO_IDS=false
if [ -n "$TRELLO_BOARD_ID" ] && [ -n "$TRELLO_LIST_ID" ]; then
  HAVE_TRELLO_IDS=true
  # Add these shared IDs to the build command
  BUILD_CMD="$BUILD_CMD --dart-define=TRELLO_BOARD_ID=$TRELLO_BOARD_ID"
  BUILD_CMD="$BUILD_CMD --dart-define=TRELLO_LIST_ID=$TRELLO_LIST_ID"
fi

# Add Trello feedback service variables if ALL required values are provided
if [ "$HAVE_TRELLO_IDS" = true ] && [ -n "$TRELLO_API_KEY" ] && [ -n "$TRELLO_TOKEN" ]; then
  echo "Adding Trello feedback service configuration"
  BUILD_CMD="$BUILD_CMD --dart-define=TRELLO_API_KEY=$TRELLO_API_KEY"
  BUILD_CMD="$BUILD_CMD --dart-define=TRELLO_TOKEN=$TRELLO_TOKEN"
else
  # If any Trello credential is missing, log a message but continue the build
  if [ -n "$TRELLO_API_KEY" ] || [ -n "$TRELLO_TOKEN" ] || [ -n "$TRELLO_BOARD_ID" ] || [ -n "$TRELLO_LIST_ID" ]; then
    echo "Warning: Incomplete Trello credentials provided. All Trello credentials must be present to include them in the build."
  fi
fi

# Add Cloudflare feedback service variables if ALL required values are provided
# Note: Cloudflare also needs the Trello board and list IDs to be available
if [ "$HAVE_TRELLO_IDS" = true ] && [ -n "$FEEDBACK_API_KEY" ] && [ -n "$FEEDBACK_PRODUCTION_URL" ]; then
  echo "Adding Cloudflare feedback service configuration"
  BUILD_CMD="$BUILD_CMD --dart-define=FEEDBACK_API_KEY=$FEEDBACK_API_KEY"
  BUILD_CMD="$BUILD_CMD --dart-define=FEEDBACK_PRODUCTION_URL=$FEEDBACK_PRODUCTION_URL"
else
  # If any Cloudflare credential is missing, log a message but continue the build
  if [ -n "$FEEDBACK_API_KEY" ] || [ -n "$FEEDBACK_PRODUCTION_URL" ] ||
     ([ -n "$TRELLO_BOARD_ID" ] || [ -n "$TRELLO_LIST_ID" ]); then
    echo "Warning: Incomplete Cloudflare feedback credentials provided. All Cloudflare credentials and Trello board/list IDs must be present to include them in the build."
  fi
fi
# Add Matomo tracking variables if ALL required values are provided
# Matomo configuration only used when both are non-empty
if [ -n "$MATOMO_URL" ] && [ -n "$MATOMO_SITE_ID" ]; then
  echo "Adding Matomo tracking configuration"
  BUILD_CMD="$BUILD_CMD --dart-define=MATOMO_URL=$MATOMO_URL"
  BUILD_CMD="$BUILD_CMD --dart-define=MATOMO_SITE_ID=$MATOMO_SITE_ID"
else
  echo "Warning: Missing Matomo parameters. Both MATOMO_URL and MATOMO_SITE_ID must be provided."
fi
# Add web-specific build arguments if the target is web
if [ "$BUILD_TARGET" = "web" ]; then
    echo "Adding web-specific build arguments: --no-web-resources-cdn"
    BUILD_CMD="$BUILD_CMD --no-web-resources-cdn"
fi
# Use the provided arguments for flutter build
# Build a second time if needed, as asset downloads will require a rebuild on the first attempt
docker run $PLATFORM_FLAG --rm -v ./build:/app/build \
  -v $(pwd):/app \
  -u "$HOST_UID:$HOST_GID" \
  $ENV_ARGS \
  komodo/komodo-wallet:latest sh -c \
  "sudo chown -R komodo:komodo /app/build; flutter pub get --enforce-lockfile; $BUILD_COMMAND || true; flutter build $BUILD_TARGET --config-only; $BUILD_CMD"
