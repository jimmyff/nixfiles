{ pkgs, lib, config, ... }: {

    options = {
        vscode_module.enable = lib.mkEnableOption "enables vscode_module";
    };

    config = lib.mkIf config.vscode_module.enable {
        home.packages = [
            # pkgs.code-cursor
            pkgs.vscode
        ];

        # Darwin-specific: Create symlink from default VSCode location to dotfiles config
        # This ensures VSCode uses our managed configuration
        home.activation = lib.mkIf pkgs.stdenv.isDarwin {
            setupVSCodeSymlink = lib.hm.dag.entryAfter ["writeBoundary"] ''
                # Path to the default macOS VSCode config location
                VSCODE_DEFAULT_PATH="$HOME/Library/Application Support/Code/User"
                # Path to our dotfiles VSCode config
                VSCODE_DOTFILES_PATH="${config.home.homeDirectory}/nixfiles/dotfiles/vscode/.config/Code/User"
                
                echo "Setting up VSCode configuration symlink for Darwin..."
                
                # Create the Application Support/Code directory if it doesn't exist
                mkdir -p "$(dirname "$VSCODE_DEFAULT_PATH")"
                
                # Check if the default path already exists
                if [ -e "$VSCODE_DEFAULT_PATH" ] || [ -L "$VSCODE_DEFAULT_PATH" ]; then
                    # Check if it's already a symlink to our config
                    if [ -L "$VSCODE_DEFAULT_PATH" ] && [ "$(readlink "$VSCODE_DEFAULT_PATH")" = "$VSCODE_DOTFILES_PATH" ]; then
                        echo "VSCode symlink already correctly configured"
                    else
                        echo "Backing up existing VSCode config..."
                        # Create backup with timestamp
                        BACKUP_PATH="$VSCODE_DEFAULT_PATH.backup.$(date +%Y%m%d_%H%M%S)"
                        if ! mv "$VSCODE_DEFAULT_PATH" "$BACKUP_PATH"; then
                            echo "ERROR: Failed to backup existing VSCode config" >&2
                            exit 1
                        fi
                        echo "Existing config backed up to: $BACKUP_PATH"
                    fi
                fi
                
                # Remove any existing symlink or directory (if backup failed above, we'll error out)
                rm -rf "$VSCODE_DEFAULT_PATH" 2>/dev/null || true
                
                # Create the symlink
                echo "Creating symlink: $VSCODE_DEFAULT_PATH -> $VSCODE_DOTFILES_PATH"
                if ! ln -sf "$VSCODE_DOTFILES_PATH" "$VSCODE_DEFAULT_PATH"; then
                    echo "ERROR: Failed to create VSCode configuration symlink" >&2
                    exit 1
                fi
                
                # Verify the symlink was created correctly
                if [ ! -L "$VSCODE_DEFAULT_PATH" ] || [ "$(readlink "$VSCODE_DEFAULT_PATH")" != "$VSCODE_DOTFILES_PATH" ]; then
                    echo "ERROR: VSCode symlink verification failed" >&2
                    exit 1
                fi
                
                echo "Successfully configured VSCode symlink on Darwin"
            '';
        };
    };
}