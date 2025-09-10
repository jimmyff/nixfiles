# LibreWolf Home Manager Configuration
# References:
# - LibreWolf module: https://raw.githubusercontent.com/nix-community/home-manager/refs/heads/master/modules/programs/librewolf.nix
# - Firefox module (LibreWolf is a Firefox fork): https://raw.githubusercontent.com/nix-community/home-manager/refs/heads/master/modules/programs/firefox/mkFirefoxModule.nix

{ config, lib, pkgs, inputs, ... }:

{
  options = {
    librewolf_module.enable = lib.mkEnableOption "Enable LibreWolf browser configuration";
  };

  config = lib.mkIf config.librewolf_module.enable {
    home.sessionVariables.BROWSER = "librewolf";
    
    programs.librewolf = {
      enable = true;
      
      profiles.jimmyff = {
        id = 0;
        isDefault = true;
        
        extensions.packages = with inputs.nur.legacyPackages.${pkgs.system}.repos.rycee.firefox-addons; [
          bitwarden
          # bookmarkhub not available in NUR
          proton-pass
          vimium
          darkreader
          ublock-origin
        ];

        search = {
          force = true;
          default = "ddg";
          engines = {
            "Nix Packages" = {
              urls = [{
                template = "https://search.nixos.org/packages";
                params = [
                  { name = "type"; value = "packages"; }
                  { name = "query"; value = "{searchTerms}"; }
                ];
              }];
              icon = "''${pkgs.nixos-icons}/share/icons/hicolor/scalable/apps/nix-snowflake.svg";
              definedAliases = [ "@np" ];
            };

            "NixOS Wiki" = {
              urls = [{
                template = "https://nixos.wiki/index.php?search={searchTerms}";
              }];
              icon = "https://nixos.wiki/favicon.png";
              definedAliases = [ "@nw" ];
            };

            "Nix Options" = {
              urls = [{
                template = "https://search.nixos.org/options";
                params = [
                  { name = "channel"; value = "unstable"; }
                  { name = "query"; value = "{searchTerms}"; }
                ];
              }];
              icon = "''${pkgs.nixos-icons}/share/icons/hicolor/scalable/apps/nix-snowflake.svg";
              definedAliases = [ "@no" ];
            };

            google = {
              urls = [{
                template = "https://www.google.com/search?q={searchTerms}";
              }];
              icon = "https://www.google.com/favicon.ico";
              definedAliases = [ "@g" ];
            };

            "Searx" = {
              urls = [{
                template = "https://searx.org/search?q={searchTerms}";
              }];
              icon = "https://searx.org/static/themes/oscar/img/favicon.png";
              definedAliases = [ "@searx" ];
            };

            bing.metaData.hidden = true;
          };
        };

        settings = {
          # Privacy and security settings from example config
          "privacy.trackingprotection.enabled" = true;
          "privacy.trackingprotection.socialtracking.enabled" = true;
          "privacy.partition.network_state" = false;
          "privacy.history.custom" = true;
          "browser.privatebrowsing.autostart" = false;
          
          # Search and navigation
          "browser.search.suggest.enabled" = false;
          "browser.search.suggest.enabled.private" = false;
          "browser.urlbar.suggest.searches" = false;
          "browser.urlbar.showSearchSuggestionsFirst" = false;
          
          # Performance settings
          "browser.sessionstore.warnOnQuit" = false;
          "browser.tabs.warnOnClose" = false;
          "browser.warnOnQuit" = false;
          
          # UI preferences
          "browser.compactmode.show" = true;
          "browser.uidensity" = 1;
          
          # Downloads
          "browser.download.useDownloadDir" = false;
          "browser.download.dir" = "~/Downloads";
          
          # Disable telemetry and data collection
          "datareporting.healthreport.uploadEnabled" = false;
          "datareporting.policy.dataSubmissionEnabled" = false;
          "toolkit.telemetry.enabled" = false;
          "toolkit.telemetry.unified" = false;
          
          # Set startup homepage to blank page
          "browser.startup.homepage" = "about:blank";
        };
      };
    };
  };
}