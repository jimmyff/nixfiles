{ lib, config, pkgs-stable, username, nixfiles-vault, ... }:
let
  cfg = config.nextdns;
  isDarwin = pkgs-stable.stdenv.isDarwin;
  homeDir =
    if isDarwin
    then "/Users/${username}"
    else "/home/${username}";
  userGroup =
    if isDarwin
    then "staff"
    else "users";

  # Captive portal toggle: temporarily relaxes NextDNS so the user can complete
  # hotel/airport portal logins (which need DNS hijacking that strict encrypted
  # DNS bypasses). Auto-reverts to strict mode after the timeout.
  nextdnsCaptiveScript = pkgs-stable.writeShellScriptBin "nextdns-captive" ''
    set -uo pipefail

    PROFILE_ID="io.nextdns.dns-profile"
    LINUX_CONF="/etc/systemd/resolved.conf.d/nextdns.conf"
    LINUX_DISABLED="$LINUX_CONF.captive-disabled"
    # Drop-in that overrides the module-level strict DoT enforcement during
    # captive mode — without this, resolved still rejects the hotel's plain
    # DNS responses and DNS resolution fails entirely.
    LINUX_DOT_OVERRIDE="/etc/systemd/resolved.conf.d/zz-captive-portal.conf"
    DARWIN_PROFILE="${homeDir}/.config/nextdns/nextdns.mobileconfig"
    DARWIN_LABEL="io.nextdns.captive.revert"
    DARWIN_PLIST="/Library/LaunchDaemons/$DARWIN_LABEL.plist"
    USER_NAME="${username}"
    SCRIPT_PATH="/run/current-system/sw/bin/nextdns-captive"

    is_darwin() { [ "$(uname)" = "Darwin" ]; }

    parse_seconds() {
      local d="$1"
      case "$d" in
        *s)   echo "''${d%s}" ;;
        *min) echo $(( ''${d%min} * 60 )) ;;
        *m)   echo $(( ''${d%m} * 60 )) ;;
        *h)   echo $(( ''${d%h} * 3600 )) ;;
        *)    echo "$d" ;;
      esac
    }

    notify_user() {
      local title="$1" msg="$2"
      if is_darwin; then
        su - "$USER_NAME" -c \
          "osascript -e 'display notification \"$msg\" with title \"$title\"'" \
          2>/dev/null || true
      else
        local uid
        uid=$(id -u "$USER_NAME" 2>/dev/null) || return 0
        sudo -u "$USER_NAME" \
          DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$uid/bus" \
          notify-send "$title" "$msg" 2>/dev/null || true
      fi
    }

    write_darwin_plist() {
      local seconds="$1"
      cat > "$DARWIN_PLIST" <<EOF
    <?xml version="1.0" encoding="UTF-8"?>
    <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
    <plist version="1.0">
    <dict>
      <key>Label</key><string>$DARWIN_LABEL</string>
      <key>ProgramArguments</key>
      <array>
        <string>$SCRIPT_PATH</string>
        <string>off</string>
      </array>
      <key>StartInterval</key><integer>$seconds</integer>
      <key>RunAtLoad</key><false/>
      <key>LaunchOnlyOnce</key><true/>
      <key>AbandonProcessGroup</key><true/>
    </dict>
    </plist>
    EOF
      chown root:wheel "$DARWIN_PLIST"
      chmod 644 "$DARWIN_PLIST"
    }

    cmd_on() {
      local duration="''${1:-5min}"

      if is_darwin; then
        launchctl bootout system "$DARWIN_PLIST" 2>/dev/null || true
        rm -f "$DARWIN_PLIST"

        if profiles list 2>/dev/null | grep -q "$PROFILE_ID"; then
          profiles remove -identifier "$PROFILE_ID"
        fi

        local secs
        secs=$(parse_seconds "$duration")
        write_darwin_plist "$secs"
        launchctl bootstrap system "$DARWIN_PLIST"
      else
        if [ -e "$LINUX_CONF" ]; then
          mv "$LINUX_CONF" "$LINUX_DISABLED"
        elif [ ! -e "$LINUX_DISABLED" ]; then
          echo "nextdns-captive: NextDNS resolved config not found at $LINUX_CONF" >&2
          echo "  (rebuild required?)" >&2
          exit 1
        fi

        # Override the module-level DNSOverTLS=true so resolved accepts the
        # hotel's plain-DNS responses.
        cat > "$LINUX_DOT_OVERRIDE" <<EOF
    [Resolve]
    DNSOverTLS=no
    EOF

        systemctl restart systemd-resolved

        local active
        active=$(nmcli -t -f NAME connection show --active | head -1)
        if [ -n "$active" ]; then
          nmcli connection modify "$active" \
            ipv4.ignore-auto-dns no ipv6.ignore-auto-dns no
          nmcli connection up "$active" >/dev/null
        else
          echo "nextdns-captive: warning - no active NetworkManager connection" >&2
        fi

        systemctl stop nextdns-captive-revert.timer 2>/dev/null || true
        systemctl reset-failed nextdns-captive-revert.service 2>/dev/null || true
        # OnCalendar (wall-clock) instead of OnActiveSec (monotonic) so the
        # revert fires reliably after suspend/resume.
        local secs target
        secs=$(parse_seconds "$duration")
        target=$(date -d "@$(($(date +%s) + secs))" "+%Y-%m-%d %H:%M:%S")
        systemd-run --on-calendar="$target" --unit=nextdns-captive-revert \
          "$SCRIPT_PATH" off
      fi

      echo "nextdns-captive: captive mode ON (auto-revert in $duration)"
    }

    cmd_off() {
      if is_darwin; then
        launchctl bootout system "$DARWIN_PLIST" 2>/dev/null || true
        rm -f "$DARWIN_PLIST"

        if profiles list 2>/dev/null | grep -q "$PROFILE_ID"; then
          echo "nextdns-captive: already strict (profile installed)"
          return 0
        fi

        if [ -f "$DARWIN_PROFILE" ]; then
          su - "$USER_NAME" -c "open '$DARWIN_PROFILE'"
          notify_user "NextDNS restored" "Click Install in System Settings → Profiles"
          echo "nextdns-captive: opened profile installer (approve in System Settings)"
        else
          echo "nextdns-captive: profile file missing at $DARWIN_PROFILE" >&2
          exit 1
        fi
      else
        systemctl stop nextdns-captive-revert.timer 2>/dev/null || true

        rm -f "$LINUX_DOT_OVERRIDE"
        if [ -e "$LINUX_DISABLED" ]; then
          mv "$LINUX_DISABLED" "$LINUX_CONF"
        fi

        systemctl restart systemd-resolved

        local active
        active=$(nmcli -t -f NAME connection show --active | head -1)
        if [ -n "$active" ]; then
          nmcli connection modify "$active" \
            ipv4.ignore-auto-dns yes ipv6.ignore-auto-dns yes
          nmcli connection up "$active" >/dev/null
        fi

        notify_user "NextDNS" "Strict DNS restored"
        echo "nextdns-captive: strict mode restored"
      fi
    }

    cmd_status() {
      if is_darwin; then
        if profiles list 2>/dev/null | grep -q "$PROFILE_ID"; then
          echo "mode: strict"
        else
          echo "mode: captive"
          [ -e "$DARWIN_PLIST" ] && echo "auto-revert: scheduled ($DARWIN_LABEL)"
        fi
      else
        if [ -e "$LINUX_DISABLED" ]; then
          echo "mode: captive"
          local next_us
          next_us=$(systemctl show nextdns-captive-revert.timer \
            -p NextElapseUSecRealtime --value 2>/dev/null || echo "")
          if [ -n "$next_us" ] && [ "$next_us" != "0" ]; then
            echo "auto-revert: $(date -d "@$((next_us / 1000000))" "+%H:%M:%S" 2>/dev/null)"
          fi
        else
          echo "mode: strict"
        fi
        local active
        active=$(nmcli -t -f NAME connection show --active | head -1)
        [ -n "$active" ] && echo "active connection: $active"
      fi
    }

    case "''${1:-}" in
      on|off)
        # Re-exec under sudo before dispatching so the original args survive.
        [ "$(id -u)" -eq 0 ] || exec sudo -E "$0" "$@"
        ;;
    esac

    case "''${1:-}" in
      on)     shift; cmd_on "$@" ;;
      off)    cmd_off ;;
      status) cmd_status ;;
      -h|--help|"")
        echo "usage: nextdns-captive {on [duration]|off|status}"
        echo "  duration: time spec (30s, 5min, 1h). Default: 5min."
        ;;
      *)
        echo "nextdns-captive: unknown command '$1'" >&2
        exit 64
        ;;
    esac
  '';
in {
  options.nextdns = {
    enable = lib.mkEnableOption "NextDNS encrypted DNS";
    vaultFile = lib.mkOption {
      type = lib.types.str;
      description = "Vault filename containing the NextDNS config ID";
      example = "nextdns_nixelbook.age";
    };
  };

  config = lib.mkIf cfg.enable (lib.mkMerge [
    # Common: decrypt the NextDNS config ID + install the captive toggle
    {
      age.identityPaths = lib.mkIf isDarwin [
        "${homeDir}/.ssh/id_ed25519"
      ];

      age.secrets.nextdns-config = {
        file = nixfiles-vault + "/${cfg.vaultFile}";
        mode = "600";
      };

      environment.systemPackages = [ nextdnsCaptiveScript ];
    }

    # Linux: systemd-resolved with DNS-over-TLS
    (lib.optionalAttrs (!isDarwin) {
      services.resolved = {
        enable = true;
        # Strict DoT: DNS fails if TLS fails (change to "opportunistic" for fallback)
        dnsovertls = "true";
      };

      # Stop NetworkManager pushing DHCP-supplied DNS to resolved as per-link
      # DNS — otherwise the router's nameserver overrides our global NextDNS.
      networking.networkmanager.connectionConfig = {
        "ipv4.ignore-auto-dns" = true;
        "ipv6.ignore-auto-dns" = true;
      };

      # notify-send for the captive toggle's revert notification
      environment.systemPackages = [ pkgs-stable.libnotify ];

      system.activationScripts.nextdnsResolved = {
        text = ''
          # Preserve an in-progress captive session across nixos-rebuild switch.
          if [ -e /etc/systemd/resolved.conf.d/nextdns.conf.captive-disabled ]; then
            echo "NextDNS captive mode active; skipping resolved config update"
          else
            CONFIG_ID=$(cat /run/agenix/nextdns-config 2>/dev/null || echo "")
            if [ -n "$CONFIG_ID" ]; then
              mkdir -p /etc/systemd/resolved.conf.d
              cat > /etc/systemd/resolved.conf.d/nextdns.conf << EOF
[Resolve]
DNS=45.90.28.0#$CONFIG_ID.dns.nextdns.io
DNS=2a07:a8c0::$CONFIG_ID.dns.nextdns.io
DNS=45.90.30.0#$CONFIG_ID.dns.nextdns.io
DNS=2a07:a8c1::$CONFIG_ID.dns.nextdns.io
DNSOverTLS=yes
Domains=~.
EOF
              systemctl restart systemd-resolved 2>/dev/null || true
              echo "NextDNS resolved config activated"
            else
              echo "Warning: NextDNS secret not available"
            fi
          fi
        '';
        deps = ["agenix"];
      };

      # If a reboot interrupts a captive session, restore strict mode on boot.
      systemd.services.nextdns-captive-restore = {
        description = "Restore NextDNS strict DNS if captive mode survived reboot";
        wantedBy = [ "multi-user.target" ];
        wants = [ "network-online.target" ];
        after = [ "network-online.target" "systemd-resolved.service" ];
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
        };
        script = ''
          if [ -e /etc/systemd/resolved.conf.d/nextdns.conf.captive-disabled ] \
             || [ -e /etc/systemd/resolved.conf.d/zz-captive-portal.conf ]; then
            ${nextdnsCaptiveScript}/bin/nextdns-captive off
          fi
        '';
      };
    })

    # macOS: generate .mobileconfig profile for DNS-over-HTTPS
    (lib.optionalAttrs isDarwin {
      system.activationScripts.postActivation.text = lib.mkAfter ''
        CONFIG_ID=$(cat /run/agenix/nextdns-config 2>/dev/null || echo "")
        PROFILE_DIR="${homeDir}/.config/nextdns"
        PROFILE_PATH="$PROFILE_DIR/nextdns.mobileconfig"
        if [ -n "$CONFIG_ID" ]; then
          mkdir -p "$PROFILE_DIR"
          cat > "$PROFILE_PATH" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>PayloadContent</key>
    <array>
        <dict>
            <key>DNSSettings</key>
            <dict>
                <key>DNSProtocol</key>
                <string>HTTPS</string>
                <key>ServerURL</key>
                <string>https://dns.nextdns.io/$CONFIG_ID</string>
                <key>ServerAddresses</key>
                <array>
                    <string>45.90.28.0</string>
                    <string>2a07:a8c0::</string>
                    <string>45.90.30.0</string>
                    <string>2a07:a8c1::</string>
                </array>
            </dict>
            <key>OnDemandRules</key>
            <array>
                <dict>
                    <key>Action</key>
                    <string>Connect</string>
                </dict>
            </array>
            <key>PayloadDisplayName</key>
            <string>NextDNS</string>
            <key>PayloadIdentifier</key>
            <string>com.apple.dnsSettings.managed.nextdns</string>
            <key>PayloadType</key>
            <string>com.apple.dnsSettings.managed</string>
            <key>PayloadUUID</key>
            <string>c5fb72ca-0846-4e74-8a0e-d5a6b3c8f901</string>
            <key>PayloadVersion</key>
            <integer>1</integer>
        </dict>
    </array>
    <key>PayloadDescription</key>
    <string>Configures DNS-over-HTTPS via NextDNS</string>
    <key>PayloadDisplayName</key>
    <string>NextDNS DNS Configuration</string>
    <key>PayloadIdentifier</key>
    <string>io.nextdns.dns-profile</string>
    <key>PayloadRemovalDisallowed</key>
    <false/>
    <key>PayloadType</key>
    <string>Configuration</string>
    <key>PayloadUUID</key>
    <string>d6ac83db-1957-5f85-9b1f-e6b7c4d9a012</string>
    <key>PayloadVersion</key>
    <integer>1</integer>
</dict>
</plist>
EOF
          chown ${username}:${userGroup} "$PROFILE_PATH"
          chmod 600 "$PROFILE_PATH"
          echo "NextDNS profile generated at $PROFILE_PATH"

          # Prompt user to install if profile not already active
          if ! sudo -u ${username} profiles list -type configuration 2>/dev/null | grep -q "io.nextdns.dns-profile"; then
            echo "NextDNS profile not installed — opening installer..."
            sudo -u ${username} open "$PROFILE_PATH"
            echo "Please approve the NextDNS profile in System Settings → General → Profiles"
          else
            echo "NextDNS profile already installed"
          fi
        else
          echo "Warning: NextDNS secret not available"
        fi
      '';
    })
  ]);
}
