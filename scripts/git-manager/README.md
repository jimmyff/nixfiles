# gm.nu

**Author**: [Jimmy Forrester-Fellowes](https://jimmyff.com) (2025)

A Nushell script for managing Git repositories with submodules. Provides an intuitive interface for checking status, updating repositories, and committing changes.

## Usage

```bash
nu gm.nu                        # Interactive mode
nu gm.nu -s                     # Status only
nu gm.nu -p                     # Pull superproject + sync submodules to recorded refs
nu gm.nu -u                     # Pull latest on every submodule's branch
nu gm.nu -d                     # Dry-run (preview operations)
nu gm.nu /path/to/repo          # Specify repo path
```

**Interactive mode** presents `(p)ull`, `(u)pdate`, and `(c)ommit dirty` options.

## Features

- **Pull + sync**: Pull superproject and sync submodules to recorded refs (`-p`)
- **Update**: Advance all submodules to latest on their branch (`-u`)
- **Three-state status**: Clean, Dirty, Updated
- **Origin ahead/behind**: Shows `↑ahead ↓behind` per repo vs `origin/main`
- **Batch commit**: Commit dirty submodules and update parent refs
- **Dry-run mode**: Preview operations before executing

## Example Output

```
🔄 Repository Status
Total: 8 | Clean: 6 | Dirty: 1 | Updated: 1

╭───┬──────────────────────┬────────────┬────────╮
│ # │      Repository      │   Status   │ Origin │
├───┼──────────────────────┼────────────┼────────┤
│ 0 │ 📁 Main Project      │ ✅ CLEAN   │ ↑0 ↓0  │
│ 1 │ 📦 app               │ ❌ DIRTY   │ ↑1 ↓0  │
│ 2 │ 📦 lib               │ 🔄 UPDATED │ ↑0 ↓2  │
╰───┴──────────────────────┴────────────┴────────╯
```

**Status Types:**
- **✅ CLEAN**: No changes, synchronized with parent
- **❌ DIRTY**: Has uncommitted changes
- **🔄 UPDATED**: Has new commits the parent doesn't reference yet

## Requirements

- Nushell
- Git (submodule support optional)