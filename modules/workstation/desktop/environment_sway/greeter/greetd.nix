{
  pkgs,
  ...
}:
{
  services.greetd = {
    enable = true;
    settings = {
     default_session.command = ''
      ${pkgs.greetd.tuigreet}/bin/tuigreet \
        --time \
        --asterisks \
        --user-menu \
        --user-menu-min-uid 1000 \
        --user-menu-max-uid 29999 \
        --cmd sway \
        --theme "text=white;border=darkgray;action=gray;time=lightcyan;greet=lightcyan;prompt=lightyellow;input=lightmagenta"
    '';
    };
  };

  environment.etc."greetd/environments".text = ''
    sway
  '';
}