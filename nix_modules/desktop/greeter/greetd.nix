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
        --cmd sway \
        --theme "text=white;border=darkgray;action=gray;time=lightcyan;greet=lightcyan;prompt=lightyellow;input=lightmagenta"
    '';
    };
  };

  environment.etc."greetd/environments".text = ''
    sway
  '';
}