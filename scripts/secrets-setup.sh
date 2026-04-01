#!/bin/bash
#
# Secrets Setup Wizard
# Interactive script to initialize credentials from templates
# Never commits actual credentials to the repository
#

set -euo pipefail

# Source logging if available
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOTFILES_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

if [[ -f "$DOTFILES_ROOT/bootstrap/lib/logging.sh" ]]; then
    source "$DOTFILES_ROOT/bootstrap/lib/logging.sh"
else
    log_info() { echo "→ $*"; }
    log_success() { echo "✓ $*"; }
    log_warning() { echo "⚠ $*"; }
    log_error() { echo "✗ $*" >&2; }
    log_header() { echo; echo "▶ $*"; echo; }
    log_step() { echo "→ $*"; }
    confirm() {
        local msg="$1" default="${2:-n}"
        echo -n "? $msg [y/N] "
        read -r response
        [[ "${response:-$default}" =~ ^[yY] ]]
    }
fi

readonly TEMPLATES_DIR="$DOTFILES_ROOT/templates"

# Setup Git local configuration
setup_git_local() {
    log_step "Setting up local Git configuration"

    local target="$HOME/.gitconfig.local"
    local template="$TEMPLATES_DIR/gitconfig.local.template"

    if [[ -f "$target" ]]; then
        log_info "~/.gitconfig.local already exists"
        if ! confirm "Overwrite existing file?"; then
            return 0
        fi
    fi

    if [[ ! -f "$template" ]]; then
        log_warning "Template not found: $template"
        return 0
    fi

    # Interactive prompts
    echo -n "  Your full name: "
    read -r git_name
    echo -n "  Your email address: "
    read -r git_email

    # Create the local gitconfig
    sed -e "s/YOUR_NAME/$git_name/" -e "s/YOUR_EMAIL/$git_email/" "$template" > "$target"

    log_success "Created ~/.gitconfig.local"

    # Ask about SSH signing with 1Password
    if confirm "Set up SSH commit signing with 1Password?"; then
        setup_1password_signing "$target"
    fi
}

# Setup 1Password SSH signing
setup_1password_signing() {
    local gitconfig_local="$1"

    if [[ ! -d "/Applications/1Password.app" ]]; then
        log_warning "1Password app not found at /Applications/1Password.app"
        log_info "Install 1Password first, then re-run this setup"
        return 0
    fi

    if ! command -v op >/dev/null 2>&1; then
        log_warning "1Password CLI (op) not found"
        log_info "Install with: brew install 1password-cli"
        return 0
    fi

    echo -n "  SSH signing key (from 1Password, e.g. ssh-ed25519 AAAA...): "
    read -r signing_key

    if [[ -z "$signing_key" ]]; then
        log_info "Skipping SSH signing setup (no key provided)"
        return 0
    fi

    # Uncomment and configure the signing section
    cat >> "$gitconfig_local" << EOF

[gpg]
    format = ssh
[gpg "ssh"]
    program = "/Applications/1Password.app/Contents/MacOS/op-ssh-sign"
    allowedSignersFile = ~/.config/git/allowed_signers
[commit]
    gpgsign = true
[tag]
    gpgsign = true
EOF

    # Create allowed_signers file
    local git_email
    git_email=$(git config --global user.email 2>/dev/null || echo "")

    if [[ -n "$git_email" ]]; then
        mkdir -p "$HOME/.config/git"
        echo "$git_email $signing_key" > "$HOME/.config/git/allowed_signers"
        log_success "Created ~/.config/git/allowed_signers"
    fi

    log_success "1Password SSH signing configured"
}

# Setup SSH configuration
setup_ssh_config() {
    log_step "Setting up SSH configuration"

    local target="$HOME/.ssh/config"
    local template="$TEMPLATES_DIR/.ssh/config.template"

    mkdir -p "$HOME/.ssh"
    chmod 700 "$HOME/.ssh"

    if [[ -f "$target" ]]; then
        log_info "~/.ssh/config already exists"
        if ! confirm "Overwrite existing SSH config?"; then
            return 0
        fi
    fi

    if [[ ! -f "$template" ]]; then
        log_warning "Template not found: $template"
        return 0
    fi

    # Check for 1Password SSH agent
    local use_1password=false
    if [[ -d "/Applications/1Password.app" ]]; then
        if confirm "Use 1Password SSH agent for key management?"; then
            use_1password=true
        fi
    fi

    if [[ "$use_1password" == "true" ]]; then
        # Create config with 1Password agent enabled
        cat > "$target" << 'EOF'
# SSH Configuration — managed by dotfiles

Host *
    AddKeysToAgent yes
    ServerAliveInterval 60
    ServerAliveCountMax 3
    IdentityAgent "~/Library/Group Containers/2BUA8C4S2C.com.1password/t/agent.sock"

Host github.com
    HostName github.com
    User git
EOF
    else
        cp "$template" "$target"
    fi

    chmod 600 "$target"
    log_success "Created ~/.ssh/config"
}

# Setup shell secrets file
setup_shell_secrets() {
    log_step "Setting up shell secrets"

    local target="$HOME/.zsh_secrets"

    if [[ -f "$target" ]]; then
        log_info "~/.zsh_secrets already exists"
        if ! confirm "Overwrite existing secrets file?"; then
            return 0
        fi
    fi

    cat > "$target" << 'EOF'
# Shell secrets — DO NOT commit this file to any repository
# This file is sourced by .zshrc.local or .zshenv.local

# Add your API keys and tokens below:
# export GITHUB_TOKEN=""
# export OPENAI_API_KEY=""
# export ANTHROPIC_API_KEY=""
EOF

    chmod 600 "$target"
    log_success "Created ~/.zsh_secrets (mode 600)"
    log_info "Add your API keys to ~/.zsh_secrets"
    log_info "Source it from ~/.zshrc.local with: source ~/.zsh_secrets"
}

# Setup local zshenv
setup_zshenv_local() {
    log_step "Setting up local shell environment"

    local target="$HOME/.zshenv.local"
    local template="$TEMPLATES_DIR/.zshenv.local.template"

    if [[ -f "$target" ]]; then
        log_info "~/.zshenv.local already exists"
        return 0
    fi

    if [[ -f "$template" ]]; then
        cp "$template" "$target"
        log_success "Created ~/.zshenv.local from template"
    else
        touch "$target"
        log_success "Created empty ~/.zshenv.local"
    fi
}

# Generate SSH key if needed
setup_ssh_key() {
    log_step "Checking SSH keys"

    if [[ -f "$HOME/.ssh/id_ed25519" ]]; then
        log_info "SSH key already exists: ~/.ssh/id_ed25519"
        return 0
    fi

    # Check for 1Password — if using 1Password agent, skip key generation
    local op_agent_sock="$HOME/Library/Group Containers/2BUA8C4S2C.com.1password/t/agent.sock"
    if [[ -S "$op_agent_sock" ]]; then
        log_info "1Password SSH agent detected — keys managed through 1Password"
        return 0
    fi

    if confirm "Generate a new SSH key?"; then
        echo -n "  Email for SSH key: "
        read -r ssh_email

        if [[ -z "$ssh_email" ]]; then
            log_warning "No email provided, skipping SSH key generation"
            return 0
        fi

        ssh-keygen -t ed25519 -C "$ssh_email" -f "$HOME/.ssh/id_ed25519"

        # Start ssh-agent and add key
        eval "$(ssh-agent -s)" >/dev/null 2>&1
        ssh-add --apple-use-keychain "$HOME/.ssh/id_ed25519" 2>/dev/null || ssh-add "$HOME/.ssh/id_ed25519"

        log_success "SSH key generated and added to agent"
        log_info "Public key:"
        cat "$HOME/.ssh/id_ed25519.pub"
        echo
        log_info "Add this key to your GitHub/GitLab account"

        # Copy to clipboard
        if command -v pbcopy >/dev/null 2>&1; then
            pbcopy < "$HOME/.ssh/id_ed25519.pub"
            log_info "Public key copied to clipboard"
        fi
    fi
}

# Show summary
show_summary() {
    log_header "Secrets Setup Summary"

    local items=("$HOME/.gitconfig.local" "$HOME/.ssh/config" "$HOME/.zsh_secrets" "$HOME/.zshenv.local" "$HOME/.ssh/id_ed25519")

    for item in "${items[@]}"; do
        if [[ -f "$item" ]]; then
            log_info "  ✓ $item"
        else
            log_info "  ✗ $item (not created)"
        fi
    done

    echo
    log_info "Remember:"
    log_info "  - Never commit secrets to git repositories"
    log_info "  - Store API keys in ~/.zsh_secrets"
    log_info "  - Use 1Password for SSH key management when possible"
}

# Main execution
main() {
    log_header "Secrets Setup Wizard"
    log_info "This wizard helps you configure credentials securely."
    log_info "No secrets will be stored in the dotfiles repository."
    echo

    setup_git_local
    echo
    setup_ssh_config
    echo
    setup_ssh_key
    echo
    setup_shell_secrets
    echo
    setup_zshenv_local
    echo
    show_summary

    log_success "Secrets setup completed"
}

main "$@"