{ lib, config, pkgs, username, ... }:
let
  cfg = config.insertcoin;
  kanataService = "kanata-internalKeyboard.service";

  insertcoinScript = pkgs.writeShellScriptBin "insertcoin" ''
    set -euo pipefail

    if [ $# -eq 0 ]; then
      echo "usage: insertcoin <cmd...>" >&2
      exit 64
    fi

    ${lib.optionalString cfg.kanata.enable ''
      KANATA_STOPPED=0
      cleanup() {
        if [ "$KANATA_STOPPED" = "1" ]; then
          ${pkgs.systemd}/bin/systemctl --no-ask-password start ${kanataService} >/dev/null 2>&1 || true
        fi
      }
      trap cleanup EXIT INT TERM HUP

      if ${pkgs.systemd}/bin/systemctl --no-ask-password stop ${kanataService} 2>/dev/null; then
        KANATA_STOPPED=1
      else
        echo "insertcoin: could not stop ${kanataService} (polkit rule missing?)" >&2
      fi
    ''}

    ${lib.optionalString cfg.touchpad.enable ''
      case "''${XDG_CURRENT_DESKTOP:-}" in
        COSMIC)
          cosmic_touchpad_conf="$HOME/.config/cosmic/com.system76.CosmicComp/v1/input_touchpad"
          if ! grep -q 'disable_while_typing: Some(false)' "$cosmic_touchpad_conf" 2>/dev/null; then
            echo "insertcoin: COSMIC detected. For trackpad use during gameplay," >&2
            echo "           disable 'Disable while typing' in Settings → Input → Touchpad." >&2
          fi
          ;;
      esac
    ''}

    "$@"
  '';
in {
  options.insertcoin = {
    enable = lib.mkEnableOption "insertcoin gaming wrapper";
    kanata.enable = lib.mkEnableOption "stop ${kanataService} while the wrapped command runs";
    touchpad.enable = lib.mkEnableOption "remind to disable the compositor's 'disable while typing' if it would block the trackpad during gameplay";
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = [ insertcoinScript ];

    security.polkit.extraConfig = lib.mkIf cfg.kanata.enable ''
      polkit.addRule(function(action, subject) {
        if (action.id == "org.freedesktop.systemd1.manage-units" &&
            action.lookup("unit") == "${kanataService}" &&
            subject.user == "${username}") {
          return polkit.Result.YES;
        }
      });
    '';
  };
}
