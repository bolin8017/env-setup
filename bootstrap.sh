#!/usr/bin/env bash
# bootstrap.sh — One-liner installer for env-setup
# Usage: bash -c "$(curl -fsSL https://raw.githubusercontent.com/bolin8017/env-setup/main/bootstrap.sh)"
set -euo pipefail

REPO_URL="https://github.com/bolin8017/env-setup.git"
INSTALL_DIR="${HOME}/.local/share/env-setup"

# ---------- OS detection ----------
OS="$(uname -s)"

# ---------- Ensure git & curl ----------
if [[ "$OS" == "Darwin" ]]; then
    if ! command -v git &>/dev/null; then
        echo "Git not found. Installing Xcode Command Line Tools..."
        xcode-select --install
        echo "Please re-run this script after the installation completes."
        exit 1
    fi
elif [[ "$OS" == "Linux" ]]; then
    if ! command -v git &>/dev/null || ! command -v curl &>/dev/null; then
        echo "Installing git and curl..."
        if command -v apt-get &>/dev/null; then
            sudo apt-get update && sudo apt-get install -y git curl
        elif command -v dnf &>/dev/null; then
            sudo dnf install -y git curl
        elif command -v pacman &>/dev/null; then
            sudo pacman -Sy --noconfirm git curl
        else
            echo "Error: Could not detect package manager. Please install git and curl manually." >&2
            exit 1
        fi
    fi
else
    echo "Unsupported OS: $OS" >&2
    exit 1
fi

# ---------- Clone or update ----------
if [[ -d "$INSTALL_DIR/.git" ]]; then
    echo "Updating existing installation..."
    if ! git -C "$INSTALL_DIR" pull --ff-only; then
        echo "" >&2
        echo "Error: could not fast-forward $INSTALL_DIR." >&2
        echo "Local commits or edits to tracked files (e.g. config.yaml) block the update." >&2
        echo "Recover with one of:" >&2
        echo "  - move machine-specific settings into config.local.yaml, then:" >&2
        echo "      git -C '$INSTALL_DIR' stash && git -C '$INSTALL_DIR' pull --ff-only && git -C '$INSTALL_DIR' stash pop" >&2
        echo "  - or inspect what diverged:  git -C '$INSTALL_DIR' status" >&2
        exit 1
    fi
else
    echo "Cloning env-setup..."
    mkdir -p "$(dirname "$INSTALL_DIR")"
    git clone "$REPO_URL" "$INSTALL_DIR"
fi

# ---------- Run setup ----------
exec bash "$INSTALL_DIR/setup.sh" "$@"
