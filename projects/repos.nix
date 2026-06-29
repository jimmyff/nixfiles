# Project name -> git remote, consumed by modules/development/default.nix.
# The per-repo flake.nix/.envrc/flake.lock now live in each repo (committed), so
# projects/ only needs the clone URLs plus the shared devshell-utils.nix.
{
  cache = "git@github.com:rocketware/cache-super.git";
  escp = "git@github.com:jimmyff/escp_super.git";
  jimmyff-website = "https://github.com/jimmyff/jimmyff-website.git";
  kosmos = "git@github.com:jimmyff/kosmos.git";
  osdn = "git@github.com:jimmyff/osdn_super.git";
  rocket-kit = "git@github.com:jimmyff/rocket-kit.git";
  rocketware = "git@github.com:jimmyff/rocketware-super.git";
  shed = "git@github.com:jimmyff/shed.git";
  warcrest = "git@github.com:jimmyff/warcrest.git";
}
