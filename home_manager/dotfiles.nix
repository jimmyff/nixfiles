
{ pkgs, lib, config, ... }: {
    #home.file = {
    #    ".vimrc".source = ~/dotfiles/vim/.vimrc;
    #    ".bashrc".source = ~/dotfiles/bash/.bashrc;
    #};

    # vscode settings
    home.file.".config/Code/User/settings.json".source = config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/nixfiles/dotfiles/vscode/.config/Code/User/settings.json";
    home.file.".config/Code/User/keybindings.json".source = config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/nixfiles/dotfiles/vscode/.config/Code/User/keybindings.json";

    # cursor settings (vscode duplicated)
    home.file.".config/Cursor/User/settings.json".source = config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/nixfiles/dotfiles/vscode/.config/Code/User/settings.json";
    home.file.".config/Cursor/User/keybindings.json".source = config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/nixfiles/dotfiles/vscode/.config/Code/User/keybindings.json";



}
