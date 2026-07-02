{ pkgs-apps, lib, config, ... }: {
  options.mux_module.enable = lib.mkEnableOption "mux herdr workspace launcher";

  config = lib.mkIf config.mux_module.enable {
    # `mux` attaches an always-on `hub` session you curate with pin/unpin;
    # `mux --project` opens a dedicated per-project session. See mux.nu.
    home.packages = [
      (let
        mux = pkgs-apps.writeScriptBin "mux"
          ("#!${pkgs-apps.nushell}/bin/nu\n" + builtins.readFile ./mux.nu);
      in
        # Space auto-sort calls herdr's socket `workspace.move` via `nc`. macOS has a working
        # /usr/bin/nc; Linux may not (`-U`), so wrap with netcat-openbsd (broken on darwin) there.
        if pkgs-apps.stdenv.isLinux then
          pkgs-apps.symlinkJoin {
            name = "mux";
            paths = [ mux ];
            nativeBuildInputs = [ pkgs-apps.makeWrapper ];
            postBuild = "wrapProgram $out/bin/mux --prefix PATH : ${lib.makeBinPath [ pkgs-apps.netcat-openbsd ]}";
          }
        else mux)
    ];
  };
}
