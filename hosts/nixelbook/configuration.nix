# Edit this configuration file to define what should be installed on
# your system.  Help is available in the configuration.nix(5) man page
# and in the NixOS manual (accessible by running ‘nixos-help’).

{ config, pkgs, lib, inputs, ... }:

{
  imports =
    [ # Include the results of the hardware scan.
      ./hardware-configuration.ni
      inputs.home-manager.nixosModules.desktop.defaultx
      inputs.home-manager.nixosModules.apps.default
    ];

  # Bootloader.
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;
  boot.loader.systemd-boot.configurationLimit = 16;

  nix = {
    settings.auto-optimise-store = true;
    settings.experimental-features = "nix-command flakes";
   	gc = {
      automatic = true;
      dates = "weekly";
      options = "--delete-older-than 30d";
    };
  };
  

  networking.hostName = "nixelbook"; # Define your hostname.
  networking.networkmanager.enable = true;

  # Set your time zone.
  time.timeZone = "Europe/London";

  # Select internationalisation properties.
  i18n.defaultLocale = "en_GB.UTF-8";

  i18n.extraLocaleSettings = {
    LC_ADDRESS = "en_GB.UTF-8";
    LC_IDENTIFICATION = "en_GB.UTF-8";
    LC_MEASUREMENT = "en_GB.UTF-8";
    LC_MONETARY = "en_GB.UTF-8";
    LC_NAME = "en_GB.UTF-8";
    LC_NUMERIC = "en_GB.UTF-8";
    LC_PAPER = "en_GB.UTF-8";
    LC_TELEPHONE = "en_GB.UTF-8";
    LC_TIME = "en_GB.UTF-8";
  };

  
  # Used for sway/niri: move
  programs.niri.enable = true;
  programs.sway = {
    enable = true;
    wrapperFeatures.gtk = true;
  };
  security.polkit.enable = true;


  # allows sandboxed apps to access resources
  xdg.portal = {
    enable = true;
    xdgOpenUsePortal = true;
    extraPortals = [ 
      pkgs.xdg-desktop-portal-gtk	  # Standard handler
      pkgs.
      pkgs.gnome-keyring		        # niri: for some apps
    ];
  };

  # Touchpad support
  services.libinput = {
    enable = true;
    mouse.naturalScrolling = true;
    touchpad.naturalScrolling = true;  
  };


  # Enable CUPS to print documents.
  services.printing.enable = true;

  # Enable sound with pipewire.
  services.pulseaudio.enable = false;
  security.rtkit.enable = true;
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
    # If you want to use JACK applications, uncomment this
    #jack.enable = true;

    # use the example session manager (no others are packaged yet so this is enabled by default,
    # no need to redefine it in your config for now)
    #media-session.enable = true;
  };

  # gnome secrets vault
  services.gnome.gnome-keyring.enable = true;

  

  # Users
  home-manager.useGlobalPkgs = true;

  # Define a user account. Don't forget to set a password with ‘passwd’.
  users.users.jimmyff = {
    isNormalUser = true;
    description = "Jimmy Forrester-Fellowes";
    extraGroups = [ "networkmanager" "wheel" ];
  };
  
  
  
  home-manager = {
    # pass inputs to home-manager modules
    extraSpecialArgs = { inherit inputs; };
    users = {
      "jimmyff" = import ./home.nix;
    };
    
    sharedModules = [(
      inputs.self.outputs.homeManagerModules.default
    )];

  };


  # fonts to move
  fonts.packages = with pkgs; [
    nerd-fonts.fira-code
    nerd-fonts.droid-sans-mono
    nerd-fonts.noto
    nerd-fonts.hack
    nerd-fonts.jetbrains-mono
  ];

  
  # Allow unfree packages
  nixpkgs.config.allowUnfree = true;


  environment = {
    sessionVariables = {
      NIXOS_OZONE_WL = "1"; # Wayland support for chromium based apps
    };
  };

  programs.gnupg.agent = {
    enable = true;
    enableSSHSupport = true;
  };

  # List packages installed in system profile. To search, run:
  # $ nix search wget
  environment.systemPackages = with pkgs; [
    unzip
    wget
    neovim

  ];

  # Some programs need SUID wrappers, can be configured further or are
  # started in user sessions.
  # programs.mtr.enable = true;


  # List services that you want to enable:

  # Enable the OpenSSH daemon.
  #services.openssh.enable = true;

  # Open ports in the firewall.
  # networking.firewall.allowedTCPPorts = [ ... ];
  # networking.firewall.allowedUDPPorts = [ ... ];
  # Or disable the firewall altogether.
  # networking.firewall.enable = false;


  # Power management
  powerManagement.enable = true;
  services.tlp.enable = true;


  # This value determines the NixOS release from which the default
  # settings for stateful data, like file locations and database versions
  # on your system were taken. It‘s perfectly fine and recommended to leave
  # this value at the release version of the first install of this system.
  # Before changing this value read the documentation for this option
  # (e.g. man configuration.nix or on https://nixos.org/nixos/options.html).
  system.stateVersion = "25.05"; # Did you read the comment?

}
