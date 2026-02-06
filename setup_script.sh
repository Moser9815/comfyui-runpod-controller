#!/bin/bash
# ComfyUI Setup Script for RunPod
# This script is idempotent - safe to run multiple times

set -e  # Exit on error

echo ""
echo "=========================================="
echo "  ComfyUI Setup Starting..."
echo "=========================================="
echo ""

# CivitAI API Token (required for some model downloads)
# Set via: export CIVITAI_API_TOKEN=your_token_here
if [ -z "$CIVITAI_API_TOKEN" ]; then
    echo "WARNING: CIVITAI_API_TOKEN not set. Some model downloads may fail."
    echo "Set it with: export CIVITAI_API_TOKEN=your_token"
    echo ""
    CIVITAI_TOKEN_PARAM=""
else
    echo "CivitAI API token detected."
    echo ""
    CIVITAI_TOKEN_PARAM="?token=${CIVITAI_API_TOKEN}"
fi

cd /workspace

# Clone ComfyUI if not exists
if [ ! -d "ComfyUI" ]; then
    echo "[1/8] Cloning ComfyUI..."
    git clone https://github.com/comfyanonymous/ComfyUI.git
else
    echo "[1/8] ComfyUI already exists, skipping clone"
fi

cd ComfyUI

# Install requirements
echo ""
echo "[2/8] Installing Python requirements..."
pip install -r requirements.txt 2>&1 | tail -5

# Fix numpy compatibility
echo ""
echo "[3/8] Fixing numpy version..."
pip install numpy==1.26.4 2>&1 | tail -2

# Upgrade PyTorch for CUDA 11.8
echo ""
echo "[4/8] Upgrading PyTorch (this takes a few minutes)..."
pip install --upgrade torch torchvision torchaudio --index-url https://download.pytorch.org/whl/cu118 2>&1 | tail -5

# Install Custom Nodes
echo ""
echo "[5/8] Installing custom nodes..."

cd custom_nodes

# ComfyUI-Manager
if [ ! -d "ComfyUI-Manager" ]; then
    echo "  → ComfyUI-Manager..."
    git clone https://github.com/ltdrdata/ComfyUI-Manager.git
    echo "    ✓ Done"
else
    echo "  → ComfyUI-Manager already exists, skipping"
fi

# rgthree-comfy (workflow improvements, required by RES4LYF)
if [ ! -d "rgthree-comfy" ]; then
    echo "  → rgthree-comfy..."
    git clone https://github.com/rgthree/rgthree-comfy.git
    echo "    ✓ Done"
else
    echo "  → rgthree-comfy already exists, skipping"
fi

# RES4LYF (advanced samplers)
if [ ! -d "RES4LYF" ]; then
    echo "  → RES4LYF..."
    git clone https://github.com/ClownsharkBatwing/RES4LYF.git
    echo "    Installing RES4LYF dependencies..."
    pip install -r RES4LYF/requirements.txt 2>&1 | tail -3
    echo "    ✓ Done"
else
    echo "  → RES4LYF already exists, skipping"
fi

# Civitai Comfy Nodes
if [ ! -d "civitai_comfy_nodes" ]; then
    echo "  → civitai_comfy_nodes..."
    git clone https://github.com/civitai/civitai_comfy_nodes.git
    if [ -f "civitai_comfy_nodes/requirements.txt" ]; then
        pip install -r civitai_comfy_nodes/requirements.txt 2>&1 | tail -3
    fi
    echo "    ✓ Done"
else
    echo "  → civitai_comfy_nodes already exists, skipping"
fi

# Install missing dependencies for custom nodes
echo "  → Installing additional dependencies..."
pip install PyWavelets gitpython dill piexif segment_anything -q
echo "    ✓ Done"

cd ..

# Create model directories
mkdir -p models/text_encoders models/diffusion_models models/checkpoints models/vae models/loras

echo ""
echo "[6/8] Downloading models..."
echo "      (Large files - this takes a while on first run)"
echo ""

# SDXL Base
if [ ! -f "models/checkpoints/sd_xl_base_1.0.safetensors" ]; then
    echo "  → SDXL Base 1.0 (~7GB)..."
    wget --progress=bar:force -O models/checkpoints/sd_xl_base_1.0.safetensors \
        https://huggingface.co/stabilityai/stable-diffusion-xl-base-1.0/resolve/main/sd_xl_base_1.0.safetensors
    echo "    ✓ Done"
else
    echo "  → SDXL Base already exists, skipping"
fi

# SDXL VAE
if [ ! -f "models/vae/sdxl_vae.safetensors" ]; then
    echo "  → SDXL VAE (~335MB)..."
    wget --progress=bar:force -O models/vae/sdxl_vae.safetensors \
        https://huggingface.co/stabilityai/sdxl-vae/resolve/main/sdxl_vae.safetensors
    echo "    ✓ Done"
else
    echo "  → SDXL VAE already exists, skipping"
fi

# Z-Image Turbo diffusion model
if [ ! -f "models/diffusion_models/z_image_turbo_bf16.safetensors" ]; then
    echo "  → Z-Image Turbo diffusion (~11GB)..."
    wget --progress=bar:force -O models/diffusion_models/z_image_turbo_bf16.safetensors \
        https://huggingface.co/Comfy-Org/z_image_turbo/resolve/main/split_files/diffusion_models/z_image_turbo_bf16.safetensors
    echo "    ✓ Done"
else
    echo "  → Z-Image Turbo already exists, skipping"
fi

# Qwen text encoder (for Z-Image Turbo)
if [ ! -f "models/text_encoders/qwen_3_4b.safetensors" ]; then
    echo "  → Qwen 3 4B text encoder (~7GB)..."
    wget --progress=bar:force -O models/text_encoders/qwen_3_4b.safetensors \
        https://huggingface.co/Comfy-Org/z_image_turbo/resolve/main/split_files/text_encoders/qwen_3_4b.safetensors
    echo "    ✓ Done"
else
    echo "  → Qwen text encoder already exists, skipping"
fi

# CLIP-L (for Flux)
if [ ! -f "models/text_encoders/clip_l.safetensors" ]; then
    echo "  → CLIP-L (~250MB)..."
    wget --progress=bar:force -O models/text_encoders/clip_l.safetensors \
        https://huggingface.co/comfyanonymous/flux_text_encoders/resolve/main/clip_l.safetensors
    echo "    ✓ Done"
else
    echo "  → CLIP-L already exists, skipping"
fi

# T5-XXL FP8 (for Flux - smaller than FP16, good quality)
if [ ! -f "models/text_encoders/t5xxl_fp8_e4m3fn.safetensors" ]; then
    echo "  → T5-XXL FP8 (~5GB)..."
    wget --progress=bar:force -O models/text_encoders/t5xxl_fp8_e4m3fn.safetensors \
        https://huggingface.co/comfyanonymous/flux_text_encoders/resolve/main/t5xxl_fp8_e4m3fn.safetensors
    echo "    ✓ Done"
else
    echo "  → T5-XXL FP8 already exists, skipping"
fi

# Flux VAE (ae.safetensors)
if [ ! -f "models/vae/ae.safetensors" ]; then
    echo "  → Flux VAE (~335MB)..."
    wget --progress=bar:force -O models/vae/ae.safetensors \
        https://huggingface.co/Comfy-Org/z_image_turbo/resolve/main/split_files/vae/ae.safetensors
    echo "    ✓ Done"
else
    echo "  → Flux VAE already exists, skipping"
fi

# Z-Image Turbo NSFW by Stable Yogi (checkpoint)
if [ ! -f "models/checkpoints/zimage_turbo_nsfw_fp8.safetensors" ]; then
    echo "  → Z-Image Turbo NSFW (~5.7GB)..."
    wget --progress=bar:force -O models/checkpoints/zimage_turbo_nsfw_fp8.safetensors \
        "https://civitai.com/api/download/models/2642303${CIVITAI_TOKEN_PARAM}"
    echo "    ✓ Done"
else
    echo "  → Z-Image Turbo NSFW already exists, skipping"
fi

# =============================================
# SDXL / Pony Checkpoints
# =============================================

# Prefect Pony XL v6
if [ ! -f "models/checkpoints/prefectPonyXL_v6.safetensors" ]; then
    echo "  → Prefect Pony XL v6 (~6.5GB)..."
    wget --progress=bar:force -O models/checkpoints/prefectPonyXL_v6.safetensors \
        "https://civitai.com/api/download/models/2114187${CIVITAI_TOKEN_PARAM}"
    echo "    ✓ Done"
else
    echo "  → Prefect Pony XL v6 already exists, skipping"
fi

# CyberRealistic Pony v16.0
if [ ! -f "models/checkpoints/cyberrealisticPony_v160.safetensors" ]; then
    echo "  → CyberRealistic Pony v16.0 (~12.9GB)..."
    wget --progress=bar:force -O models/checkpoints/cyberrealisticPony_v160.safetensors \
        "https://civitai.com/api/download/models/2581228${CIVITAI_TOKEN_PARAM}"
    echo "    ✓ Done"
else
    echo "  → CyberRealistic Pony v16.0 already exists, skipping"
fi

# =============================================
# Z-Image Turbo Checkpoints
# =============================================

# Jib Mix ZIT v2.0
if [ ! -f "models/checkpoints/jibMixZIT_v20.safetensors" ]; then
    echo "  → Jib Mix ZIT v2.0 (~11.5GB)..."
    wget --progress=bar:force -O models/checkpoints/jibMixZIT_v20.safetensors \
        "https://civitai.com/api/download/models/2637947${CIVITAI_TOKEN_PARAM}"
    echo "    ✓ Done"
else
    echo "  → Jib Mix ZIT v2.0 already exists, skipping"
fi

# =============================================
# WAN Video 2.2 I2V 14B Models
# =============================================

# DaSiWa WAN 2.2 I2V 14B - SynthSeduction High v9
if [ ! -f "models/checkpoints/DasiwaWAN22I2V14B_synthseductionHighV9.safetensors" ]; then
    echo "  → DaSiWa WAN I2V - SynthSeduction High v9 (~13.5GB)..."
    wget --progress=bar:force -O models/checkpoints/DasiwaWAN22I2V14B_synthseductionHighV9.safetensors \
        "https://civitai.com/api/download/models/2555640${CIVITAI_TOKEN_PARAM}"
    echo "    ✓ Done"
else
    echo "  → DaSiWa WAN I2V High already exists, skipping"
fi

# DaSiWa WAN 2.2 I2V 14B - SynthSeduction Low v9
if [ ! -f "models/checkpoints/DasiwaWAN22I2V14B_synthseductionLowV9.safetensors" ]; then
    echo "  → DaSiWa WAN I2V - SynthSeduction Low v9 (~13.5GB)..."
    wget --progress=bar:force -O models/checkpoints/DasiwaWAN22I2V14B_synthseductionLowV9.safetensors \
        "https://civitai.com/api/download/models/2555652${CIVITAI_TOKEN_PARAM}"
    echo "    ✓ Done"
else
    echo "  → DaSiWa WAN I2V Low already exists, skipping"
fi

# =============================================
# Pony LoRAs
# =============================================

echo ""
echo "  Downloading LoRAs..."

# Pony Detail Tweaker V2
if [ ! -f "models/loras/Pony_DetailV2.0.safetensors" ]; then
    echo "  → Pony Detail Tweaker (~11MB)..."
    wget --progress=bar:force -O models/loras/Pony_DetailV2.0.safetensors \
        "https://civitai.com/api/download/models/449738${CIVITAI_TOKEN_PARAM}"
    echo "    ✓ Done"
else
    echo "  → Pony Detail Tweaker already exists, skipping"
fi

# RawCam Slider
if [ ! -f "models/loras/RawCam_250_v1.safetensors" ]; then
    echo "  → RawCam Slider (~3MB)..."
    wget --progress=bar:force -O models/loras/RawCam_250_v1.safetensors \
        "https://civitai.com/api/download/models/1926656${CIVITAI_TOKEN_PARAM}"
    echo "    ✓ Done"
else
    echo "  → RawCam Slider already exists, skipping"
fi

# Real Skin Slider
if [ ! -f "models/loras/RealSkin_xxXL_v1.safetensors" ]; then
    echo "  → Real Skin Slider (~150MB)..."
    wget --progress=bar:force -O models/loras/RealSkin_xxXL_v1.safetensors \
        "https://civitai.com/api/download/models/1681921${CIVITAI_TOKEN_PARAM}"
    echo "    ✓ Done"
else
    echo "  → Real Skin Slider already exists, skipping"
fi

# Vivid Realism Color Enhancer
if [ ! -f "models/loras/VividRealismColorEnhancer.safetensors" ]; then
    echo "  → Vivid Realism Color Enhancer (~55MB)..."
    wget --progress=bar:force -O models/loras/VividRealismColorEnhancer.safetensors \
        "https://civitai.com/api/download/models/458702${CIVITAI_TOKEN_PARAM}"
    echo "    ✓ Done"
else
    echo "  → Vivid Realism Color Enhancer already exists, skipping"
fi

# Pony Realism Slider
if [ ! -f "models/loras/Pony Realism Slider.safetensors" ]; then
    echo "  → Pony Realism Slider (~5MB)..."
    wget --progress=bar:force -O "models/loras/Pony Realism Slider.safetensors" \
        "https://civitai.com/api/download/models/1253021${CIVITAI_TOKEN_PARAM}"
    echo "    ✓ Done"
else
    echo "  → Pony Realism Slider already exists, skipping"
fi

# Breast Size Slider
if [ ! -f "models/loras/Breast Size Slider.safetensors" ]; then
    echo "  → Breast Size Slider (~8MB)..."
    wget --progress=bar:force -O "models/loras/Breast Size Slider.safetensors" \
        "https://civitai.com/api/download/models/534952${CIVITAI_TOKEN_PARAM}"
    echo "    ✓ Done"
else
    echo "  → Breast Size Slider already exists, skipping"
fi

# Age Slider (SDXL)
if [ ! -f "models/loras/Age Slider.safetensors" ]; then
    echo "  → Age Slider (~177MB)..."
    wget --progress=bar:force -O "models/loras/Age Slider.safetensors" \
        "https://civitai.com/api/download/models/493670${CIVITAI_TOKEN_PARAM}"
    echo "    ✓ Done"
else
    echo "  → Age Slider already exists, skipping"
fi

# Pointy Breasts (banana)
if [ ! -f "models/loras/banana.safetensors" ]; then
    echo "  → Pointy Breasts LoRA (~109MB)..."
    wget --progress=bar:force -O models/loras/banana.safetensors \
        "https://civitai.com/api/download/models/478193${CIVITAI_TOKEN_PARAM}"
    echo "    ✓ Done"
else
    echo "  → Pointy Breasts LoRA already exists, skipping"
fi

echo ""
echo "[7/8] All models downloaded!"
echo ""
echo "=========================================="
echo "[8/8] Starting ComfyUI..."
echo "=========================================="
echo ""
echo "==========================================="
echo ""
echo "  ✓ ComfyUI URL:"
echo ""
echo "  https://${RUNPOD_POD_ID}-8188.proxy.runpod.net"
echo ""
echo "==========================================="
echo ""

# Start ComfyUI
python main.py --listen 0.0.0.0 --port 8188
