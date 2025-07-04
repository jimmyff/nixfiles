{ inputs, config, pkgs, ... }:

{

  imports = [
    inputs.catppuccin.homeModules.catppuccin
  ];

  # Home Manager needs a bit of information about you and the paths it should
  # manage.
  home.username = "jimmyff";
  home.homeDirectory = "/home/jimmyff";

  # This value determines the Home Manager release that your configuration is
  # compatible with. This helps avoid breakage when a new Home Manager release
  # introduces backwards incompatible changes.
  #
  # You should not change this value, even if you update Home Manager. If you do
  # want to update the value, then make sure to first check the Home Manager
  # release notes.
  home.stateVersion = "25.05"; # Please read the comment before changing.


  # The home.packages option allows you to install Nix packages into your
  # environment.
  home.packages = [
    # # Adds the 'hello' command to your environment. It prints a friendly
    # # "Hello, world!" when run.
    # pkgs.hello

    pkgs.chromium			# browser			
    pkgs.google-chrome		# browser
    pkgs.bitwarden-desktop		# vault

    pkgs.fuzzel			                  # launcher (niri)
    pkgs.wofi                         # launcher (sway)
    pkgs.mako				                  # notifications
    pkgs.wl-clipboard                 # clipboard
    pkgs.nautilus			                # file manager
    pkgs.font-awesome		              # font icons
    pkgs.nerd-fonts.jetbrains-mono    # font
    pkgs.slurp                        # screenshots
    pkgs.grim                         # screenshots

    pkgs.code-cursor		              # ide
    pkgs.ghostty                      # term
    pkgs.neofetch                     # info


    pkgs.catppuccin-gtk # theme
    pkgs.bemoji
    pkgs.playerctl
    pkgs.wl-clipboard
    pkgs.wdisplays

    # # It is sometimes useful to fine-tune packages, for example, by applying
    # # overrides. You can do that directly here, just don't forget the
    # # parentheses. Maybe you want to install Nerd Fonts with a limited number of
    # # fonts?
    # (pkgs.nerdfonts.override { fonts = [ "FantasqueSansMono" ]; })

    # # You can also create simple shell scripts directly inside your
    # # configuration. For example, this adds a command 'my-hello' to your
    # # environment:
    # (pkgs.writeShellScriptBin "my-hello" ''
    #   echo "Hello, ${config.home.username}!"
    # '')
  ];

  programs.git = {
    enable = true;
    userName = "jimmyff";
    userEmail = "code@rocketware.co.uk";
  };

  programs.btop = {
    enable = true;
    settings = {
      #color_theme = "HotPurpleTrafficLight";
      vim_keys = true;
    };
  };

  # sway
  home.pointerCursor = {
    package = pkgs.bibata-cursors;
    name = "Bibata-Modern-Ice";
    size = 22;
    gtk.enable = true;
  };
  
    

  programs.rofi = {
    enable = true;
    package = pkgs.rofi-wayland;
    terminal = "${pkgs.ghostty}/bin/";

    extraConfig = {
      modi = "drun";
      show-icons = true;
      drun-display-format = "{icon} {name}";
      disable-history = false;
      hide-scrollbar = true;
      display-drun = "   Apps ";
      sidebar-mode = true;
    };
  };

  # Home Manager is pretty good at managing dotfiles. The primary way to manage
  # plain files is through 'home.file'.
  home.file = {
    # # Building this configuration will create a copy of 'dotfiles/screenrc' in
    # # the Nix store. Activating the configuration will then make '~/.screenrc' a
    # # symlink to the Nix store copy.
    # ".screenrc".source = dotfiles/screenrc;

    # # You can also set the file content immediately.
    # ".gradle/gradle.properties".text = ''
    #   org.gradle.console=verbose
    #   org.gradle.daemon.idletimeout=3600000
    # '';
  };

  # Home Manager can also manage your environment variables through
  # 'home.sessionVariables'. These will be explicitly sourced when using a
  # shell provided by Home Manager. If you don't want to manage your shell
  # through Home Manager then you have to manually source 'hm-session-vars.sh'
  # located at either
  #
  #  ~/.nix-profile/etc/profile.d/hm-session-vars.sh
  #
  # or
  #
  #  ~/.local/state/nix/profiles/profile/etc/profile.d/hm-session-vars.sh
  #
  # or
  #
  #  /etc/profiles/per-user/jimmyff/etc/profile.d/hm-session-vars.sh
  #
  
  home.sessionVariables = {
    BROWSER = "google-chrome-stable";
    EDITOR = "nvim";
    TERMINAL = "ghostty";
  };

  # Let Home Manager install and manage itself.
  programs.home-manager.enable = true;
}
