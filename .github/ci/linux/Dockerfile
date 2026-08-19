# syntax=docker/dockerfile:1

FROM denoland/deno:bin-2.9.5@sha256:0d1262facd139e815217c001945eb822c7a78584cf660142c34a6b53effec1aa AS deno

FROM ubuntu:24.04@sha256:d78ab76437b1afc5f01e223d6bf0172763f404bb166441328845adbef44518cb

ARG DEBIAN_FRONTEND=noninteractive
ARG QT_VERSION=6.9.3

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        build-essential \
        ca-certificates \
        cmake \
        git \
        libgl1-mesa-dev \
        libgstreamer-gl1.0-0 \
        libpulse-dev \
        libxcb-cursor0 \
        libxcb-glx0 \
        libxcb-icccm4 \
        libxcb-image0 \
        libxcb-keysyms1 \
        libxcb-randr0 \
        libxcb-render-util0 \
        libxcb-render0 \
        libxcb-shape0 \
        libxcb-shm0 \
        libxcb-sync1 \
        libxcb-util1 \
        libxcb-xfixes0 \
        libxcb-xinerama0 \
        libxcb-xkb-dev \
        libxcb1 \
        libxkbcommon-dev \
        libxkbcommon-x11-0 \
        ninja-build \
        pulseaudio \
        python3 \
        python3-venv \
    && rm -rf /var/lib/apt/lists/*

RUN python3 -m venv /opt/aqt \
    && /opt/aqt/bin/pip install --no-cache-dir "aqtinstall==3.3.0" \
    && /opt/aqt/bin/aqt install-qt linux desktop "${QT_VERSION}" \
        --outputdir /opt/Qt \
    && rm -rf /opt/aqt

COPY --from=deno /deno /usr/local/bin/deno

RUN useradd --create-home --uid 1001 --shell /bin/bash runner \
    && mkdir -p /workspace \
    && chown runner:runner /workspace

ENV QT_ROOT_DIR=/opt/Qt/${QT_VERSION}/gcc_64
ENV CMAKE_PREFIX_PATH=${QT_ROOT_DIR}
ENV LD_LIBRARY_PATH=${QT_ROOT_DIR}/lib
ENV PATH=${QT_ROOT_DIR}/bin:${PATH}
ENV PKG_CONFIG_PATH=${QT_ROOT_DIR}/lib/pkgconfig
ENV QML2_IMPORT_PATH=${QT_ROOT_DIR}/qml
ENV QT_PLUGIN_PATH=${QT_ROOT_DIR}/plugins
ENV QT_QPA_PLATFORM=offscreen
ENV LANG=C.UTF-8
ENV HOME=/home/runner

USER runner
WORKDIR /workspace
