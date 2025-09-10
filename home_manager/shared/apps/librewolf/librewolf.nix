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

      policies = {
        ExtensionSettings = {
          # BookmarkHub
          "{9c37f9a3-ea04-4a2b-9fcc-c7a814c14311}" = {
            install_url = "https://addons.mozilla.org/firefox/downloads/file/3815080/bookmarkhub-0.0.4.xpi";
            installation_mode = "force_installed";
            default_area = "menupanel";
          };
          # Bitwarden Password Manager
          "{446900e4-71c2-419f-a6a7-df9c091e268b}" = {
            install_url = "https://addons.mozilla.org/firefox/downloads/file/4567044/bitwarden_password_manager-2025.8.2.xpi";
            installation_mode = "force_installed";
            default_area = "menupanel";
          };
          # Proton Pass
          "78272b6fa58f4a1abaac99321d503a20@proton.me" = {
            install_url = "https://addons.mozilla.org/firefox/downloads/file/4567405/proton_pass-1.32.5.xpi";
            installation_mode = "force_installed";
            default_area = "menupanel";
          };
          # Vimium
          "{d7742d87-e61d-4b78-b8a1-b469842139fa}" = {
            install_url = "https://addons.mozilla.org/firefox/downloads/file/4524018/vimium_ff-2.3.xpi";
            installation_mode = "force_installed";
            default_area = "menupanel";
          };
          # Dark Reader
          "addon@darkreader.org" = {
            install_url = "https://addons.mozilla.org/firefox/downloads/file/4535824/darkreader-4.9.110.xpi";
            installation_mode = "force_installed";
            default_area = "menupanel";
          };
          # uBlock Origin
          "uBlock0@raymondhill.net" = {
            install_url = "https://addons.mozilla.org/firefox/downloads/file/4531307/ublock_origin-1.65.0.xpi";
            installation_mode = "force_installed";
            default_area = "menupanel";
          };
        };
      };
      
      profiles.jimmyff = {
        id = 0;
        isDefault = true;

        search = {
          force = true;
          default = "Searx";
          engines = {
            "Nix Packages" = {
              urls = [{
                template = "https://search.nixos.org/packages";
                params = [
                  { name = "type"; value = "packages"; }
                  { name = "query"; value = "{searchTerms}"; }
                ];
              }];
              icon = "https://search.nixos.org/favicon.png";
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
              icon = "https://search.nixos.org/favicon.png";
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
              icon = "https://searx.org/static/themes/simple/img/favicon.png";
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
          
          # Enable vertical tabs
          "sidebar.verticalTabs" = true;
          "sidebar.collapsed" = true;
          
          # Dark theme
          "extensions.activeThemeID" = "firefox-compact-dark@mozilla.org";
          
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
          
          # Set new tab page to blank
          "browser.newtabpage.enabled" = false;
        };
      };
    };
  };
}