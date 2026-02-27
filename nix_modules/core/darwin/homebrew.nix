{ ... }: {
  # Fail early if Homebrew isn't installed
  system.activationScripts.preActivation.text = ''
    if ! [ -x /opt/homebrew/bin/brew ] && ! [ -x /usr/local/bin/brew ]; then
      echo "error: Homebrew is not installed. Install it first:"
      echo "  /bin/bash -c \"\$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)\""
      exit 1
    fi
  '';

  homebrew = {
    enable = true;

    onActivation = {
      cleanup = "zap"; # remove anything not declared
      autoUpdate = true;
      upgrade = true;
    };

    casks = [
      "signal"
      "ungoogled-chromium"
    ];
  };
}
