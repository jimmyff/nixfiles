{
  pkgs,
  username,
  ...
}:
let
  nixPaths = [
    "/Users/${username}/.nix-profile/bin"
    "/etc/profiles/per-user/${username}/bin"
    "/run/current-system/sw/bin"
    "/nix/var/nix/profiles/default/bin"
    "/Users/${username}/.local/bin"
    "/Users/${username}/.cache/dart-pub/bin" # FlutterFire CLI for Xcode build phases
  ];
  systemPaths = [
    "/usr/local/bin"
    "/usr/bin"
    "/bin"
    "/usr/sbin"
    "/sbin"
  ];
in {
  imports = [
    ../shared/core.nix
    ../shared/apps.nix
    ../users_darwin.nix
    ../shared/ssh.nix
    ./ssh.nix
    ../shared/fonts.nix
    ../shared/stow.nix
    ./homebrew.nix
  ];

  nixpkgs.hostPlatform = "aarch64-darwin";
  system.primaryUser = username;

  # Optimise store
  nix.optimise.automatic = true;

  # Garbage collection
  nix.gc = {
    automatic = true;
    interval = {
      Weekday = 0;
      Hour = 0;
      Minute = 0;
    };
    options = "--delete-older-than 7d";
  };

  system = {
    stateVersion = 6;
  };

  # Add ability to used TouchID for sudo authentication
  security.pam.services.sudo_local.touchIdAuth = true;

  # Create /etc/zshrc that loads the nix-darwin environment.
  # this is required if you want to use darwin's default shell - zsh
  programs.zsh.enable = true;

  # Set up environment variables for GUI applications via launchd
  # This ensures GUI apps like VS Code inherit the proper PATH from Nix
  # Lists are automatically concatenated with colons (:)
  launchd.user.envVariables = {
    PATH = nixPaths ++ [ "$PATH" ];
  };

  # Persist PATH across reboots via login agent (envVariables only applies at switch time)
  launchd.user.agents.nix-env-path = {
    serviceConfig = {
      RunAtLoad = true;
      ProgramArguments = [
        "/bin/sh"
        "-c"
        "/bin/launchctl setenv PATH '${builtins.concatStringsSep ":" (nixPaths ++ systemPaths)}'"
      ];
    };
  };
}
