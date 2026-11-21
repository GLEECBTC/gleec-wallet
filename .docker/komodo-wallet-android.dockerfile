FROM komodo/android-sdk:36 AS final

ENV HOME="/home/komodo"
ENV USER="komodo"
ENV PATH=$PATH:$HOME/flutter/bin

USER $USER

WORKDIR /app

# Share the exact app/CI pin; a new .fvmrc invalidates this image layer.
COPY --chown=komodo:komodo .fvmrc /tmp/flutter-version.json
RUN FLUTTER_VERSION=$(jq -er '.flutter | select(type == "string") | select(test("^[0-9]+\\.[0-9]+\\.[0-9]+$"))' /tmp/flutter-version.json) && \
    curl --fail --location --output flutter.tar.xz "https://storage.googleapis.com/flutter_infra_release/releases/stable/linux/flutter_linux_${FLUTTER_VERSION}-stable.tar.xz" && \
    tar -xf flutter.tar.xz -C "${HOME}" && \
    rm flutter.tar.xz /tmp/flutter-version.json && \
    flutter config --no-analytics && \
    yes "y" | flutter doctor --android-licenses && \
    flutter doctor
