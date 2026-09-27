# syntax=docker/dockerfile:1.7
# Laya System 1 server image for Unraid, one tag per target: cpu or nvidia.
# Build from this folder with the Laya source in upstream/:
#   docker build --build-arg TARGET=cpu --build-context laya=upstream -t pikkonmg/laya-system-one:cpu .
ARG PYTHON_IMAGE=python:3.11-slim-trixie

FROM ${PYTHON_IMAGE} AS build

ENV PIP_NO_CACHE_DIR=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1

ARG TARGET
ARG TORCH_VERSION=2.14.0
# CUDA 12.6 runs on NVIDIA drivers from the 560 series onward.
ARG TORCH_NVIDIA_INDEX=cu126

RUN case "$TARGET" in \
        cpu) echo cpu > /tmp/torch_index ;; \
        nvidia) echo "$TORCH_NVIDIA_INDEX" > /tmp/torch_index ;; \
        *) echo "TARGET must be cpu or nvidia" >&2; exit 1 ;; \
    esac

RUN python -m venv /opt/venv
ENV PATH="/opt/venv/bin:$PATH"

# Fail the build when the index serves a different PyTorch build than requested.
RUN torch_index="$(cat /tmp/torch_index)" \
    && pip install "torch==${TORCH_VERSION}" --index-url "https://download.pytorch.org/whl/${torch_index}" \
    && python -c "import sys, torch; expected = sys.argv[1]; sys.exit(0 if torch.__version__ == expected else 'Expected PyTorch ' + expected + ', installed ' + torch.__version__)" "${TORCH_VERSION}+${torch_index}"

WORKDIR /src
COPY --from=laya pyproject.toml setup.py README.md LICENSE ./
COPY --from=laya laya/ ./laya/
RUN pip install ".[serve]" && pip check

# Triton only compiles kernels for torch.compile and the native JIT, which this
# image turns off with TORCH_DISABLE_NATIVE_JIT. Dropping it saves about 0.9 GB.
RUN if pip show triton >/dev/null 2>&1; then pip uninstall -y triton; fi

FROM ${PYTHON_IMAGE} AS runtime

ARG TARGET

LABEL org.opencontainers.image.title="Laya System 1" \
      org.opencontainers.image.description="Laya System 1 decision engine server for Unraid" \
      org.opencontainers.image.source="https://github.com/NandhaKishorM/laya" \
      org.opencontainers.image.licenses="Apache-2.0"

# torch 2.14 compiles Triton kernels on the first CUDA inference unless native JIT is
# off, and this image carries no C compiler (upstream issue #365).
ENV PATH="/opt/venv/bin:$PATH" \
    TORCH_DISABLE_NATIVE_JIT=1 \
    PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    USE_TF=0 \
    USE_TORCH=1 \
    TOKENIZERS_PARALLELISM=false \
    OMP_NUM_THREADS=4 \
    LAYA_TARGET=${TARGET} \
    LAYA_HOST=0.0.0.0 \
    LAYA_PORT=8000 \
    PUID=99 \
    PGID=100 \
    HOME=/data \
    HF_HOME=/data/huggingface

COPY --from=build /opt/venv /opt/venv
COPY --from=laya LICENSE /usr/share/doc/laya/LICENSE
COPY --from=laya docker/entrypoint.py /opt/laya/entrypoint.py
COPY start.sh /opt/laya/start.sh

VOLUME /data
EXPOSE 8000

# The server loads its checkpoints before it listens, so the first start with
# preload on can take several minutes while the weights download.
HEALTHCHECK --interval=30s --timeout=5s --retries=3 --start-period=10m \
    CMD ["python3", "-c", "import os, urllib.request; urllib.request.urlopen('http://127.0.0.1:' + os.environ['LAYA_PORT'] + '/health', timeout=4)"]

ENTRYPOINT ["/opt/laya/start.sh"]
CMD ["laya-serve"]
