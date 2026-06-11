# DRY kanata config generator. Wraps the shared layer template (kanata-layers.kbd)
# with a per-platform (defcfg ...) and the host's key fragment (platformKeys),
# then validates the result at build time with the same kanata binary that will
# run it — a generator/keymap typo fails the build, not the keyboard.
#
# All params required (defaults hide bugs):
#   pkgs         - nixpkgs instance (for writeTextFile)
#   kanata       - the kanata package that will run this config (used for --check)
#   extraDefcfg  - list of extra defcfg lines (platform-specific, e.g. device filters)
#   platformKeys - { aliases, defsrc, base, gamemode } injected at the @@MARKERS@@
{ pkgs, kanata, extraDefcfg, platformKeys }:
let
  body = builtins.replaceStrings
    [ "@@ALIASES@@" "@@DEFSRC@@" "@@BASE@@" "@@GAMEMODE@@" ]
    [ platformKeys.aliases platformKeys.defsrc platformKeys.base platformKeys.gamemode ]
    (builtins.readFile ./kanata-layers.kbd);
in
pkgs.writeTextFile {
  name = "kanata.kbd";
  text = ''
    (defcfg
      ${builtins.concatStringsSep "\n  " ([ "process-unmapped-keys yes" ] ++ extraDefcfg)}
    )

    ${body}
  '';
  checkPhase = ''
    ${kanata}/bin/kanata --cfg "$target" --check
  '';
}
