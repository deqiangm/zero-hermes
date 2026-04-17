#!/usr/bin/env bash
#
# ZeroHermes Installer
# One-line install: curl -fsSL https://raw.githubusercontent.com/deqiangm/zero-hermes/main/install.sh | bash
#
# Supported: Linux, macOS (Intel/Apple Silicon)
# Requires: bash, git, python3
#

set -e

# =============================================================================
# Colors and formatting
# =============================================================================

if [[ -t 1 ]]; then
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[0;33m'
    BLUE='\033[0;34m'
    BOLD='\033[1m'
    RESET='\033[0m'
else
    RED=''
    GREEN=''
    YELLOW=''
    BLUE=''
    BOLD=''
    RESET=''
fi

info() { echo -e "${BLUE}==>${RESET} ${BOLD}$1${RESET}"; }
success() { echo -e "${GREEN}✓${RESET} $1"; }
warn() { echo -e "${YELLOW}Warning:${RESET} $1" >&2; }
error() { echo -e "${RED}Error:${RESET} $1" >&2; exit 1; }

# =============================================================================
# Detect platform
# =============================================================================

detect_platform() {
    OS="$(uname -s)"
    ARCH="$(uname -m)"
    
    case "$OS" in
        Darwin) OS="macos" ;;
        Linux)  OS="linux" ;;
        *)      error "Unsupported OS: $OS" ;;
    esac
    
    case "$ARCH" in
        x86_64|amd64) ARCH="x64" ;;
        arm64|aarch64) ARCH="arm64" ;;
        *) error "Unsupported architecture: $ARCH" ;;
    esac
    
    info "Detected: $OS ($ARCH)"
}

# =============================================================================
# Check dependencies
# =============================================================================

check_dependencies() {
    local missing=()
    
    # Check bash version (3.2+ for macOS compatibility)
    if [[ "${BASH_VERSINFO[0]}" -lt 3 ]] || \
       [[ "${BASH_VERSINFO[0]}" -eq 3 && "${BASH_VERSINFO[1]}" -lt 2 ]]; then
        error "Bash 3.2+ required (found ${BASH_VERSION})"
    fi
    
    # Required commands
    for cmd in git python3 curl; do
        if ! command -v "$cmd" &>/dev/null; then
            missing+=("$cmd")
        fi
    done
    
    if [[ ${#missing[@]} -gt 0 ]]; then
        error "Missing dependencies: ${missing[*]}\n\nInstall with:\n  macOS: brew install ${missing[*]}\n  Linux: sudo apt install ${missing[*]}"
    fi
    
    # Check Python version (3.8+)
    PYTHON_VERSION=$(python3 -c 'import sys; print(f"{sys.version_info.major}.{sys.version_info.minor}")')
    if [[ $(echo "$PYTHON_VERSION < 3.8" | bc -l 2>/dev/null || echo "0") -eq 1 ]]; then
        error "Python 3.8+ required (found $PYTHON_VERSION)"
    fi
    
    success "All dependencies satisfied"
}

# =============================================================================
# Installation directory
# =============================================================================

get_install_dir() {
    # Priority: ZEROTHERMES_HOME env > ~/.zerohermes
    if [[ -n "${ZEROTHERMES_HOME:-}" ]]; then
        INSTALL_DIR="$ZEROTHERMES_HOME"
    else
        INSTALL_DIR="$HOME/.zerohermes"
    fi
    
    # Check if already installed
    if [[ -d "$INSTALL_DIR/.git" ]]; then
        warn "ZeroHermes already installed at $INSTALL_DIR"
        read -rp "Reinstall/update? [y/N] " choice
        case "$choice" in
            y|Y)
                info "Updating existing installation..."
                UPDATE_MODE=1
                ;;
            *)
                info "Aborted. To reinstall, run: rm -rf $INSTALL_DIR && ./install.sh"
                exit 0
                ;;
        esac
    else
        UPDATE_MODE=0
    fi
}

# =============================================================================
# Download and install
# =============================================================================

install_zerohermes() {
    REPO_URL="https://github.com/deqiangm/zero-hermes.git"
    BRANCH="${ZEROTHERMES_BRANCH:-main}"
    
    if [[ "$UPDATE_MODE" -eq 1 ]]; then
        cd "$INSTALL_DIR"
        git fetch origin "$BRANCH"
        git reset --hard "origin/$BRANCH"
        success "Updated to latest version"
    else
        info "Cloning ZeroHermes to $INSTALL_DIR..."
        git clone -b "$BRANCH" "$REPO_URL" "$INSTALL_DIR"
        success "Cloned successfully"
    fi
    
    cd "$INSTALL_DIR"
}

# =============================================================================
# Initialize database
# =============================================================================

initialize_database() {
    info "Initializing database..."
    
    DB_DIR="$INSTALL_DIR/data"
    mkdir -p "$DB_DIR"
    
    # Create sessions database
    python3 lib/pyhelper.py --db "$DB_DIR/sessions.db" init-db 2>/dev/null || true
    
    success "Database initialized"
}

# =============================================================================
# Configure environment
# =============================================================================

configure_environment() {
    ENV_FILE="$INSTALL_DIR/.env"
    
    if [[ ! -f "$ENV_FILE" ]]; then
        info "Creating .env file..."
        cp "$INSTALL_DIR/.env.example" "$ENV_FILE" 2>/dev/null || cat > "$ENV_FILE" << 'EOF'
# ZeroHermes Configuration
# Copy this file and add your API keys

# LLM Provider (openrouter, openai, anthropic, zai)
LLM_PROVIDER=openrouter
LLM_MODEL=anthropic/claude-sonnet-4

# API Keys (required)
# OPENROUTER_API_KEY=your_key_here
# OPENAI_API_KEY=your_key_here
# ANTHROPIC_API_KEY=your_key_here
# ZAI_API_KEY=your_key_here

# Telegram Bot (optional)
# TG_BOT_TOKEN=your_token_here
# TG_ALLOWED_CHATS=123456,789012

# Settings
LLM_TIMEOUT=120
LLM_MAX_RETRIES=3
EOF
        success "Created .env template"
        warn "Please edit $ENV_FILE and add your API key(s)"
    else
        success ".env already exists"
    fi
}

# =============================================================================
# Shell integration
# =============================================================================

setup_shell() {
    info "Setting up shell integration..."
    
    # Detect shell config file
    SHELL_RC=""
    if [[ -n "${BASH_VERSION:-}" ]]; then
        if [[ -f "$HOME/.bashrc" ]]; then
            SHELL_RC="$HOME/.bashrc"
        elif [[ -f "$HOME/.bash_profile" ]]; then
            SHELL_RC="$HOME/.bash_profile"
        fi
    elif [[ -n "${ZSH_VERSION:-}" ]]; then
        if [[ -f "$HOME/.zshrc" ]]; then
            SHELL_RC="$HOME/.zshrc"
        elif [[ -f "$HOME/.zprofile" ]]; then
            SHELL_RC="$HOME/.zprofile"
        fi
    fi
    
    if [[ -z "$SHELL_RC" ]]; then
        warn "Could not detect shell config file"
        return
    fi
    
    # Add to PATH if not already present
    if ! grep -q 'zerohermes' "$SHELL_RC" 2>/dev/null; then
        cat >> "$SHELL_RC" << EOF

# ZeroHermes - AI Agent
export ZEROTHERMES_HOME="$INSTALL_DIR"
export PATH="\$ZEROTHERMES_HOME/bin:\$PATH"
EOF
        success "Added to $SHELL_RC"
        info "Run: source $SHELL_RC"
    else
        success "Already in $SHELL_RC"
    fi
}

# =============================================================================
# Run tests
# =============================================================================

run_tests() {
    info "Running tests..."
    cd "$INSTALL_DIR"
    
    if [[ -x "tests/test_pyhelper.sh" ]]; then
        ./tests/test_pyhelper.sh && success "All tests passed"
    fi
}

# =============================================================================
# Summary
# =============================================================================

print_summary() {
    echo ""
    echo -e "${BOLD}╔══════════════════════════════════════════════════════╗${RESET}"
    echo -e "${BOLD}║          ZeroHermes Installation Complete           ║${RESET}"
    echo -e "${BOLD}╚══════════════════════════════════════════════════════╝${RESET}"
    echo ""
    echo -e "  ${GREEN}✓${RESET} Installed to: ${BOLD}$INSTALL_DIR${RESET}"
    echo ""
    echo -e "  ${BLUE}Next steps:${RESET}"
    echo ""
    echo -e "  1. Edit ${YELLOW}$INSTALL_DIR/.env${RESET} and add your API key"
    echo -e "  2. Reload shell: ${YELLOW}source ~/.bashrc${RESET} (or ~/.zshrc)"
    echo -e "  3. Run: ${YELLOW}zero-hermes${RESET}"
    echo ""
    echo -e "  ${BLUE}Or run directly:${RESET}"
    echo -e "  ${YELLOW}$INSTALL_DIR/bin/zero-hermes${RESET}"
    echo ""
    echo -e "  ${BLUE}Documentation:${RESET}"
    echo -e "  https://github.com/deqiangm/zero-hermes"
    echo ""
}

# =============================================================================
# Main
# =============================================================================

main() {
    echo -e "${BOLD}"
    echo "  ███████╗███████╗ ██████╗██████╗ ███████╗██████╗ "
    echo "  ╚══███╔╝██╔════╝██╔════╝██╔══██╗██╔════╝██╔══██╗"
    echo "    ███╔╝ █████╗  ██║     ██████╔╝█████╗  ██████╔╝"
    echo "   ███╔╝  ██╔══╝  ██║     ██╔══██╗██╔══╝  ██╔══██╗"
    echo "  ███████╗███████╗╚██████╗██║  ██║███████╗██║  ██║"
    echo "  ╚══════╝╚══════╝ ╚═════╝╚═╝  ╚═╝╚══════╝╚═╝  ╚═╝"
    echo -e "${RESET}"
    echo -e "  ${BOLD}A minimal AI agent with Shell + Python${RESET}"
    echo ""
    
    detect_platform
    check_dependencies
    get_install_dir
    install_zerohermes
    initialize_database
    configure_environment
    setup_shell
    
    # Optional: run tests
    if [[ "${RUN_TESTS:-0}" == "1" ]]; then
        run_tests
    fi
    
    print_summary
}

main "$@"
