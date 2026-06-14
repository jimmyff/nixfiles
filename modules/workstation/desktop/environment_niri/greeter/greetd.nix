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
        --cmd niri-session \
        --theme "text=white;border=darkgray;action=gray;time=lightcyan;greet=lightcyan;prompt=lightyellow;input=lightmagenta"
    '';
    };
  };

  environment.etc."greetd/environments".text = ''
    niri-session
  '';
}
