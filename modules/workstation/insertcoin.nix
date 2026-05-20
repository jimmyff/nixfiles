{ lib, config, pkgs, ... }:
let
  cfg = config.insertcoin;

  insertcoinScript = pkgs.writeShellScriptBin "insertcoin" ''
    set -uo pipefail

    PORT=${toString cfg.port}
    LOCKDIR="''${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
    LOCKFILE="$LOCKDIR/insertcoin.lock"
    COUNTFILE="$LOCKDIR/insertcoin.count"

    send_layer() {
      local layer="$1"
      local msg='{"ChangeLayer":{"new":"'"$layer"'"}}'
      local attempt
      for attempt in 1 2 3 4 5; do
        # Drain a bounded chunk of server output before closing. Kanata 1.9.0
        # panics in tcp_server.rs:99 (getpeername) if the client disconnects
        # too quickly, so this keeps the connection open long enough for the
        # server to register the client.
        if {
          printf '%s\n' "$msg" >&3
          ${pkgs.coreutils}/bin/timeout 0.3 ${pkgs.coreutils}/bin/head -c 256 <&3 >/dev/null 2>&1 || true
        } 3<>/dev/tcp/127.0.0.1/"$PORT" 2>/dev/null; then
          return 0
        fi
        sleep 0.1
      done
      echo "insertcoin: warning - could not reach kanata on 127.0.0.1:$PORT" >&2
      return 1
    }

    case "''${1:-}" in
      --reset)
        send_layer base
        rm -f "$COUNTFILE"
        exit 0
        ;;
      "")
        echo "usage: insertcoin <cmd...>" >&2
        echo "       insertcoin --reset    (force layer back to base)" >&2
        exit 64
        ;;
    esac

    mkdir -p "$LOCKDIR"

    # Refcount nested invocations: only outermost wrapper restores base.
    nest_enter() {
      (
        ${pkgs.util-linux}/bin/flock 9
        local n=0
        [ -f "$COUNTFILE" ] && n=$(cat "$COUNTFILE")
        echo $((n + 1)) > "$COUNTFILE"
        echo "$n"
      ) 9>"$LOCKFILE"
    }

    nest_exit() {
      (
        ${pkgs.util-linux}/bin/flock 9
        local n=1
        [ -f "$COUNTFILE" ] && n=$(cat "$COUNTFILE")
        n=$((n - 1))
        if [ "$n" -le 0 ]; then
          rm -f "$COUNTFILE"
          echo "0"
        else
          echo "$n" > "$COUNTFILE"
          echo "$n"
        fi
      ) 9>"$LOCKFILE"
    }

    cleanup() {
      local remaining
      remaining=$(nest_exit)
      if [ "$remaining" = "0" ]; then
        send_layer base
      fi
    }
    trap cleanup EXIT INT TERM HUP

    prev=$(nest_enter)
    if [ "$prev" = "0" ]; then
      send_layer gamemode
    fi

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
    port = lib.mkOption {
      type = lib.types.port;
      default = 5829;
      description = "TCP port on which kanata's IPC server is listening on 127.0.0.1.";
    };
    touchpad.enable = lib.mkEnableOption "remind to disable the compositor's 'disable while typing' if it would block the trackpad during gameplay";
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = [ insertcoinScript ];
  };
}
