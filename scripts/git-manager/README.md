# gm.nu

**Author**: [Jimmy Forrester-Fellowes](https://jimmyff.com) (2025)

A Nushell script for managing Git repositories with submodules. Provides an intuitive interface for checking status, updating repositories, and committing changes.

## Usage

```bash
# Check status only
nu gm.nu --status-only
nu gm.nu -s

# Run operations
nu gm.nu --update               # Update all repos
nu gm.nu --dry-run              # Preview operations

# Interactive mode (choose operation)
nu gm.nu
nu gm.nu /path/to/repo
```

## Features

- **Three-state status system**: Clean, Dirty, and Updated repositories/submodules
- **Batch operations**: Update and commit multiple repositories at once
- **Visual progress**: Shows real-time progress with success/error status
- **Dry-run mode**: Preview operations before executing

## Example Output

```
🔄 Repository Status
Total: 8 | Clean: 6 | Dirty: 1 | Updated: 1

╭───┬───────────────────────────────┬────────────╮
│ # │          Repository           │   Status   │
├───┼───────────────────────────────┼────────────┤
│ 0 │ 📁 Main Project               │ ❌ DIRTY   │
│ 1 │ 📦 app                        │ ✅ CLEAN   │
│ 2 │ 📦 management                 │ 🔄 UPDATED │
╰───┴───────────────────────────────┴────────────╯
```

**Status Types:**
- **✅ CLEAN**: No changes, synchronized with parent
- **❌ DIRTY**: Has uncommitted changes that need to be committed  
- **🔄 UPDATED**: Has new commits that the parent repository doesn't reference yet

## Requirements

- Nushell
- Git (submodule support optional)