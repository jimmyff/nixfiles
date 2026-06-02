{ ... }: {
  # Fail early if Homebrew isn't installed
  system.activationScripts.preActivation.text = ''
    if ! [ -x /opt/homebrew/bin/brew ] && ! [ -x /usr/local/bin/brew ]; then
      echo "error: Homebrew is not installed. Install it from: https://brew.sh/"
      exit 1
    fi
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
      autoUpdate = true;
      upgrade = true;
      # brew 5.1.14+ requires explicit confirmation before a --cleanup;
      # --force-cleanup cleans up without prompting (non-interactive activation).
      extraFlags = [ "--force-cleanup" ];
    };

    casks = [
      "camo-studio"
      "signal"
      "ungoogled-chromium"
    ];
  };
}
