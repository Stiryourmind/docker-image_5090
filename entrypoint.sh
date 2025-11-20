#!/usr/bin/env bash

# ComfyUI Docker Startup File v1.0.3 (Fixed)
# Original by John Aldred - Modified for Docker volume compatibility

set -e

echo "🚀 Starting ComfyUI AIBooth..."
echo "========================================="

# ============================================================
# 1. Create user directories (no chown on volumes!)
# ============================================================
echo "📁 Ensuring user directories exist..."

# Create directories if they don't exist
mkdir -p /app/ComfyUI/user/default/ComfyUI-Manager

# Only try to change permissions if NOT a volume mount
# (volumes inherit host permissions, can't be changed by non-root)
if [ ! -d "/app/ComfyUI/user/.docker_volume" ]; then
    # Try to set permissions, ignore failures (likely a volume mount)
    chown -R "$(id -u)":"$(id -g)" /app/ComfyUI/user 2>/dev/null || true
    chmod -R u+rwX /app/ComfyUI/user 2>/dev/null || true
fi

echo "   ✅ User directories ready"

# ============================================================
# 2. Configure ComfyUI-Manager
# ============================================================
CFG_DIR="/app/ComfyUI/user/default/ComfyUI-Manager"
CFG_FILE="$CFG_DIR/config.ini"
DB_DIR="$CFG_DIR"
DB_PATH="${DB_DIR}/manager.db"
SQLITE_URL="sqlite:////${DB_PATH}"

echo "⚙️  Configuring ComfyUI-Manager..."

# Ensure config directory exists
mkdir -p "$CFG_DIR"

if [ ! -f "$CFG_FILE" ]; then
    echo "   ↳ Creating new config.ini..."
    cat > "$CFG_FILE" <<EOF
[default]
use_uv = False
file_logging = False
db_mode = cache
database_url = ${SQLITE_URL}
EOF
    echo "   ✅ Config created"
else
    echo "   ↳ Updating existing config.ini..."
    
    # use_uv = False
    if grep -q '^use_uv' "$CFG_FILE"; then
        sed -i 's/^use_uv.*/use_uv = False/' "$CFG_FILE"
    else
        printf '\nuse_uv = False\n' >> "$CFG_FILE"
    fi

    # file_logging = False
    if grep -q '^file_logging' "$CFG_FILE"; then
        sed -i 's/^file_logging.*/file_logging = False/' "$CFG_FILE"
    else
        printf '\nfile_logging = False\n' >> "$CFG_FILE"
    fi
    
    # Remove any log_path entries
    sed -i '/^log_path[[:space:]=]/d' "$CFG_FILE" 2>/dev/null || true

    # db_mode = cache
    if grep -q '^db_mode' "$CFG_FILE"; then
        sed -i 's/^db_mode.*/db_mode = cache/' "$CFG_FILE"
    else
        printf '\ndb_mode = cache\n' >> "$CFG_FILE"
    fi

    # database_url
    if grep -q '^database_url' "$CFG_FILE"; then
        sed -i "s|^database_url.*|database_url = ${SQLITE_URL}|" "$CFG_FILE"
    else
        printf "database_url = ${SQLITE_URL}\n" >> "$CFG_FILE"
    fi
    
    echo "   ✅ Config updated"
fi

# ============================================================
# 3. One-time initialization (custom nodes)
# ============================================================
INIT_MARKER="/app/ComfyUI/.docker_initialized"

if [ ! -f "$INIT_MARKER" ]; then
    echo ""
    echo "🔧 First-time initialization detected..."
    
    # Install custom node dependencies if needed
    if [ -d "/app/ComfyUI/custom_nodes" ]; then
        echo "📦 Checking custom node dependencies..."
        
        for node_dir in /app/ComfyUI/custom_nodes/*/; do
            if [ -f "${node_dir}requirements.txt" ]; then
                node_name=$(basename "$node_dir")
                echo "   ↳ Installing dependencies for: $node_name"
                pip install -q -r "${node_dir}requirements.txt" 2>/dev/null || echo "      ⚠️  Some dependencies failed (non-critical)"
            fi
        done
        
        echo "   ✅ Dependencies processed"
    fi
    
    # Create marker to skip this on next startup
    touch "$INIT_MARKER"
    echo "   ✅ Initialization complete"
else
    echo "✅ Previously initialized, skipping setup"
fi

# ============================================================
# 4. Display startup info
# ============================================================
echo ""
echo "========================================="
echo "🎨 ComfyUI Configuration"
echo "========================================="
echo "📂 Working directory: $(pwd)"
echo "👤 Running as: $(whoami) (UID: $(id -u), GID: $(id -g))"
echo "🐍 Python: $(python --version 2>&1)"
echo "🔥 PyTorch: $(python -c 'import torch; print(torch.__version__)' 2>/dev/null || echo 'N/A')"
echo "🎮 CUDA: $(python -c 'import torch; print("Available" if torch.cuda.is_available() else "Not available")' 2>/dev/null || echo 'N/A')"
echo "📦 Custom nodes: $(ls -1d /app/ComfyUI/custom_nodes/*/ 2>/dev/null | wc -l)"
echo "========================================="
echo ""

# ============================================================
# 5. Start ComfyUI
# ============================================================
echo "🚀 Launching ComfyUI..."
echo "🌐 Access at: http://localhost:8188"
echo "========================================="
echo ""

exec "$@"