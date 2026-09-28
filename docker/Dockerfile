# Runtime image for the Python steps of Saguaro-Biosciences/lembeddingscellprofileling
# (QC_MULT, QC_REPORT_ANNOT, EMBEDDINGS_EXTRACTION, EMBEDDINGS_EXTRACTION_NETWORK).
# The pipeline scripts themselves live in ../bin and are put on PATH by Nextflow, so
# script changes do not require rebuilding this image.
#
# Build (from the repo root):
#   docker build -t ghcr.io/saguaro-biosciences/lembeddingscellprofileling:1.0.0dev -f docker/Dockerfile docker/
FROM pytorch/pytorch:2.5.1-cuda12.1-cudnn9-runtime

ENV DEBIAN_FRONTEND=noninteractive \
    PIP_NO_CACHE_DIR=1 \
    PYTHONUNBUFFERED=1

# procps: Nextflow uses `ps` to collect task metrics
RUN apt-get update \
    && apt-get install -y --no-install-recommends procps libgl1 libglib2.0-0 \
    && rm -rf /var/lib/apt/lists/*

COPY requirements.txt /tmp/requirements.txt
RUN pip install -r /tmp/requirements.txt && rm /tmp/requirements.txt

# Bake model weights into the image so tasks run offline and do not re-download ~1.7 GB
# on every new host. Paths must be readable by any uid (tasks may run as the host user).
ENV CELLPOSE_LOCAL_MODELS_PATH=/opt/models/cellpose \
    HF_HOME=/opt/models/huggingface
RUN python -c "from cellpose import models; models.CellposeModel(gpu=False)" \
    && python -c "from transformers import AutoImageProcessor, AutoModel; \
n='timm/tf_efficientnetv2_l.in21k'; AutoImageProcessor.from_pretrained(n); AutoModel.from_pretrained(n)" \
    && chmod -R a+rX /opt/models

# Writable scratch for libraries that cache under $HOME, whatever uid the task runs as
ENV HF_HUB_OFFLINE=1 \
    TRANSFORMERS_OFFLINE=1 \
    MPLCONFIGDIR=/tmp/matplotlib \
    NUMBA_CACHE_DIR=/tmp/numba_cache

LABEL org.opencontainers.image.source="https://github.com/Saguaro-Biosciences/lembeddingscellprofileling" \
      org.opencontainers.image.description="Cellpose + EfficientNetV2 embedding extraction for live-cell profiling"
