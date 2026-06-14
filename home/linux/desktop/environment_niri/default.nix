{ pkgs, pkgs-desktop, lib, config, ... }:

let
  # niri is a system package (programs.niri); reference its stable binary by
  # the system profile path so swayidle/scripts use the same niri as the session.
  niri = "/run/current-system/sw/bin/niri";

  # Power menu (ported from the sway tofi-power-menu): fuzzel --dmenu front-end,
  # niri's own quit action for Logout.
  niriPowerMenu = pkgs-desktop.writeScriptBin "niri-power-menu" ''
    #!${pkgs-desktop.nushell}/bin/nu

    let options = [ "Lock" "Sleep" "Reboot" "Logout" "Shutdown" ]

    try {
        let chosen = ($options | str join "\n" | ${pkgs.fuzzel}/bin/fuzzel --dmenu --prompt "⏻ ")

        match $chosen {
            "Lock" => { ${pkgs.swaylock}/bin/swaylock -f }
            "Sleep" => { ${pkgs.systemd}/bin/systemctl suspend }
            "Reboot" => { ${pkgs.systemd}/bin/systemctl reboot }
            "Logout" => { ${niri} msg action quit }
            "Shutdown" => { ${pkgs.systemd}/bin/systemctl poweroff }
        }
    }
  '';
in
{
  imports = [
    ./waybar/waybar.nix
  ];

  # Whole env is dead on headless hosts (desktop.enable is false there).
  config = lib.mkIf config.desktop.enable {

    # Cursor
    home.pointerCursor = {
      package = pkgs-desktop.bibata-cursors;
      name = "Bibata-Modern-Ice";
      size = 22;
      gtk.enable = true;
    };

    # niri config — live-editable symlink (matches the cosmic env + the repo's
    # "live symlinks" philosophy; niri reloads config.kdl on save).
    home.file.".config/niri/config.kdl".source =
      config.lib.file.mkOutOfStoreSymlink
        "${config.home.homeDirectory}/nixfiles/dotfiles/niri/config.kdl";

    # Notifications — SwayNotificationCenter (popups + control-center panel).
    # Toggle panel: Mod+N; toggle Do-Not-Disturb: Mod+Shift+N (niri binds).
    # Waybar shows an unread/DND indicator (custom/notification module).
    services.swaync = {
      enable = true;
      style = ./swaync/style.css;
      settings = {
        positionX = "right";
        positionY = "top";
        layer = "overlay";
        control-center-layer = "top";
        cssPriority = "user";
        control-center-width = 400;
        control-center-margin-top = 8;
        control-center-margin-bottom = 8;
        control-center-margin-right = 8;
        control-center-margin-left = 8;
        notification-window-width = 400;
        notification-icon-size = 48;
        notification-body-image-height = 160;
        notification-body-image-width = 220;
        timeout = 6;          # normal urgency (seconds)
        timeout-low = 4;
        timeout-critical = 0; # critical stays until dismissed
        fit-to-screen = true;  # full-height side panel (control-center-height ignored)
        keyboard-shortcuts = true;
        image-visibility = "when-available";
        transition-time = 200;
        hide-on-clear = false;
        hide-on-action = true;
        widgets = [ "title" "dnd" "notifications" ];
        widget-config = {
          title = {
            text = "Notifications";
            clear-all-button = true;
            button-text = "Clear all";
          };
          dnd.text = "Do not disturb";
          notifications.vexpand = true;
        };
      };
    };

    # Polkit authentication agent (system enables security.polkit + PAM).
    services.polkit-gnome.enable = true;

    # Screen lock (Catppuccin theme, ported from environment_sway/sway/config_swaylock).
    programs.swaylock = {
      enable = true;
      settings = {
        font = "JetBrainsMono Nerd Font";
        font-size = 14;
        color = "1e1e2e";
        bs-hl-color = "f5e0dc";
        caps-lock-bs-hl-color = "f5e0dc";
        caps-lock-key-hl-color = "a6e3a1";
        inside-color = "00000000";
        inside-clear-color = "00000000";
        inside-caps-lock-color = "00000000";
        inside-ver-color = "00000000";
        inside-wrong-color = "00000000";
        key-hl-color = "a6e3a1";
        layout-bg-color = "00000000";
        layout-border-color = "00000000";
        layout-text-color = "cdd6f4";
        line-color = "00000000";
        line-clear-color = "00000000";
        line-caps-lock-color = "00000000";
        line-ver-color = "00000000";
        line-wrong-color = "00000000";
        ring-color = "b4befe";
        ring-clear-color = "f5e0dc";
        ring-caps-lock-color = "fab387";
        ring-ver-color = "89b4fa";
        ring-wrong-color = "eba0ac";
        separator-color = "00000000";
        text-color = "cdd6f4";
        text-clear-color = "f5e0dc";
        text-caps-lock-color = "fab387";
        text-ver-color = "89b4fa";
        text-wrong-color = "eba0ac";
      };
    };

    # Idle: lock on idle, then blank monitors; lock before sleep.
    # Lock must precede power-off — niri needs monitors on to blank the lock frame.
    services.swayidle = {
      enable = true;
      timeouts = [
        {
          timeout = 600;
          command = "${pkgs.swaylock}/bin/swaylock -f";
        }
        {
          timeout = 605;
          command = "${niri} msg action power-off-monitors";
          resumeCommand = "${niri} msg action power-on-monitors";
        }
      ];
      events = [
        {
          event = "before-sleep";
          command = "${pkgs.swaylock}/bin/swaylock -f";
        }
      ];
    };

    # Launcher (colors ported from the tofi theme)
    programs.fuzzel = {
      enable = true;
      settings = {
        main = {
          font = "JetBrainsMono Nerd Font:size=16";
          lines = 8;
          width = 40;
        };
        colors = {
          background = "0d0e1cee";
          text = "ffffffff";
          match = "79a8ffff";
          selection = "fec43fff";
          selection-text = "0d0e1cff";
          selection-match = "79a8ffff";
          border = "79a8ffff";
        };
        border = {
          width = 2;
          radius = 0;
        };
      };
    };

    # Clipboard history watchers (user service). The Super+V picker and the
    # wl-clip-persist daemon are wired in dotfiles/niri/config.kdl.
    services.cliphist = {
      enable = true;
      allowImages = true;
    };

    # USB automount (replaces thunar-volman; needs services.udisks2 system-side).
    services.udiskie = {
      enable = true;
      automount = true;
      notify = true;
      tray = "never";
    };

    # Night light — ADJUST latitude/longitude to your location (defaulted to UK;
    # this only sets the sunrise/sunset timing).
    services.wlsunset = {
      enable = true;
      latitude = "54";
      longitude = "-1";
    };

    # On-screen display server; config.kdl binds call swayosd-client for the OSD.
    services.swayosd.enable = true;

    # Dark GTK + tell the appearance portal to prefer dark, so GTK dialogs,
    # nm-connection-editor, Chromium and websites all follow dark.
    gtk = {
      enable = true;
      theme = {
        name = "Adwaita-dark";
        package = pkgs.gnome-themes-extra;
      };
      iconTheme = {
        name = "Papirus-Dark";
        package = pkgs.papirus-icon-theme;
      };
      gtk3.extraConfig.gtk-application-prefer-dark-theme = true;
      gtk4.extraConfig.gtk-application-prefer-dark-theme = true;
    };
    dconf.settings."org/gnome/desktop/interface" = {
      color-scheme = "prefer-dark";
      gtk-theme = "Adwaita-dark";
    };

    # Default applications — open links/files in the right app.
    xdg.mimeApps = {
      enable = true;
      defaultApplications = {
        "x-scheme-handler/http" = "chromium.desktop";
        "x-scheme-handler/https" = "chromium.desktop";
        "text/html" = "chromium.desktop";
        "image/png" = "imv.desktop";
        "image/jpeg" = "imv.desktop";
        "image/gif" = "imv.desktop";
        "image/webp" = "imv.desktop";
        "image/svg+xml" = "imv.desktop";
        "application/pdf" = "org.pwmt.zathura.desktop";
        "video/mp4" = "mpv.desktop";
        "video/x-matroska" = "mpv.desktop";
        "video/webm" = "mpv.desktop";
        "audio/mpeg" = "mpv.desktop";
        "audio/flac" = "mpv.desktop";
        "audio/x-wav" = "mpv.desktop";
      };
    };

    home.packages = [
      niriPowerMenu
      pkgs-desktop.swaybg          # wallpaper (solid colour)
      pkgs-desktop.grim            # screenshots (niri also has built-in)
      pkgs-desktop.slurp           # region select
      pkgs-desktop.wl-clipboard    # clipboard
      pkgs-desktop.wl-clip-persist # keep clipboard after the source app closes
      pkgs-desktop.playerctl       # media keys
      pkgs-desktop.brightnessctl   # brightness keys
      pkgs-desktop.wdisplays       # display layout GUI
      pkgs-desktop.wiremix         # TUI audio mixer (bar volume on-click)
      pkgs-desktop.imv             # image viewer
      pkgs-desktop.zathura         # PDF viewer
      pkgs-desktop.mpv             # video / audio player
      pkgs.xdg-utils               # xdg-open / mime (cliphist image inference)
    ];
  };
}
