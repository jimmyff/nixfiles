# LibreWolf Home Manager Configuration
# References:
# - LibreWolf module: https://raw.githubusercontent.com/nix-community/home-manager/refs/heads/master/modules/programs/librewolf.nix
# - Firefox module (LibreWolf is a Firefox fork): https://raw.githubusercontent.com/nix-community/home-manager/refs/heads/master/modules/programs/firefox/mkFirefoxModule.nix
{
  config,
  lib,
  pkgs,
  inputs,
  ...
}: {
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
          bookmarkhub
          proton-pass
          vimium
          darkreader
          ublock-origin
        ];

        search = {
          force = true;
          default = "DuckDuckGo Lite";
          engines = {
            "DuckDuckGo Lite" = {
              urls = [
                {
                  template = "https://lite.duckduckgo.com/lite/?q={searchTerms}";
                }
              ];
              icon = "https://duckduckgo.com/favicon.ico";
              definedAliases = ["@ddgl"];
            };

            "Startpage" = {
              urls = [
                {
                  template = "https://www.startpage.com/do/search?q={searchTerms}";
                }
              ];
              icon = "https://www.startpage.com/sp/cdn/favicons/favicon-96x96.png";
              definedAliases = ["@sp"];
            };

            "GitHub" = {
              urls = [
                {
                  template = "https://github.com/search?q={searchTerms}";
                }
              ];
              icon = "https://github.com/favicon.ico";
              definedAliases = ["@gh"];
            };

            "Nix Home Manager Options" = {
              urls = [
                {
                  template = "https://home-manager-options.extranix.com/?query={searchTerms}";
                }
              ];
              icon = "https://home-manager-options.extranix.com/favicon.ico";
              definedAliases = ["@hm"];
            };

            "Nix Packages" = {
              urls = [
                {
                  template = "https://search.nixos.org/packages";
                  params = [
                    {
                      name = "type";
                      value = "packages";
                    }
                    {
                      name = "query";
                      value = "{searchTerms}";
                    }
                  ];
                }
              ];
              icon = "https://search.nixos.org/favicon.png";
              definedAliases = ["@np"];
            };

            "NixOS Wiki" = {
              urls = [
                {
                  template = "https://nixos.wiki/index.php?search={searchTerms}";
                }
              ];
              icon = "https://nixos.wiki/favicon.png";
              definedAliases = ["@nw"];
            };

            "Nix Options" = {
              urls = [
                {
                  template = "https://search.nixos.org/options";
                  params = [
                    {
                      name = "channel";
                      value = "unstable";
                    }
                    {
                      name = "query";
                      value = "{searchTerms}";
                    }
                  ];
                }
              ];
              icon = "https://search.nixos.org/favicon.png";
              definedAliases = ["@no"];
            };

            google = {
              urls = [
                {
                  template = "https://www.google.com/search?q={searchTerms}";
                }
              ];
              icon = "https://www.google.com/favicon.ico";
              definedAliases = ["@g"];
            };

            "Searx" = {
              urls = [
                {
                  template = "https://searx.org/search?q={searchTerms}";
                }
              ];
              icon = "https://searx.org/static/themes/simple/img/favicon.png";
              definedAliases = ["@searx"];
            };

            "Wikipedia" = {
              urls = [
                {
                  template = "https://en.wikipedia.org/wiki/Special:Search?search={searchTerms}";
                }
              ];
              icon = "https://en.wikipedia.org/favicon.ico";
              definedAliases = ["@wiki"];
            };

            "Pub.dev" = {
              urls = [
                {
                  template = "https://pub.dev/packages?q={searchTerms}";
                }
              ];
              icon = "https://pub.dev/favicon.ico";
              definedAliases = ["@pub"];
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

          # Allow persistent logins - less aggressive cookie clearing
          "privacy.sanitize.sanitizeOnShutdown" = false;
          "privacy.clearOnShutdown.cache" = false;
          "privacy.clearOnShutdown.cookies" = false;
          "privacy.clearOnShutdown.sessions" = false;
          "network.cookie.lifetimePolicy" = 0;

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

          # Bookmarks toolbar - only show on new tab
          "browser.toolbars.bookmarks.visibility" = "newtab";

          # Enable vertical tabs
          "sidebar.verticalTabs" = true;
          "sidebar.collapsed" = true;

          # Dark theme
          "extensions.activeThemeID" = "firefox-compact-dark@mozilla.org";
          "ui.systemUsesDarkTheme" = true;
          "browser.theme.dark-private-windows" = true;

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

          # Auto-enable extensions
          "extensions.autoDisableScopes" = 0;

          # Hardware acceleration
          "media.ffmpeg.vaapi.enabled" = true;
          "layers.acceleration.force-enabled" = true;
          "gfx.webrender.all" = true;

          # Enable theme/dark mode switching
          "privacy.resistFingerprinting" = false;
          "privacy.fingerprintingProtection" = true;
          "privacy.fingerprintingProtection.overrides" = "+AllTargets,-CSSPrefersColorScheme";

          # Force default search engine
          "browser.search.defaultenginename" = "DuckDuckGo Lite";
        };
      };
    };
  };
}
