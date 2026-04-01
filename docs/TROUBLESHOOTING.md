# Troubleshooting Guide

Common issues and solutions for the dotfiles bootstrap system.

## Bootstrap Issues

### "Another bootstrap process is already running"

A stale lock file exists from a previous interrupted run.

```bash
rm -f ~/.cache/dotfiles-bootstrap/bootstrap.lock
bash ~/dotfiles/bootstrap/bootstrap.sh --resume
```

### Bootstrap fails during Homebrew installation

```bash
# Install Homebrew manually
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

# Add Homebrew to PATH (Apple Silicon)
eval "$(/opt/homebrew/bin/brew shellenv)"

# Resume bootstrap
bash ~/dotfiles/bootstrap/bootstrap.sh --resume
```

### "Command Line Tools not found"

```bash
xcode-select --install
# Wait for installation, then retry
bash ~/dotfiles/bootstrap/bootstrap.sh --resume
```

### Permission errors with Homebrew

```bash
sudo chown -R $(whoami) $(brew --prefix)/*
bash ~/dotfiles/bootstrap/bootstrap.sh --resume
```

## Shell Issues

### Zsh not loading configuration

1. Verify symlinks exist:
   ```bash
   ls -la ~/.zshrc ~/.zshenv
   ```

2. Re-create symlinks:
   ```bash
   rcup -v
   ```

3. Check for syntax errors:
   ```bash
   zsh -n ~/.zshrc
   ```

### Shell prompt not showing git branch

The `git-current-branch` script must be in your PATH:
```bash
which git-current-branch
# Should show: ~/.bin/git-current-branch or ~/dotfiles/bin/git-current-branch
```

If missing, run `rcup` to recreate the symlinks.

### PATH not including Homebrew tools

Add to your `~/.zshrc.local`:
```bash
# Apple Silicon
eval "$(/opt/homebrew/bin/brew shellenv)"

# Intel
eval "$(/usr/local/bin/brew shellenv)"
```

## Git Issues

### SSH signing not working

1. Verify 1Password SSH agent is running
2. Check `~/.gitconfig.local` has signing configuration
3. Verify the allowed_signers file:
   ```bash
   cat ~/.config/git/allowed_signers
   ```
4. Test SSH signing:
   ```bash
   echo "test" | ssh-keygen -Y sign -f ~/.ssh/id_ed25519 -n git
   ```

### Git push rejected (no SSH key)

```bash
# Test SSH connection to GitHub
ssh -T git@github.com

# If using 1Password, ensure the agent socket exists
ls -la ~/Library/Group\ Containers/2BUA8C4S2C.com.1password/t/agent.sock
```

## Vim Issues

### vim-plug not installing plugins

```bash
# Reinstall vim-plug
curl -fLo ~/.vim/autoload/plug.vim --create-dirs \
  https://raw.githubusercontent.com/junegunn/vim-plug/master/plug.vim

# Install plugins manually
vim +PlugInstall +qa
```

### Vim errors on startup

```bash
# Check for errors
vim -es -c 'q!' 2>&1

# Skip loading plugins temporarily
vim -u NONE
```

## RCM Issues

### rcup not creating symlinks

```bash
# Check rcrc configuration
cat ~/.rcrc

# Run with verbose output
rcup -v

# Force overwrite existing files
rcup -f
```

### Symlinks point to wrong directory

Check your `~/.rcrc` `DOTFILES_DIRS` setting:
```bash
grep DOTFILES_DIRS ~/.rcrc
```

## asdf Issues

### asdf plugin not found

```bash
# List available plugins
asdf plugin list all | grep PLUGIN_NAME

# Add plugin manually
asdf plugin add nodejs
asdf plugin add python
asdf plugin add ruby
```

### Tool version not installing

```bash
# List available versions
asdf list all nodejs

# Install specific version
asdf install nodejs 20.11.1

# Set global version
asdf global nodejs 20.11.1
```

## Recovery

### Full reset and restart

```bash
# Reset bootstrap state
rm -rf ~/.cache/dotfiles-bootstrap

# Start fresh
bash ~/dotfiles/bootstrap/bootstrap.sh --force
```

### Restore backed up files

Backups are stored in `~/.cache/dotfiles-bootstrap/backups/`:
```bash
ls ~/.cache/dotfiles-bootstrap/backups/
# Copy files back as needed
```

### Check error reports

```bash
ls ~/.cache/dotfiles-bootstrap/error-report-*.log
cat ~/.cache/dotfiles-bootstrap/error-report-LATEST.log
```

## Getting More Help

1. Run bootstrap with debug output:
   ```bash
   bash ~/dotfiles/bootstrap/bootstrap.sh --debug --phase PHASE_NAME
   ```

2. Check the architecture docs: [ARCHITECTURE.md](./ARCHITECTURE.md)

3. Run the verification script:
   ```bash
   bash ~/dotfiles/scripts/verify-install.sh
   ```