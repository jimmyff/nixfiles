{ ... }: {

  # uwsm — Universal Wayland Session Manager. Wraps niri in systemd units
  # (graphical-session-pre/graphical-session/xdg-desktop-autostart targets) and
  # manages the session environment cleanly. This replaces the upstream
  # `niri-session` script, whose blanket `systemctl --user import-environment`
  # emitted the boot warnings (deprecated no-arg form + control-char prompt var).
  #
  # Setup: plain niri (no --session). niri runs `uwsm finalize` at startup (see
  # dotfiles/niri/config.kdl) to export WAYLAND_DISPLAY/NIRI_SOCKET — with an
  # explicit var list — and signal readiness. uwsm owns all systemd/D-Bus env.
  programs.uwsm = {
    enable = true;
    waylandCompositors.niri = {
      prettyName = "niri";
      comment = "Niri (uwsm-managed)";
      # Stable system path (matches the home module's niri reference) so uwsm and
      # the session run the same binary.
      binPath = "/run/current-system/sw/bin/niri";
    };
  };

  # Note: programs.uwsm hard-sets services.dbus.implementation = "broker" (the
  # modern default it recommends). Override with `lib.mkForce "dbus"` if needed.
}
