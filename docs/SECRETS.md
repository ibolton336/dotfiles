# Secrets Management Guide

How credentials and sensitive configuration are handled in this dotfiles setup.

## Core Principle

**No credentials are ever stored in the dotfiles repository.** All secrets live in local-only files that are excluded from version control.

## Secret File Locations

| File | Purpose | Created By |
|---|---|---|
| `~/.gitconfig.local` | Git user info, signing keys | `secrets-setup.sh` |
| `~/.ssh/config` | SSH host configuration | `secrets-setup.sh` |
| `~/.ssh/id_ed25519` | SSH private key | `secrets-setup.sh` or 1Password |
| `~/.zsh_secrets` | API keys and tokens | `secrets-setup.sh` |
| `~/.zshenv.local` | Environment variables | Template |
| `~/.config/git/allowed_signers` | SSH signing verification | `secrets-setup.sh` |

## Initial Setup

Run the interactive secrets wizard:

```bash
bash ~/dotfiles/scripts/secrets-setup.sh
```

This will guide you through setting up each credential file from templates.

## 1Password Integration

### SSH Key Management

If you use 1Password for SSH keys:

1. Enable SSH Agent in 1Password Settings > Developer
2. Run the secrets wizard — it will detect 1Password and configure the SSH agent
3. Your SSH config will point to the 1Password agent socket

### Commit Signing

1Password can sign git commits with your SSH key:

1. The secrets wizard configures `~/.gitconfig.local` with signing settings
2. It creates `~/.config/git/allowed_signers` for verification
3. All commits will be signed automatically

### CLI Authentication

```bash
# Sign in to 1Password CLI
op signin

# Use 1Password to inject secrets into commands
op run -- my-command
```

## Manual Setup

### Git Credentials

Create `~/.gitconfig.local`:
```ini
[user]
    name = Your Name
    email = your.email@example.com
    signingkey = ssh-ed25519 AAAA...

[gpg]
    format = ssh
[gpg "ssh"]
    program = "/Applications/1Password.app/Contents/MacOS/op-ssh-sign"
[commit]
    gpgsign = true
```

### SSH Keys

```bash
# Generate a new key
ssh-keygen -t ed25519 -C "your.email@example.com"

# Add to SSH agent with keychain
ssh-add --apple-use-keychain ~/.ssh/id_ed25519
```

### Shell Secrets

Create `~/.zsh_secrets`:
```bash
export GITHUB_TOKEN="ghp_xxxx"
export ANTHROPIC_API_KEY="sk-ant-xxxx"
```

Source it from `~/.zshrc.local`:
```bash
[[ -f ~/.zsh_secrets ]] && source ~/.zsh_secrets
```

## Security Best Practices

1. **File permissions** — Secret files should be mode 600: `chmod 600 ~/.zsh_secrets`
2. **Never commit** — Verify secrets are in `.gitignore`
3. **Use 1Password** — Prefer 1Password for key management over local files
4. **Rotate regularly** — Update API keys and tokens periodically
5. **Audit access** — Review `~/.ssh/config` and `~/.gitconfig.local` periodically

## Templates

Templates are stored in `~/dotfiles/templates/` and serve as documentation for what secrets are needed. They contain placeholder values only — never real credentials.

```bash
ls ~/dotfiles/templates/
# .zshenv.local.template
# gitconfig.local.template
# .ssh/config.template
```