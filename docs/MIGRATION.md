# Dotfiles Migration Guide

This guide walks you through setting up your complete development environment on a new Mac using the automated bootstrap system.

## Quick Start

**One-command setup for a new Mac:**

```bash
bash ~/dotfiles/bootstrap/bootstrap.sh
```

That's it! The bootstrap script will handle everything automatically.

## Prerequisites

### System Requirements

- **macOS 11.0 (Big Sur) or later**
- **20GB+ available disk space**
- **Internet connection**
- **Admin privileges** (for some installations)

### Before You Begin

1. **Sign into your Apple ID** in System Preferences
2. **Install App Store** apps you want (optional - can be done via script)
3. **Have your 1Password account ready** for SSH key setup
4. **Ensure you're connected to the internet**

## Step-by-Step Migration

### 1. Get the Dotfiles Repository

If you don't have the dotfiles repository yet:

```bash
# Clone the repository
git clone https://github.com/YOUR_USERNAME/dotfiles.git ~/dotfiles
cd ~/dotfiles
```

If you already have it (like from a USB drive or cloud storage):

```bash
# Navigate to your dotfiles directory
cd ~/dotfiles
```

### 2. Run the Bootstrap Script

#### Full Automated Setup (Recommended)

```bash
bash ~/dotfiles/bootstrap/bootstrap.sh
```

This will:
- ✅ Check system requirements
- ✅ Install Homebrew and all packages
- ✅ Set up essential system tools
- ✅ Create dotfiles symlinks with rcm
- ✅ Install development tools and version managers
- ✅ Configure Vim and install plugins
- ✅ Install applications and extensions
- ✅ Configure shell and environment
- ✅ Verify the installation

#### With Options

```bash
# With verbose output
bash ~/dotfiles/bootstrap/bootstrap.sh --verbose

# With debug information
bash ~/dotfiles/bootstrap/bootstrap.sh --debug

# Dry run (see what would be done)
bash ~/dotfiles/bootstrap/bootstrap.sh --dry-run

# Save detailed logs
bash ~/dotfiles/bootstrap/bootstrap.sh --log-file ~/bootstrap.log
```

### 3. Resume After Interruption

If the bootstrap process is interrupted, you can resume exactly where you left off:

```bash
bash ~/dotfiles/bootstrap/bootstrap.sh --resume
```

### 4. Run Individual Phases

You can run specific phases independently:

```bash
# List all available phases
bash ~/dotfiles/bootstrap/bootstrap.sh --list-phases

# Run only Homebrew installation
bash ~/dotfiles/bootstrap/bootstrap.sh --phase 02-homebrew

# Run only vim setup
bash ~/dotfiles/bootstrap/bootstrap.sh --phase 06-vim-setup
```

## What Gets Installed

### Package Managers
- **Homebrew** - macOS package manager
- **npm/yarn** - Node.js package managers
- **asdf** - Multi-language version manager

### Development Tools
- **Git** with enhanced configuration
- **Zsh** with custom configuration and completions
- **Vim** with plugins and configuration
- **tmux** for terminal multiplexing
- **Universal CTags** for code navigation

### Languages and Runtimes
- **Node.js** (LTS versions)
- **Python** (3.11, 3.12)
- **Ruby** (latest stable)
- **Go** (latest stable)
- **Rust** (stable)

### Applications
- **Visual Studio Code** with extensions
- **Cursor IDE** with extensions
- **Docker Desktop**
- **1Password** and CLI
- **iTerm2**
- **Rectangle** (window management)

### Command Line Tools
- **ripgrep** (rg) - fast search
- **the_silver_searcher** (ag) - code search
- **fzf** - fuzzy finder
- **jq** - JSON processor
- **tree** - directory visualization
- **htop** - process monitor

## Configuration Overview

### Shell Configuration
- **Zsh** as default shell with custom prompt
- **Git-aware** prompt showing current branch
- **Vi mode** keybindings
- **Enhanced history** with search
- **Auto-completion** for development tools

### Git Configuration
- **SSH signing** with 1Password integration
- **Helpful aliases** (st, co, ci, etc.)
- **Global gitignore** patterns
- **Enhanced diff** output with git-delta

### Vim Configuration
- **vim-plug** plugin manager
- **fzf integration** for file search
- **Language support** (Go, Elixir, JavaScript, etc.)
- **Git integration** with fugitive
- **Syntax highlighting** and linting

### Development Environment
- **asdf** for managing language versions
- **Default tool versions** automatically installed
- **Shell completions** for all major tools
- **PATH configuration** for all installed tools

## Secrets and Credentials

The bootstrap system helps you set up credentials securely:

### 1Password Integration
- **SSH signing keys** automatically configured
- **API tokens** managed through 1Password CLI
- **GPG keys** for commit signing

### Manual Setup Required
After bootstrap completes, you'll need to configure:

1. **Git user information** (if not already set):
   ```bash
   git config --global user.name "Your Name"
   git config --global user.email "your.email@example.com"
   ```

2. **SSH keys** for GitHub/GitLab:
   ```bash
   # Generate new SSH key (if needed)
   ssh-keygen -t ed25519 -C "your.email@example.com"

   # Add to SSH agent
   ssh-add ~/.ssh/id_ed25519

   # Copy public key to clipboard
   pbcopy < ~/.ssh/id_ed25519.pub
   ```

3. **1Password SSH agent** (if using 1Password for SSH):
   - Enable SSH agent in 1Password settings
   - Configure SSH config to use 1Password agent

## Troubleshooting

### Common Issues

**Bootstrap fails during Homebrew installation:**
```bash
# Install Homebrew manually first
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

# Then resume bootstrap
bash ~/dotfiles/bootstrap/bootstrap.sh --resume
```

**Permission errors:**
```bash
# Fix Homebrew permissions
sudo chown -R $(whoami) $(brew --prefix)/*

# Restart bootstrap
bash ~/dotfiles/bootstrap/bootstrap.sh --resume
```

**Command Line Tools missing:**
```bash
# Install Xcode Command Line Tools
xcode-select --install

# Wait for installation to complete, then restart
bash ~/dotfiles/bootstrap/bootstrap.sh --resume
```

**Symlinks not created properly:**
```bash
# Run rcup manually to debug
rcup -v

# Check for conflicts
rcup -d
```

### Getting Help

1. **Check the logs** if you used `--log-file`
2. **Run with debug mode** for detailed output:
   ```bash
   bash ~/dotfiles/bootstrap/bootstrap.sh --debug --phase PHASE_NAME
   ```
3. **Review error reports** in `~/.cache/dotfiles-bootstrap/`
4. **See troubleshooting guide**: [TROUBLESHOOTING.md](./TROUBLESHOOTING.md)

## Post-Installation Steps

### 1. Restart Your Shell
```bash
# Start a new terminal session or
exec zsh
```

### 2. Verify Installation
```bash
# Run the verification script
bash ~/dotfiles/scripts/verify-install.sh

# Check specific tools
which git node python3 vim
git --version
node --version
python3 --version
```

### 3. Customize Your Setup
```bash
# Create local overrides
mkdir -p ~/dotfiles-local
echo "# My custom zsh configuration" > ~/dotfiles-local/zshrc.local

# Add personal scripts
mkdir -p ~/dotfiles-local/bin
# Add your custom scripts here
```

### 4. Configure System Preferences
```bash
# Run macOS defaults automation (optional)
bash ~/dotfiles/scripts/mac-defaults.sh
```

## Maintenance

### Updating Dotfiles
```bash
cd ~/dotfiles
git pull
rcup  # Re-run rcup to apply any changes
```

### Updating Packages
```bash
# Update Homebrew packages
brew update && brew upgrade

# Update global npm packages
npm update -g

# Update vim plugins
vim +PlugUpdate +qa
```

### Adding New Packages
1. **Add to Brewfile**: Edit `~/dotfiles/manifests/brewfile`
2. **Install new packages**: `brew bundle install --file=~/dotfiles/manifests/brewfile`
3. **Commit changes**: Git commit the updated Brewfile

## Advanced Usage

### Environment Variables
```bash
# Enable verbose output
export VERBOSE=true

# Enable debug mode
export DEBUG=true

# Custom log file location
export LOG_FILE=~/my-bootstrap.log
```

### Selective Installation
```bash
# Install only specific categories
bash ~/dotfiles/bootstrap/bootstrap.sh --phase 02-homebrew
bash ~/dotfiles/bootstrap/bootstrap.sh --phase 06-vim-setup
```

### Fresh Start
```bash
# Reset bootstrap state and start over
bash ~/dotfiles/bootstrap/bootstrap.sh --force
```

## Next Steps

- **Explore the configuration**: Look through `~/.zshrc`, `~/.vimrc`, `~/.gitconfig`
- **Customize to your needs**: Create local overrides in `~/dotfiles-local/`
- **Learn the tools**: Try out `fzf`, `ripgrep`, and other installed utilities
- **Set up your development projects**: Your environment is ready!

## Getting Support

- **Documentation**: See `~/dotfiles/docs/` for detailed guides
- **Issues**: Check existing configuration in dotfiles repository
- **Customization**: See [CUSTOMIZATION.md](./CUSTOMIZATION.md) for extension guides

---

**Enjoy your new development environment! 🚀**