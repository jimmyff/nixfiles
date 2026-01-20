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

          # OpenPGP settings
          "mail.identity.default.attachPgpKey" = true; # Attach public key to signed messages
          "mail.identity.default.protectSubject" = true; # Encrypt subject line
          "mail.e2ee.auto_enable" = true; # Auto-enable encryption when possible
          "mail.e2ee.notify_on_auto_disable" = true; # Notify when encryption disabled
        };

        # Extensions can be added here
        # extensions = [ ];

        # Custom CSS can be added here
        # userChrome = "";
        # userContent = "";
      };
    };

    # Accounts configured manually in Thunderbird (not declaratively)
    # due to "managed by organisation" lockdown preventing password entry
  };
}
