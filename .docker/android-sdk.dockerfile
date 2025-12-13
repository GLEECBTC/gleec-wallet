FROM docker.io/ubuntu:22.04

# Credit to Cirrus Labs for the original Dockerfile
# LABEL org.opencontainers.image.source=https://github.com/cirruslabs/docker-images-android

ENV USER="komodo"
ARG BUILD_USER_ID=1000
ENV USER_ID=${BUILD_USER_ID}

RUN apt update && apt install -y sudo && \
    useradd -u $USER_ID -m $USER && \ 
    usermod -aG sudo $USER && \ 
    echo "$USER ALL=(ALL) NOPASSWD: ALL" >> /etc/sudoers

USER $USER

ENV ANDROID_HOME=/opt/android-sdk-linux \
    LANG=en_US.UTF-8 \
    LC_ALL=en_US.UTF-8 \
    LANGUAGE=en_US:en

ENV ANDROID_SDK_ROOT=$ANDROID_HOME \
    PATH=${PATH}:${ANDROID_HOME}/cmdline-tools/latest/bin:${ANDROID_HOME}/platform-tools:${ANDROID_HOME}/emulator

# comes from https://developer.android.com/studio/#command-tools
ENV ANDROID_SDK_TOOLS_VERSION=11076708

# https://developer.android.com/studio/releases/build-tools
ENV ANDROID_PLATFORM_VERSION=36
ENV ANDROID_BUILD_TOOLS_VERSION=35.0.1

# https://developer.android.com/ndk/downloads
ENV ANDROID_NDK_VERSION=27.3.13750724

RUN set -o xtrace \
    && sudo chown -R $USER:$USER /opt \
    && cd /opt \
    && sudo apt-get update \
    && sudo apt-get install -y jq openjdk-17-jdk nodejs npm \
    wget zip unzip git openssh-client curl bc software-properties-common build-essential \
    ruby-full ruby-bundler libstdc++6 libpulse0 libglu1-mesa locales lcov libsqlite3-dev --no-install-recommends \
    # For Linux build
    xz-utils acl \
    clang cmake git \
    ninja-build pkg-config \
    libgtk-3-dev liblzma-dev \
    libstdc++-12-dev libsecret-1-dev \
    # for x86 emulators
    libxtst6 libnss3-dev libnspr4 libxss1 libatk-bridge2.0-0 libgtk-3-0 libgdk-pixbuf2.0-0 \
    && sudo rm -rf /var/lib/apt/lists/* \
    && sh -c 'echo "en_US.UTF-8 UTF-8" | sudo tee -a /etc/locale.gen' \
    && sudo locale-gen \
    && sudo update-locale LANG=en_US.UTF-8 \
    && wget -q https://dl.google.com/android/repository/commandlinetools-linux-${ANDROID_SDK_TOOLS_VERSION}_latest.zip -O android-sdk-tools.zip \
    && mkdir -p ${ANDROID_HOME}/cmdline-tools/ \
    && unzip -q android-sdk-tools.zip -d ${ANDROID_HOME}/cmdline-tools/ \
    && mv ${ANDROID_HOME}/cmdline-tools/cmdline-tools ${ANDROID_HOME}/cmdline-tools/latest \
    && rm android-sdk-tools.zip \
    && yes | sdkmanager --licenses \
    && sdkmanager platform-tools \
    && sudo mkdir -p /root/.android \
    && sudo chown -R $USER:$USER /root \
    && touch /root/.android/repositories.cfg \
    && git config --global user.email "info@gleec.com" \
    && git config --global user.name "Gleec" \
    && yes | sdkmanager \
    "platforms;android-$ANDROID_PLATFORM_VERSION" \
    "build-tools;$ANDROID_BUILD_TOOLS_VERSION" \
    && yes | sdkmanager "ndk;$ANDROID_NDK_VERSION" \
    && sudo chown -R $USER:$USER $ANDROID_HOME \
    && sudo setfacl -R -m u:$USER:rwX -m d:u:$USER:rwX /usr/local