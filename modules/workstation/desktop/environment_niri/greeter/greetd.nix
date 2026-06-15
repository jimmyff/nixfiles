{
  pkgs,
  ...
}:
{
  services.greetd = {
    enable = true;
    settings = {
     default_session.command = ''
      ${pkgs.tuigreet}/bin/tuigreet \
        --time \
        --asterisks \
        --user-menu \
        --cmd "uwsm start -F -- /run/current-system/sw/bin/niri" \
        --theme "text=white;border=darkgray;action=gray;time=lightcyan;greet=lightcyan;prompt=lightyellow;input=lightmagenta"
    '';
    };
  };

  # Sessions selectable from tuigreet's menu. uwsm is the default (matches
  # --cmd); niri-session is kept as a fallback during the transition.
  environment.etc."greetd/environments".text = ''
    uwsm start -F -- /run/current-system/sw/bin/niri
    niri-session
  '';
}
