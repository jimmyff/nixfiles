{
  pkgs-apps,
  lib,
  config,
  ...
}: {
  options = {
    thunderbird_module.enable = lib.mkEnableOption "Enable Thunderbird email client";
  };

  config = lib.mkIf config.thunderbird_module.enable {
    programs.thunderbird = {
      enable = true;
      package = pkgs-apps.thunderbird;
      # Set to null for darwin compatibility
      profileVersion =
        if pkgs-apps.stdenv.isDarwin
        then null
        else 2;

      # Global settings applied to all profiles
      settings = {
        # Privacy
        "privacy.donottrackheader.enabled" = true;
      };

      profiles.default = {
        isDefault = true;

        # Profile-specific settings
        settings = {
          # Compose settings
          "mail.identity.default.compose_html" = false; # Plain text by default
          "mail.SpellCheckBeforeSend" = true;
        };

        # Extensions can be added here
        # extensions = [ ];

        # Custom CSS can be added here
        # userChrome = "";
        # userContent = "";
      };
    };

    # Email accounts can be declared here using accounts.email.accounts
    # Example structure (uncomment and customize):
    #
    # accounts.email.accounts."personal" = {
    #   primary = true;
    #   address = "you@example.com";
    #   realName = "Your Name";
    #   userName = "you@example.com";
    #   imap = {
    #     host = "imap.example.com";
    #     port = 993;
    #   };
    #   smtp = {
    #     host = "smtp.example.com";
    #     port = 587;
    #   };
    #   thunderbird = {
    #     enable = true;
    #     profiles = [ "default" ];
    #   };
    # };
  };
}
