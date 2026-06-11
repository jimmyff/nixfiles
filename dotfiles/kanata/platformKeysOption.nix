# Shared module option: per-host kanata keys injected into the shared template.
# Consumed by both the nixos and darwin kanata modules so the shape is defined once.
{ lib }:
lib.mkOption {
  description = ''
    Host-specific kanata keys (function row, caps, ...) injected into the shared
    layer template. Set from the host's hardware/kanata-fn.nix. defsrc/base/gamemode
    must stay column-aligned (same key count).
  '';
  type = lib.types.submodule {
    options = {
      aliases = lib.mkOption {
        type = lib.types.lines;
        default = "";
        description = "A (defalias ...) block for the host keys (may be empty for pure passthrough keys).";
      };
      defsrc = lib.mkOption {
        type = lib.types.str;
        description = "defsrc columns appended after the home row.";
      };
      base = lib.mkOption {
        type = lib.types.str;
        description = "base-layer columns (same count/order as defsrc).";
      };
      gamemode = lib.mkOption {
        type = lib.types.str;
        description = "gamemode-layer columns (same count/order as defsrc).";
      };
    };
  };
}
