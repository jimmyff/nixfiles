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
    # Common: decrypt the NextDNS config ID
    {
      age.identityPaths = lib.mkIf isDarwin [
        "${homeDir}/.ssh/id_ed25519"
      ];

      age.secrets.nextdns-config = {
        file = nixfiles-vault + "/${cfg.vaultFile}";
        mode = "600";
      };
    }

    # Linux: systemd-resolved with DNS-over-TLS
    (lib.optionalAttrs (!isDarwin) {
      services.resolved = {
        enable = true;
        # Strict DoT: DNS fails if TLS fails (change to "opportunistic" for fallback)
        dnsovertls = "true";
      };

      system.activationScripts.nextdnsResolved = {
        text = ''
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
        '';
        deps = ["agenix"];
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
          if ! profiles list -type configuration 2>/dev/null | grep -q "io.nextdns.dns-profile"; then
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
