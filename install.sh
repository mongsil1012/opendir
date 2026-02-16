#!/bin/bash
#
# OPENDIR Installer
# Usage: curl -fsSL https://opendir.cokac.com/install.sh | bash
#

set -e

BINARY_NAME="opendir"
BASE_URL="https://opendir.cokac.com/dist"
DIST_DIR="${OPENDIR_DIST_DIR:-}"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

info() {
    echo -e "${BLUE}→${NC} $1"
}

success() {
    echo -e "${GREEN}✓${NC} $1"
}

warn() {
    echo -e "${YELLOW}!${NC} $1"
}

error() {
    echo -e "${RED}✗${NC} $1"
    exit 1
}

# Detect OS
detect_os() {
    local os
    os="$(uname -s)"
    case "$os" in
        Linux*)  echo "linux" ;;
        Darwin*) echo "macos" ;;
        *)       error "Unsupported OS: $os" ;;
    esac
}

# Detect architecture
detect_arch() {
    local arch
    arch="$(uname -m)"
    case "$arch" in
        x86_64|amd64)  echo "x86_64" ;;
        aarch64|arm64) echo "aarch64" ;;
        *)             error "Unsupported architecture: $arch" ;;
    esac
}

# Get install directory
get_install_dir() {
    # Prefer /usr/local/bin (always in PATH)
    if [ -d "/usr/local/bin" ]; then
        echo "/usr/local/bin"
    else
        # Fallback to ~/.local/bin
        mkdir -p "$HOME/.local/bin"
        echo "$HOME/.local/bin"
    fi
}

# Check if command exists
has_cmd() {
    command -v "$1" >/dev/null 2>&1
}

# Download file
download() {
    local url="$1"
    local dest="$2"

    if has_cmd curl; then
        curl -fsSL "$url" -o "$dest"
    elif has_cmd wget; then
        wget -q "$url" -O "$dest"
    else
        error "curl or wget is required"
    fi
}

resolve_dist_dir() {
    if [ -n "$DIST_DIR" ]; then
        echo "$DIST_DIR"
        return
    fi

    if [ -n "$0" ] && [ "$0" != "-" ] && [ -f "$0" ] && [ -d "$(dirname "$0")/dist" ]; then
        echo "$(dirname "$0")/dist"
        return
    fi

    if [ -f "$(pwd)/install.sh" ] && [ -d "./dist" ]; then
        echo "$(pwd)/dist"
        return
    fi

    echo ""
}

# Shell wrapper function to add
SHELL_FUNC='opendir() { command opendir "$@" && cd "$(cat ~/.opendir/lastdir 2>/dev/null || pwd)"; }'

# Get shell config file
get_shell_config() {
    local shell_name
    shell_name="$(basename "$SHELL")"

    case "$shell_name" in
        bash)
            if [ -f "$HOME/.bashrc" ]; then
                echo "$HOME/.bashrc"
            elif [ -f "$HOME/.bash_profile" ]; then
                echo "$HOME/.bash_profile"
            else
                echo "$HOME/.bashrc"
            fi
            ;;
        zsh)
            echo "$HOME/.zshrc"
            ;;
        *)
            echo ""
            ;;
    esac
}

# Setup shell wrapper function
setup_shell() {
    local config_file
    config_file="$(get_shell_config)"

    if [ -z "$config_file" ]; then
        return
    fi

    # Check if already configured
    if [ -f "$config_file" ] && grep -q "opendir()" "$config_file"; then
        return
    fi

    # Create file if not exists
    if [ ! -f "$config_file" ]; then
        touch "$config_file"
    fi

    # Add function
    echo "" >> "$config_file"
    echo "# opendir - cd to last directory on exit" >> "$config_file"
    echo "$SHELL_FUNC" >> "$config_file"
}

main() {
    # Detect platform
    local os arch
    os="$(detect_os)"
    arch="$(detect_arch)"

    info "Downloading opendir ($os-$arch)..."

    # Build download URL
    local filename="${BINARY_NAME}-${os}-${arch}"
    local url="${BASE_URL}/${filename}"
    local local_dist_dir
    local local_file
    local source_file
    local_dist_dir="$(resolve_dist_dir)"
    local_file="${local_dist_dir:+$local_dist_dir/$filename}"

    # Create temp file
    local tmpfile
    tmpfile="$(mktemp)"
    trap 'rm -f "$tmpfile"' EXIT

    if [ -n "$local_file" ] && [ -f "$local_file" ]; then
        info "Using local dist file: $local_file"
        source_file="$local_file"
    else
        source_file="$url"
    fi

    # Download or copy from local dist
    if [ "$source_file" = "$url" ]; then
        if ! download "$url" "$tmpfile"; then
            error "Download failed"
        fi
    else
        cp "$source_file" "$tmpfile"
    fi

    # Make executable
    chmod +x "$tmpfile"

    # Get install directory
    local install_dir
    install_dir="$(get_install_dir)"
    local install_path="${install_dir}/${BINARY_NAME}"

    # Install
    if [ -w "$install_dir" ]; then
        mv "$tmpfile" "$install_path"
    else
        sudo mv "$tmpfile" "$install_path"
    fi

    # Verify installation
    if [ -x "$install_path" ]; then
        # Check if in PATH
        if ! echo "$PATH" | grep -q "$install_dir"; then
            warn "Add to PATH: export PATH=\"$install_dir:\$PATH\""
        fi

        # Setup shell wrapper
        setup_shell

        success "Installed! Run 'opendir' to start."
    else
        error "Installation failed"
    fi
}

main "$@"
