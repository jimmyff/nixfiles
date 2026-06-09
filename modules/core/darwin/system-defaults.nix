# macOS system defaults (nix-darwin) — first use of system.defaults in this repo.
#
# Chromium ⌃-based menu shortcuts, so Ctrl drives Chromium's menus (tabs, address
# bar, nav) rather than being swallowed — the browser half of the Ctrl layering.
# Codified verbatim from the live `defaults read org.chromium.Chromium
# NSUserKeyEquivalents`. Modifiers: ^ = Ctrl, @ = Cmd, $ = Shift, ~ = Option.
#
# Caveats:
#   - Menu titles are matched literally and are localization-sensitive; the
#     duplicate "New Tab"/"New tab" casing is a deliberate safety net.
#   - To apply: `killall cfprefsd` then relaunch Chromium (a rebuild writes the
#     pref, but a running app caches it).
#   - Edit here, NOT in System Settings → a rebuild overwrites manual changes.
{ ... }: {
  system.defaults.CustomUserPreferences."org.chromium.Chromium".NSUserKeyEquivalents = {
    "New Tab" = "^t";
    "New tab" = "^t";
    "New Window" = "^n";
    "New Private Window" = "^$n";
    "Close Tab" = "^w";
    "Open Location..." = "^l";
    "Reload This Page" = "^r";
    "Back" = "^k";
    "Forward" = "^j";
    "Select Previous Tab" = "@^h";
    "Select Next Tab" = "@^l";
  };
}
