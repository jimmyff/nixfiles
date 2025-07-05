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
        --theme "text=cyan;prompt=yellow;input=magenta" \
        --greeting "👋 jimmyff.co.uk // github.com/jimmyff/nixfiles"
    '';
    };
  };

  environment.etc."greetd/environments".text = ''
    sway
  '';
}