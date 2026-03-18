FROM komodo/android-sdk:35 AS final

ENV FLUTTER_VERSION="3.41.3"
ENV HOME="/home/komodo"
ENV USER="komodo"
ENV PATH=$PATH:$HOME/flutter/bin

USER $USER

WORKDIR /app

RUN curl -O https://storage.googleapis.com/flutter_infra_release/releases/stable/linux/flutter_linux_${FLUTTER_VERSION}-stable.tar.xz && \
    tar -xvf flutter_linux_${FLUTTER_VERSION}-stable.tar.xz -C ${HOME} && \
    rm flutter_linux_${FLUTTER_VERSION}-stable.tar.xz && \
    flutter config --no-analytics  && \
    yes "y" | flutter doctor --android-licenses && \
    flutter doctor
