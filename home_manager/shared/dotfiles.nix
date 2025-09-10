
{ pkgs, lib, config, ... }: 
let
  dotfilesPath = "${config.home.homeDirectory}/nixfiles/dotfiles";
in {
  home.activation.dotfileSymlinks = lib.mkAfter ''
    # Function to safely create directory symlinks
    safe_symlink() {
      local source="$1"
      local target="$2"
      
      # ANSI color codes
      local RED='\033[0;31m'
      local YELLOW='\033[1;33m'
      local GREEN='\033[0;32m'
      local NC='\033[0m' # No Color
      
      # Store raw target path for dotfiles check before resolution
      local target_raw="$target"
      
      # Resolve absolute paths to prevent issues
      source=$(realpath "$source")
      target=$(realpath -m "$target")  # -m allows non-existent target
      
      # Validate source exists
      if [ ! -d "$source" ]; then
        echo -e "''${RED}🚨 ERROR: Source directory $source does not exist''${NC}"
        exit 1
      fi
      
      # Prevent symlinks inside dotfiles directory (use raw path)
      if [[ "$target_raw" == *"/dotfiles/"* ]]; then
        echo -e "''${RED}🚨 ERROR: Cannot create symlinks inside dotfiles directory: $target_raw''${NC}"
        exit 1
      fi
      
      # Check if target exists and handle appropriately (use raw path)
      if [ -e "$target_raw" ] && [ ! -L "$target_raw" ]; then
        echo -e "''${RED}🚨 ERROR: $target_raw already exists and is not a symlink. Please remove it manually.''${NC}"
        exit 1
      elif [ -L "$target_raw" ] && [ "$(readlink "$target_raw")" != "$source" ]; then
        echo -e "''${YELLOW}⚠️  WARNING: $target_raw points to $(readlink "$target_raw"), updating to $source''${NC}"
        rm "$target_raw"
      fi
      
      # Create parent directory and symlink (use raw path)
      mkdir -p "$(dirname "$target_raw")"
      ln -sfn "$source" "$target_raw"
      echo -e "''${GREEN}✅ Linked $source -> $target_raw''${NC}"
    }
    
    # Create directory symlinks
    safe_symlink ${dotfilesPath}/vscode/.config/Code ~/.config/Code
    safe_symlink ${dotfilesPath}/zed/.config/zed ~/.config/zed
    safe_symlink ${dotfilesPath}/ghostty/.config/ghostty ~/.config/ghostty
    safe_symlink ${dotfilesPath}/zellij/.config/zellij ~/.config/zellij
    safe_symlink ${dotfilesPath}/aerospace ~/.config/aerospace
    
    # Conditional desktop environment configs
    if [ -d "${dotfilesPath}/cosmic/.config/cosmic" ]; then
      safe_symlink ${dotfilesPath}/cosmic/.config/cosmic ~/.config/cosmic
    fi
  '';
}
