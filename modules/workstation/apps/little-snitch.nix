{
  pkgs-stable,
  lib,
  config,
  ...
}: let
  cfg = config.little-snitch;

  littlesnitch-linux = pkgs-stable.stdenv.mkDerivation rec {
    pname = "littlesnitch";
    version = "1.0.1";

    src = pkgs-stable.fetchurl {
      url = "https://obdev.at/downloads/littlesnitch-linux/littlesnitch_${version}_amd64.deb";
      sha256 = "1zwag00nfs7rn9psj5dn35yhsird0pjzp4yx71myrj68fhqvcbss";
    };

    nativeBuildInputs = with pkgs-stable; [
      dpkg
      autoPatchelfHook
    ];

    buildInputs = with pkgs-stable; [
      linux-pam
      sqlite
      stdenv.cc.cc.lib
    ];

    unpackCmd = "dpkg-deb -x $curSrc .";
    sourceRoot = ".";

    installPhase = ''
      runHook preInstall

      mkdir -p $out/bin
      install -m755 usr/bin/littlesnitch $out/bin/littlesnitch

      mkdir -p $out/lib/systemd/system
      substitute usr/lib/systemd/system/littlesnitch.service \
        $out/lib/systemd/system/littlesnitch.service \
        --replace-fail "/usr/bin/littlesnitch" "$out/bin/littlesnitch"

      mkdir -p $out/share/doc/littlesnitch
      cp usr/share/doc/littlesnitch/copyright $out/share/doc/littlesnitch/
      mkdir -p $out/share/metainfo
      cp usr/share/metainfo/at.obdev.littlesnitch.metainfo.xml $out/share/metainfo/

      runHook postInstall
    '';

    meta = with lib; {
      description = "Network monitor and firewall using eBPF";
      homepage = "https://obdev.at/products/littlesnitch-linux/";
      license = licenses.unfree;
      platforms = ["x86_64-linux"];
    };
  };
in {
  options.little-snitch = {
    enable = lib.mkEnableOption "Little Snitch network monitor";
  };

  config = lib.mkIf cfg.enable (
    if pkgs-stable.stdenv.isDarwin
    then {
      homebrew.casks = ["little-snitch"];
    }
    else {
      environment.systemPackages = [littlesnitch-linux];

      systemd.packages = [littlesnitch-linux];
      systemd.services.littlesnitch = {
        enable = true;
        wantedBy = ["multi-user.target"];
      };
    }
  );
}
