# macOS system keyboard shortcuts (com.apple.symbolichotkeys), pulled verbatim from
# live `defaults read`. Nearly every default system shortcut is disabled so they don't
# collide with the kanata/aerospace/zellij layer; IDs 80/82 (window focus) stay enabled.
#
# Each entry: { enabled; value = { type = "standard"; parameters = [ key code modifiers ]; }; }
# (65535 = unbound). Disabling only needs `enabled = false`; values are kept for fidelity.
#
# Regenerate after toggling shortcuts in System Settings — a rebuild overwrites manual
# changes — with:
#   defaults export com.apple.symbolichotkeys - | plutil -convert json -o - -
# Note: changes here usually need a logout (or restart) to fully take effect.
{ ... }:
let
  hk = enabled: parameters: { inherit enabled; value = { type = "standard"; inherit parameters; }; };
  bare = enabled: { inherit enabled; };
in {
  system.defaults.CustomUserPreferences."com.apple.symbolichotkeys".AppleSymbolicHotKeys = {
    "15" = bare false;
    "16" = bare false;
    "17" = bare false;
    "18" = bare false;
    "19" = bare false;
    "20" = bare false;
    "21" = bare false;
    "22" = bare false;
    "23" = bare false;
    "24" = bare false;
    "25" = bare false;
    "26" = bare false;
    "27" = hk false [ 96 50 1048576 ];
    "32" = hk false [ 65535 126 8650752 ];
    "33" = hk false [ 65535 125 8650752 ];
    "36" = hk false [ 65535 103 8388608 ];
    "52" = hk false [ 100 2 1572864 ];
    "59" = hk false [ 65535 96 9437184 ];
    "60" = hk false [ 32 49 262144 ];
    "61" = hk false [ 32 49 786432 ];
    "64" = hk false [ 32 49 1048576 ];
    "65" = hk false [ 32 49 1572864 ];
    "79" = hk false [ 65535 123 8650752 ];
    "80" = hk true [ 65535 123 8781824 ];
    "81" = hk false [ 65535 124 8650752 ];
    "82" = hk true [ 65535 124 8781824 ];
    "98" = hk false [ 47 44 1179648 ];
    "118" = hk false [ 65535 18 262144 ];
    "119" = hk false [ 65535 19 262144 ];
    "159" = hk false [ 65535 36 262144 ];
    "162" = hk false [ 65535 96 9961472 ];
    "164" = hk false [ 65535 65535 0 ];
    "175" = hk false [ 65535 65535 0 ];
    "190" = hk false [ 113 12 8388608 ];
    "215" = hk false [ 65535 65535 0 ];
    "216" = hk false [ 65535 65535 0 ];
    "217" = hk false [ 65535 65535 0 ];
    "218" = hk false [ 65535 65535 0 ];
    "219" = hk false [ 65535 65535 0 ];
    "222" = hk false [ 65535 65535 0 ];
    "223" = hk false [ 65535 65535 0 ];
    "224" = hk false [ 65535 65535 0 ];
    "225" = hk false [ 65535 65535 0 ];
    "226" = hk false [ 65535 65535 0 ];
    "227" = hk false [ 65535 65535 0 ];
    "228" = hk false [ 65535 65535 0 ];
    "229" = hk false [ 65535 65535 0 ];
    "230" = hk false [ 65535 65535 0 ];
    "231" = hk false [ 65535 65535 0 ];
    "232" = hk false [ 65535 65535 0 ];
    "233" = hk false [ 109 46 1048576 ];
    "235" = hk false [ 65535 65535 0 ];
    "237" = hk false [ 102 3 8650752 ];
    "238" = hk false [ 99 8 8650752 ];
    "239" = hk false [ 114 15 8650752 ];
    "240" = hk false [ 65535 123 8650752 ];
    "241" = hk false [ 65535 124 8650752 ];
    "242" = hk false [ 65535 126 8650752 ];
    "243" = hk false [ 65535 125 8650752 ];
    "244" = hk false [ 65535 65535 0 ];
    "245" = hk false [ 65535 65535 0 ];
    "246" = hk false [ 65535 65535 0 ];
    "247" = hk false [ 65535 65535 0 ];
    "248" = hk false [ 65535 123 8781824 ];
    "249" = hk false [ 65535 124 8781824 ];
    "250" = hk false [ 65535 126 8781824 ];
    "251" = hk false [ 65535 125 8781824 ];
    "256" = hk false [ 65535 65535 0 ];
    "257" = hk false [ 65535 65535 0 ];
    "258" = hk false [ 65535 65535 0 ];
    "260" = hk false [ 65535 53 1048576 ];
  };
}
