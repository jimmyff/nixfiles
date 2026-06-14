{ ... }: {

  # niri: scrollable-tiling Wayland compositor (built-in nixpkgs module).
  # Package left at the stable default so mesa stays in sync — a mesa
  # version mismatch can stop niri starting on a TTY.
  programs.niri.enable = true;

  # The generated niri.service otherwise inherits a stripped PATH that
  # shadows the session PATH; let spawned children resolve normally.
  systemd.user.services.niri.enableDefaultPath = false;

  # Polkit. The niri/nixpkgs module enables neither polkit nor an agent.
  # The agent itself runs as a home-manager user service
  # (services.polkit-gnome) in the home niri module.
  security.polkit.enable = true;

  # swaylock authenticates via PAM; without this it can never unlock —
  # critical with lock-on-idle. Wires up /etc/pam.d/swaylock.
  security.pam.services.swaylock = {};
}
