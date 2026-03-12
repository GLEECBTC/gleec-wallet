#!/usr/bin/env bash
set -euo pipefail

echo "=== Gleec QA Automation Setup ==="

# ---------------------------------------------------------------------------
# Platform detection
# ---------------------------------------------------------------------------
IS_WSL=false
IS_WINDOWS_HOST=false

if grep -qi microsoft /proc/version 2>/dev/null; then
    IS_WSL=true
    IS_WINDOWS_HOST=true
    echo "[platform] Running inside WSL2 (Windows host detected)"
elif [[ "$(uname -s)" == *MINGW* ]] || [[ "$(uname -s)" == *MSYS* ]]; then
    IS_WINDOWS_HOST=true
    echo "[platform] Running on native Windows — please use WSL2 for the runner"
    exit 1
else
    echo "[platform] Running on Linux/macOS"
fi

# ---------------------------------------------------------------------------
# 1. Ollama
# ---------------------------------------------------------------------------
if $IS_WSL; then
    echo "[ollama] On WSL2: Ollama should run natively on Windows for best GPU performance."
    echo "[ollama] Install from https://ollama.com/download/windows if not already installed."
    echo "[ollama] Checking if Ollama is reachable on localhost:11434..."
    if curl -sf http://localhost:11434/api/tags > /dev/null 2>&1; then
        echo "[ollama] Ollama is reachable from WSL2."
    else
        echo "[ollama] WARNING: Ollama not reachable on localhost:11434."
        echo "[ollama] Start Ollama on Windows and ensure it listens on all interfaces."
        echo "[ollama] Set OLLAMA_HOST=0.0.0.0 in Windows environment variables if needed."
    fi
else
    if ! command -v ollama &> /dev/null; then
        echo "[ollama] Installing Ollama..."
        curl -fsSL https://ollama.com/install.sh | sh
    else
        echo "[ollama] Ollama already installed."
    fi

    if ! curl -sf http://localhost:11434/api/tags > /dev/null 2>&1; then
        echo "[ollama] Starting Ollama server..."
        ollama serve &
        sleep 3
    fi
fi

# ---------------------------------------------------------------------------
# 2. Pull vision model
# ---------------------------------------------------------------------------
echo "[model] Pulling qwen2.5-vl:32b (this may take a while on first run)..."
if $IS_WSL; then
    echo "[model] Run 'ollama pull qwen2.5-vl:32b' on your Windows host if not already pulled."
else
    ollama pull qwen2.5-vl:32b
fi

# ---------------------------------------------------------------------------
# 3. Create directory structure
# ---------------------------------------------------------------------------
echo "[dirs] Creating project directories..."
mkdir -p results/screenshots results/videos

# ---------------------------------------------------------------------------
# 4. Environment file
# ---------------------------------------------------------------------------
if [ ! -f .env ]; then
    echo "[env] Creating .env from .env.example..."
    cp .env.example .env
    echo "[env] Edit .env to set your APP_BASE_URL and other overrides."
else
    echo "[env] .env already exists, skipping."
fi

# ---------------------------------------------------------------------------
# 5. Python dependencies
# ---------------------------------------------------------------------------
echo "[python] Installing Python dependencies..."
pip install -r requirements.txt

# ---------------------------------------------------------------------------
# 6. Docker stack
# ---------------------------------------------------------------------------
echo "[docker] Starting Skyvern + PostgreSQL..."
docker compose up -d

echo ""
echo "=== Setup complete ==="
echo "  Ollama:  http://localhost:11434"
echo "  Skyvern: http://localhost:8000"
echo ""
echo "Next steps:"
echo "  1. Edit .env if needed (APP_BASE_URL, model choice, etc.)"
echo "  2. Run smoke test:  python -m runner.runner --tag smoke"
echo "  3. Run full suite:  python -m runner.runner"
echo ""
