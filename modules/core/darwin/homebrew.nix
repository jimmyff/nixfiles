{ ... }: {
  # Fail early if Homebrew isn't installed
  system.activationScripts.preActivation.text = ''
    if ! [ -x /opt/homebrew/bin/brew ] && ! [ -x /usr/local/bin/brew ]; then
      echo "error: Homebrew is not installed. Install it from: https://brew.sh/"
      exit 1
    fi
  '';

  # Remind that brew upgrades are decoupled from rebuilds (darwin-only).
  # Bold-cyan the command so it stands out without padding/blank lines.
  system.activationScripts.postActivation.text = ''
    printf 'Homebrew: casks reconciled, versions unchanged — run \033[1;36mbrew-up\033[0m to upgrade.\n'
  '';

  # Quiet down Homebrew's auto-update noise (interactive brew use).
  # Note: not forwarded to the sudo'd brew bundle during activation, so the
  # "New Formulae/Casks" list can still appear on darwin-rebuild switch.
  environment.variables = {
    HOMEBREW_NO_UPDATE_REPORT_NEW = "1"; # hide new formulae/casks list
    HOMEBREW_NO_ENV_HINTS = "1"; # hide "Adjust how often…/Hide these hints…" blurbs
  };

  homebrew = {
    enable = true;

    onActivation = {
      cleanup = "zap"; # remove anything not declared
      # Decoupled from rebuilds: a switch only reconciles the declared cask set
      # (install missing, zap undeclared). Index refresh + version upgrades are a
      # deliberate, separate step — run `brew-up` (see nu.nix). Keeps rebuilds
      # fast and deterministic.
      autoUpdate = false; # no `brew update` during rebuild
      upgrade = false; # no `brew upgrade` during rebuild
      # brew 5.1.14+ requires explicit confirmation before a --cleanup;
      # --force-cleanup cleans up without prompting (non-interactive activation).
      extraFlags = [ "--force-cleanup" ];
    };

    casks = [
      "camo-studio"
      "inkscape"
      "signal"
      "ungoogled-chromium"
    ];
  };
}
