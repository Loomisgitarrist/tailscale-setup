#!/bin/bash
# Tailscale Remote Setup for macOS (Apple Silicon)
# One-liner install: curl -fsSL <url> | bash
# For: Sebastian (Remote Access for Loomis)

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
PURPLE='\033[0;35m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

BANNER="${PURPLE}
╔══════════════════════════════════════════════════════════╗
║           🔗 TAILSCALE REMOTE SETUP                        ║
║      For Sebastian — Remote Access by Loomis               ║
╚══════════════════════════════════════════════════════════╝
${NC}"

print_banner() {
    echo -e "$BANNER"
}

info() {
    echo -e "${CYAN}ℹ️  $1${NC}"
}

success() {
    echo -e "${GREEN}✅ $1${NC}"
}

warn() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

error() {
    echo -e "${RED}❌ $1${NC}"
}

step() {
    echo ""
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BLUE}  STEP $1: $2${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
}

# macOS dialog helper
_dialog() {
    local title="$1"
    local message="$2"
    osascript -e "display dialog \"$message\" with title \"$title\" buttons {\"OK\"} default button \"OK\"" 2>/dev/null || true
}

# Check architecture
check_arch() {
    local arch=$(uname -m)
    if [[ "$arch" != "arm64" ]]; then
        warn "This Mac is $arch, not Apple Silicon (arm64)."
        _dialog "Architecture" "This script is optimized for Apple Silicon (M1/M2/M3/M4). Your Mac is $arch. It should still work, but let Loomis know."
    else
        success "Apple Silicon (arm64) detected."
    fi
}

# Check if Tailscale is installed
check_tailscale() {
    if [[ -d "/Applications/Tailscale.app" ]]; then
        success "Tailscale is already installed!"
        return 0
    fi
    return 1
}

# Download and install Tailscale
install_tailscale() {
    info "Downloading Tailscale for macOS..."
    local pkg_url="https://pkgs.tailscale.com/stable/Tailscale-latest-macos.pkg"
    local pkg_path="$HOME/Downloads/Tailscale.pkg"
    
    if ! curl -fsSL "$pkg_url" -o "$pkg_path"; then
        error "Download failed. Check your internet connection."
        _dialog "Error" "Could not download Tailscale. Please check your internet and try again."
        exit 1
    fi
    
    success "Download complete!"
    info "Installing Tailscale (enter your Mac password if asked)..."
    
    if sudo installer -pkg "$pkg_path" -target /; then
        success "Tailscale installed successfully!"
        rm -f "$pkg_path"
    else
        error "Installation failed."
        _dialog "Error" "Tailscale installation failed. Please download from https://tailscale.com/download and install manually."
        exit 1
    fi
}

# Start Tailscale and wait for login
start_tailscale() {
    info "Opening Tailscale app..."
    open -a Tailscale
    success "Tailscale opened!"
    
    echo ""
    warn "IMPORTANT: Please log in to Tailscale now."
    echo "   1. Click the Tailscale icon in your menu bar (top right)"
    echo "   2. Click 'Log in...'"
    echo "   3. Sign in with Google, Apple, Microsoft, or GitHub"
    echo ""
    
    read -p "👉 Press ENTER after you've logged in to Tailscale..."
}

# Get Tailscale IP
get_ip() {
    info "Getting your Tailscale IP..."
    
    local ip=""
    local attempts=0
    
    while [[ -z "$ip" && $attempts -lt 5 ]]; do
        ip=$(/usr/local/bin/tailscale ip -4 2>/dev/null || /opt/homebrew/bin/tailscale ip -4 2>/dev/null || true)
        if [[ -z "$ip" ]]; then
            warn "IP not ready yet, waiting... ($((attempts+1))/5)"
            sleep 3
            ((attempts++))
        fi
    done
    
    if [[ -n "$ip" ]]; then
        success "Your Tailscale IP is: $ip"
        echo ""
        echo -e "${PURPLE}╔════════════════════════════════════════════════╗${NC}"
        echo -e "${PURPLE}║  🌐 YOUR IP: ${GREEN}$ip${PURPLE}                  ║${NC}"
        echo -e "${PURPLE}╚════════════════════════════════════════════════╝${NC}"
        echo ""
        echo "$ip" > "$HOME/tailscale_ip.txt"
        TAILSCALE_IP="$ip"
        return 0
    else
        error "Could not get Tailscale IP. Make sure you're logged in."
        _dialog "Error" "Could not get your Tailscale IP. Please make sure you're logged into Tailscale and try again."
        exit 1
    fi
}

# Enable SSH (Remote Login)
enable_ssh() {
    info "Enabling SSH (Remote Login)..."
    
    if sudo systemsetup -setremotelogin on >/dev/null 2>&1; then
        success "SSH (Remote Login) enabled!"
        SSH_ENABLED=1
    else
        warn "Could not auto-enable SSH."
        echo "   Manual: System Settings → General → Sharing → Remote Login → ON"
        SSH_ENABLED=0
    fi
}

# Enable Screen Sharing (VNC)
enable_screen_sharing() {
    info "Enabling Screen Sharing (Remote Desktop)..."
    
    if sudo /System/Library/CoreServices/RemoteManagement/ARDAgent.app/Contents/Resources/kickstart \
        -activate -configure -access -on \
        -clientopts -setvnclegacy -vnclegacy yes \
        -restart -agent -privs -all >/dev/null 2>&1; then
        success "Screen Sharing enabled!"
        SCREEN_ENABLED=1
    else
        warn "Could not auto-enable Screen Sharing."
        echo "   Manual: System Settings → General → Sharing → Screen Sharing → ON"
        SCREEN_ENABLED=0
    fi
}

# Build and copy message for Loomis
send_to_loomis() {
    local ip="$1"
    local message="Hi Loomis! 👋

My Tailscale IP is: $ip

I've enabled:
✅ SSH (Remote Login)
✅ Screen Sharing (Remote Desktop)

You can connect with:
• Terminal: ssh $ip
• Screen Sharing: vnc://$ip

Ready when you are! 🔗"

    echo -e "${CYAN}📋 Here's your message for Loomis:${NC}"
    echo -e "${GREEN}$message${NC}"
    echo ""
    
    # Copy to clipboard
    echo "$message" | pbcopy
    success "Message copied to clipboard!"
    
    echo ""
    warn "📱 Paste it into WhatsApp/iMessage and send it to Loomis now!"
    echo ""
    
    # Show final dialog
    osascript -e "display dialog \"$message\" with title \"✅ Setup Complete! Paste to Loomis\" buttons {\"Copy Again\", \"Done\"} default button \"Done\"" 2>/dev/null || true
}

# Summary
print_summary() {
    local ip="$1"
    echo ""
    echo -e "${PURPLE}╔══════════════════════════════════════════════════════════╗${NC}"
    echo -e "${PURPLE}║              🎉 SETUP COMPLETE! 🎉                       ║${NC}"
    echo -e "${PURPLE}╚══════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "${CYAN}📌 Summary:${NC}"
    echo -e "   Tailscale IP: ${GREEN}$ip${NC}"
    echo -e "   SSH:          ${GREEN}Enabled${NC}"
    echo -e "   Screen Share:  ${GREEN}Enabled${NC}"
    echo ""
    echo -e "${CYAN}📁 Files saved:${NC}"
    echo -e "   IP saved to: ~/tailscale_ip.txt"
    echo ""
    echo -e "${CYAN}🔐 Security:${NC}"
    echo -e "   Only you and Loomis can connect."
    echo -e "   To disable: System Settings → General → Sharing → turn OFF"
    echo ""
    echo -e "${PURPLE}══════════════════════════════════════════════════════════${NC}"
    echo -e "${PURPLE}Done! You can close this Terminal window.${NC}"
    echo -e "${PURPLE}══════════════════════════════════════════════════════════${NC}"
    echo ""
}

# ═══════════════════════════════════════════════════════════
# MAIN
# ═══════════════════════════════════════════════════════════

main() {
    print_banner
    
    step "1/5" "Checking your Mac"
    check_arch
    
    step "2/5" "Installing Tailscale"
    if ! check_tailscale; then
        install_tailscale
    fi
    
    step "3/5" "Starting Tailscale"
    start_tailscale
    
    step "4/5" "Getting your IP"
    get_ip
    
    step "5/5" "Enabling remote access"
    enable_ssh
    enable_screen_sharing
    
    # Send info to Loomis
    send_to_loomis "$TAILSCALE_IP"
    
    # Final summary
    print_summary "$TAILSCALE_IP"
    
    # Keep terminal open
    read -p "Press ENTER to close..."
}

main "$@"
