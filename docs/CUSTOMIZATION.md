# Customization Guide

How to modify and extend the dotfiles setup for your needs.

## Adding Local Overrides

The simplest way to customize is through local override files. These are never committed to the shared repository.

### Shell Configuration

```bash
# Create or edit ~/.zshrc.local
vim ~/.zshrc.local
```

Add your personal aliases, functions, and settings. This file is sourced at the end of `~/.zshrc`.

### Git Configuration

```bash
# Create or edit ~/.gitconfig.local
vim ~/.gitconfig.local
```

Override git settings without modifying the shared config.

### Vim Configuration

```bash
# Additional vim settings
vim ~/.vimrc.local

# Additional vim plugins
vim ~/.vimrc.bundles.local
```

### Using dotfiles-local Directory

For more complex overrides, create files in `~/dotfiles-local/`:

```bash
mkdir -p ~/dotfiles-local
# Files here are symlinked with higher priority than ~/dotfiles/
# Mirror the same directory structure
```

## Adding Homebrew Packages

Edit `~/dotfiles/manifests/brewfile`:

```ruby
# Add a formula
brew "my-tool"

# Add a cask (GUI application)
cask "my-app"

# Add a tap (third-party repository)
tap "owner/repo"
```

Then install:
```bash
brew bundle install --file=~/dotfiles/manifests/brewfile
```

## Adding IDE Extensions

### VS Code
Edit `~/dotfiles/manifests/extensions/vscode.txt` — one extension ID per line.

### Cursor
Edit `~/dotfiles/manifests/extensions/cursor.txt` — same format.

Install manually:
```bash
code --install-extension EXTENSION_ID
```

## Adding Shell Functions

Create a new file in the zsh functions directory:

```bash
# Create function file (no file extension needed)
vim ~/dotfiles/zsh/functions/my-function
```

The function will be auto-loaded by zsh on next shell start.

## Adding Shell Completions

Place completion files in `~/dotfiles/zsh/completion/`:

```bash
# Completion files must start with underscore
vim ~/dotfiles/zsh/completion/_my-tool
```

## Adding Git Hooks

Create hooks in the git template:

```bash
vim ~/dotfiles/git_template/hooks/my-hook
chmod +x ~/dotfiles/git_template/hooks/my-hook
```

For local-only hooks, use the local override:
```bash
mkdir -p ~/.git_template.local/hooks
vim ~/.git_template.local/hooks/pre-commit
```

## Adding Scripts to PATH

Place scripts in `~/dotfiles/bin/`:

```bash
vim ~/dotfiles/bin/my-script
chmod +x ~/dotfiles/bin/my-script
```

After running `rcup`, the script will be available as `my-script` in your PATH.

## Modifying Bootstrap Phases

To add a custom bootstrap phase:

1. Create a new phase script:
   ```bash
   vim ~/dotfiles/bootstrap/phases/10-custom.sh
   chmod +x ~/dotfiles/bootstrap/phases/10-custom.sh
   ```

2. Follow the existing phase template pattern (source logging.sh, define a `main` function)

3. Add the phase to the `PHASES` array in `bootstrap/bootstrap.sh`

## Modifying macOS Defaults

Edit `~/dotfiles/scripts/mac-defaults.sh` to add or change system preferences.

Each setting uses the `defaults write` command:
```bash
# Example: Set Dock size
defaults write com.apple.dock tilesize -int 36
```

## Adding Tool Versions

Edit `~/dotfiles/manifests/versions.txt` to add or update pinned versions:

```
# Format: tool_name version
nodejs 20.11.1
python 3.12.2
```

Then install via asdf:
```bash
asdf install nodejs 20.11.1
asdf global nodejs 20.11.1
```

## After Making Changes

Always run `rcup` after modifying files in `~/dotfiles/` to update symlinks:

```bash
rcup
```

For changes to shell configuration, start a new terminal session or:
```bash
exec zsh
```