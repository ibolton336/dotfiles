# Architecture Guide

How the dotfiles bootstrap system works and the design decisions behind it.

## System Overview

```
~/dotfiles/
├── bootstrap/             # Automated migration system
│   ├── bootstrap.sh       # Main entry point and orchestrator
│   ├── lib/
│   │   ├── logging.sh     # Colored output, progress, spinners
│   │   └── error-handling.sh  # Error recovery, state, resume
│   └── phases/            # Modular installation scripts (01-09)
│       ├── 01-preflight.sh
│       ├── 02-homebrew.sh
│       ├── 03-system-tools.sh
│       ├── 04-dotfiles-setup.sh
│       ├── 05-dev-tools.sh
│       ├── 06-vim-setup.sh
│       ├── 07-app-installs.sh
│       ├── 08-shell-setup.sh
│       └── 09-postflight.sh
├── manifests/             # Declarative dependency lists
│   ├── brewfile           # Homebrew packages
│   ├── npm-global.txt     # Global npm packages
│   ├── app-store-apps.txt # Mac App Store apps
│   ├── versions.txt       # Pinned tool versions
│   ├── shell-completions.txt
│   └── extensions/
│       ├── vscode.txt     # VS Code extensions
│       └── cursor.txt     # Cursor extensions
├── templates/             # Credential file templates
│   ├── .zshenv.local.template
│   ├── gitconfig.local.template
│   └── .ssh/config.template
├── scripts/               # Standalone utility scripts
│   ├── secrets-setup.sh   # Interactive credential wizard
│   ├── mac-defaults.sh    # macOS system preferences
│   └── verify-install.sh  # Post-install verification
├── docs/                  # Documentation
├── bin/                   # Shell scripts added to PATH
├── hooks/                 # RCM lifecycle hooks
│   └── post-up            # Runs after rcup
├── zsh/                   # Zsh configuration modules
│   ├── configs/           # Modular zsh settings
│   ├── functions/         # Custom shell functions
│   └── completion/        # Zsh completions
├── vim/                   # Vim filetype and plugin configs
├── git_template/          # Git template hooks
└── [dotfiles]             # Root-level config files (zshrc, vimrc, etc.)
```

## Design Principles

### 1. Preserve Existing Patterns

The bootstrap system is an addition, not a replacement. The existing thoughtbot-based dotfiles continue to work exactly as before. RCM symlink management, local overrides via `~/dotfiles-local/`, and the `hooks/post-up` workflow are all preserved.

### 2. Modular Phases

Each bootstrap phase is a standalone script that can run independently:

```bash
bash ~/dotfiles/bootstrap/bootstrap.sh --phase 02-homebrew
```

Phases are ordered by dependency — Homebrew must be installed before dev tools, dotfiles must be symlinked before vim plugins. But each phase is self-contained and can be debugged in isolation.

### 3. Declarative Manifests

Dependencies are declared in plain text files under `manifests/`, not embedded in shell scripts. This makes it easy to review what's being installed, add or remove packages, and track changes in version control.

### 4. State and Resume

Bootstrap state is stored in `~/.cache/dotfiles-bootstrap/bootstrap-state.json`. If the process is interrupted, you can resume from the last incomplete phase:

```bash
bash ~/dotfiles/bootstrap/bootstrap.sh --resume
```

A lock file prevents concurrent runs. State tracks completed phases, failed phases, and backup locations.

### 5. Secrets Stay Local

Credentials never enter the repository. The `templates/` directory provides skeleton files. The `scripts/secrets-setup.sh` wizard guides users through creating local credential files (`~/.gitconfig.local`, `~/.ssh/config`, `~/.zsh_secrets`).

## How RCM Works

RCM (RC file Management) creates symlinks from your home directory to files in the dotfiles repository.

**Configuration** (`~/.rcrc`):
- `DOTFILES_DIRS` — directories to source dotfiles from (local overrides take precedence)
- `EXCLUDES` — files/directories to skip (README, LICENSE, bootstrap, manifests, docs)
- `COPY_ALWAYS` — files to copy instead of symlink

**Commands:**
- `rcup` — create/update symlinks
- `rcdn` — remove symlinks
- `lsrc` — list what rcup would do

**Local Override Pattern:**
`~/dotfiles-local/` takes precedence over `~/dotfiles/`. Files like `zshrc.local` are sourced at the end of their parent files, allowing customization without modifying the shared repository.

## Phase Execution Flow

```
bootstrap.sh
  ├── Parse arguments
  ├── Source lib/logging.sh
  ├── Source lib/error-handling.sh
  ├── Initialize state management
  ├── Check system requirements
  ├── Get phases to run (all, resume, or specific)
  └── For each phase:
      ├── Check if already completed (skip in resume mode)
      ├── Set current phase in state
      ├── Execute phase script
      ├── Mark completed or failed
      └── Handle errors (offer continue/stop)
```

## Error Handling

The error handling system provides:

- **ERR trap** — catches any command failure and logs context
- **INT/TERM trap** — handles Ctrl+C gracefully
- **Lock file** — prevents concurrent bootstrap runs
- **Error reports** — detailed logs saved to `~/.cache/dotfiles-bootstrap/`
- **Retry with backoff** — `retry_command` for flaky network operations
- **Backup/restore** — backs up existing files before replacing them

## Shell Configuration Loading Order

```
Login shell starts
  → ~/.zshenv          (environment variables, always loaded)
  → ~/.zshrc           (interactive shell configuration)
       ├── Load ~/.zsh/functions/*
       ├── Load ~/.zsh/configs/pre/*     (early overrides)
       ├── Load ~/.zsh/configs/*         (main config modules)
       ├── Load ~/.zsh/configs/post/*    (late config, PATH, completions)
       ├── Load ~/.zshrc.local           (user overrides)
       ├── Load ~/.aliases               (shared aliases)
       └── Load ~/.fzf.zsh              (fzf integration)
```

## File Ownership

| Location | Purpose | Committed to Git? |
|---|---|---|
| `~/dotfiles/` | Shared dotfiles (this repo) | Yes |
| `~/dotfiles-local/` | Personal overrides | Your choice |
| `~/.gitconfig.local` | Personal git settings | No |
| `~/.zshrc.local` | Personal shell config | No |
| `~/.zsh_secrets` | API keys and tokens | Never |
| `~/.ssh/config` | SSH configuration | Never |
| `~/.cache/dotfiles-bootstrap/` | Bootstrap state | Never |