# ComfyUI for AI Photobooth - Production Ready
FROM nvidia/cuda:12.1.0-cudnn8-runtime-ubuntu22.04

# Build metadata
LABEL maintainer="stirproductionltd@gmail.com"
LABEL version="1.0"
LABEL description="ComfyUI AI Photobooth with LivePortrait"

# Build arguments
ARG UID=1000
ARG GID=1000
ARG COMFYUI_REPO=https://github.com/Stiryourmind/ComfyUI-v0.3.59-for-AI-booth.git
ARG COMFYUI_BRANCH=main

# ============================================================
# CRITICAL: Prevent interactive prompts
# ============================================================
ENV DEBIAN_FRONTEND=noninteractive
ENV TZ=UTC
ENV PYTHONUNBUFFERED=1

# Configure timezone
RUN ln -snf /usr/share/zoneinfo/$TZ /etc/localtime && echo $TZ > /etc/timezone

# ============================================================
# System Dependencies
# ============================================================
RUN apt-get update && apt-get install -y --no-install-recommends \
    tzdata software-properties-common \
    && add-apt-repository ppa:deadsnakes/ppa \
    && apt-get update && apt-get install -y --no-install-recommends \
    python3.11 python3.11-dev python3.11-venv python3.11-distutils \
    git build-essential cmake curl \
    libopencv-dev libglib2.0-0 libsm6 libxext6 libxrender-dev libgomp1 \
    libgl1 libglx-mesa0 \
    fonts-dejavu-core fontconfig \
    && curl -sS https://bootstrap.pypa.io/get-pip.py | python3.11 \
    && update-alternatives --install /usr/bin/python python /usr/bin/python3.11 1 \
    && update-alternatives --install /usr/bin/python3 python3 /usr/bin/python3.11 1 \
    && python3.11 -m pip install --upgrade pip setuptools wheel \
    && groupadd --gid ${GID} appuser \
    && useradd --uid ${UID} --gid ${GID} --create-home --shell /bin/bash appuser \
    && rm -rf /var/lib/apt/lists/*

# ============================================================
# Entrypoint Setup
# ============================================================
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh && chown ${UID}:${GID} /entrypoint.sh

# Switch to non-root
USER ${UID}:${GID}
ENV PATH=/home/appuser/.local/bin:$PATH
WORKDIR /app

# ============================================================
# Clone ComfyUI
# ============================================================
RUN git clone --depth 1 --branch ${COMFYUI_BRANCH} ${COMFYUI_REPO} ComfyUI
WORKDIR /app/ComfyUI

# ============================================================
# Install PyTorch 2.1.2 (cu121)
# ============================================================
RUN pip install --no-cache-dir \
    torch==2.1.2+cu121 \
    torchvision==0.16.2+cu121 \
    torchaudio==2.1.2+cu121 \
    --index-url https://download.pytorch.org/whl/cu121

RUN pip install --no-cache-dir -r requirements.txt

# ============================================================
# OpenCV version locking
# ============================================================
RUN echo "opencv-python==4.10.0.84" > /tmp/opencv-constraints.txt && \
    echo "opencv-python-headless==4.10.0.84" >> /tmp/opencv-constraints.txt && \
    echo "opencv-contrib-python==4.10.0.84" >> /tmp/opencv-constraints.txt && \
    echo "opencv-contrib-python-headless==4.10.0.84" >> /tmp/opencv-constraints.txt

ENV PIP_CONSTRAINT=/tmp/opencv-constraints.txt

RUN pip uninstall -y opencv-python opencv-python-headless \
    opencv-contrib-python opencv-contrib-python-headless || true \
    && pip install --no-cache-dir \
    opencv-python==4.10.0.84 \
    opencv-python-headless==4.10.0.84 \
    opencv-contrib-python==4.10.0.84 \
    opencv-contrib-python-headless==4.10.0.84

# ============================================================
# Install FaceNet FIRST (PuLID dependency)
# ============================================================
RUN pip install --no-cache-dir facenet-pytorch==2.6.0

# ============================================================
# Install Custom Nodes
# ============================================================
USER root
COPY custom_nodes.txt /tmp/custom_nodes.txt
WORKDIR /app/ComfyUI/custom_nodes

RUN echo "====== Cloning Custom Nodes ======" && \
    while IFS= read -r raw_repo; do \
        repo="$(echo "$raw_repo" | tr -d '\r' | sed 's/[[:space:]]*$//' )"; \
        [ -z "$repo" ] && continue; \
        echo "$repo" | grep -qE '^[[:space:]]*#' && continue; \
        if echo "$repo" | grep -qi "comfyui-manager"; then \
            git clone --depth 1 "$repo" comfyui-manager; continue; \
        fi; \
        repo_name=$(basename "$repo" .git); \
        git clone --depth 1 "$repo" "$repo_name" || true; \
    done < /tmp/custom_nodes.txt

# ============================================================
# Install PuLID Flux ll FaceNet (correct position)
# ============================================================
WORKDIR /app/ComfyUI/custom_nodes

# Normalize folder name
RUN if [ -d "ComfyUI_PuLID_Flux_ll_FaceNet.git" ]; then \
        mv ComfyUI_PuLID_Flux_ll_FaceNet.git ComfyUI_PuLID_Flux_ll_FaceNet; fi

# Install if not cloned by list
RUN if [ ! -d "ComfyUI_PuLID_Flux_ll_FaceNet" ]; then \
        git clone --depth 1 \
        https://github.com/KY-2000/ComfyUI_PuLID_Flux_ll_FaceNet \
        ComfyUI_PuLID_Flux_ll_FaceNet; \
    fi

# Install PuLID requirements
RUN pip install --no-cache-dir -r \
    ComfyUI_PuLID_Flux_ll_FaceNet/requirements.txt || true

# Optional InsightFace
RUN pip install --no-cache-dir insightface==0.7.3 onnxruntime onnxruntime-gpu || true

# ============================================================
# Install ALL custom node requirements
# ============================================================
RUN for d in /app/ComfyUI/custom_nodes/*/; do \
        if [ -f "${d}requirements.txt" ]; then \
            pip install --no-cache-dir -r "${d}requirements.txt" || true; \
        fi \
    done

RUN chown -R ${UID}:${GID} /app/ComfyUI/custom_nodes

# ============================================================
# Switch back to non-root
# ============================================================
USER ${UID}:${GID}
WORKDIR /app/ComfyUI

# Final OpenCV locking
RUN pip uninstall -y opencv-python opencv-python-headless \
    opencv-contrib-python opencv-contrib-python-headless || true \
    && pip install --no-cache-dir --force-reinstall --no-deps \
    opencv-python==4.10.0.84 \
    opencv-python-headless==4.10.0.84 \
    opencv-contrib-python==4.10.0.84 \
    opencv-contrib-python-headless==4.10.0.84

# ============================================================
# Verification
# ============================================================
RUN python - <<EOF
import torch, cv2
from facenet_pytorch import MTCNN
print("Torch:", torch.__version__)
print("CUDA:", torch.cuda.is_available())
print("OpenCV:", cv2.__version__)
print("FaceNet OK")
EOF

# ============================================================
# Cleanup
# ============================================================
USER root
RUN pip cache purge && rm -f /tmp/custom_nodes.txt /tmp/opencv-constraints.txt
USER ${UID}:${GID}

# ============================================================
# Runtime
# ============================================================
EXPOSE 8188
ENTRYPOINT ["/entrypoint.sh"]
CMD ["python", "/app/ComfyUI/main.py", "--listen", "0.0.0.0"]