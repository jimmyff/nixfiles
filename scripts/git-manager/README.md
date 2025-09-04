# gm.nu: Git Manager

**Author**: Jimmy Forrester-Fellowes (2025)

A Nushell script for managing Git repositories with submodules. Provides an intuitive interface for checking status, updating repositories, and committing changes across your entire repository ecosystem.

## Features

- **Three-state status system**: Clean, Dirty, and Updated repositories/submodules
- **Beautiful visual interface** with colors and progress indicators
- **Batch operations** for updating and committing multiple repositories
- **Dry-run mode** and comprehensive error handling

## Usage

### Quick Start

```bash
# Check status
nu gm.nu --status-only

# Interactive mode (recommended)
nu gm.nu

# Update everything automatically
nu gm.nu --update

# Preview operations
nu gm.nu --dry-run
```

### Status Display

```
🔄 Repository Status
┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄
Total: 8 | Clean: 6 | Dirty: 1 | Updated: 1

╭───┬───────────────────────────────┬────────────╮
│ # │          Repository           │   Status   │
├───┼───────────────────────────────┼────────────┤
│ 0 │ 📁 Main Project               │ ❌ DIRTY   │
│ 1 │ 📦 app                        │ ✅ CLEAN   │
│ 2 │ 📦 management                 │ 🔄 UPDATED │
│ 3 │ 📦 packages/osdn_core         │ ✅ CLEAN   │
╰───┴───────────────────────────────┴────────────╯
```

**Status Types:**
- **✅ CLEAN**: No changes, synchronized with parent
- **❌ DIRTY**: Has uncommitted changes that need to be committed
- **🔄 UPDATED**: Has new commits that the parent repository doesn't reference yet

### Interactive Mode

Default mode when run without flags. Choose from:
- **Update** (`u`): Pull latest changes for main repo and all submodules
- **Commit** (`c`): Commit dirty repositories and update parent references

### Command Options

```bash
# Work with specific path
nu gm.nu /path/to/repo --status-only

# Automated workflows
nu gm.nu --update          # Update all repos
nu gm.nu --update --force  # Skip confirmations

# Preview mode
nu gm.nu --dry-run         # Preview interactive operations
nu gm.nu --update --dry-run # Preview update operations
```

## Common Workflows

```bash
# Daily sync
nu gm.nu -s    # Check status
nu gm.nu -u    # Update everything

# Before making changes
nu gm.nu -s    # Ensure clean state
nu gm.nu       # Commit pending work (choose 'c')

# Preview operations
nu gm.nu -u -d # See what would be updated
```

## Troubleshooting

**"Repository has no submodules"** - Script works normally, operates on main repository only

**Update failures** - Check network connectivity and repository permissions

**Commit failures** - Verify git configuration (user.name, user.email) and push permissions

## Requirements

- **Nushell** (recent versions)
- **Git** (submodule support optional)
