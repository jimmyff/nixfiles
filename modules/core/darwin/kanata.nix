{ pkgs, ... }: {
  environment.systemPackages = [ pkgs.kanata ];

  launchd.user.agents.kanata = {
    enable = true;
    program = "${pkgs.kanata}/bin/kanata";
    programArgs = [ "--config" ../../../dotfiles/kanata/kanata.kbd ];
    keepAlive = true;
    runAtLoad = true;
  };
}