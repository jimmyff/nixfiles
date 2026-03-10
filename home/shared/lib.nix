{ lib, config, pkgs }: {
  # Helper function to wrap packages with Doppler environment injection
  mkDopplerWrapper = { package, project, config ? "dev", binaries ? null }:
    let
      # If binaries not specified, try to infer from package name
      defaultBinaries = [ (lib.getName package) ];
      wrappedBinaries = if binaries != null then binaries else defaultBinaries;
    in
    pkgs.symlinkJoin {
      name = "${lib.getName package}-doppler-wrapped";
      paths = [ package ];
      buildInputs = [ pkgs.makeWrapper ];
      postBuild = lib.concatMapStringsSep "\n" (binary: ''
        wrapProgram $out/bin/${binary} \
          --run 'while IFS="=" read -r key value; do [[ $key =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]] && { value=''${value#\"}; value=''${value%\"}; export "$key"="$value"; }; done < <(${pkgs.doppler}/bin/doppler secrets download --no-file --format env --project ${project} --config ${config})'
      '') wrappedBinaries;
    };

  # Helper function to create Darwin Application Support symlinks to XDG config
  mkDarwinAppSupportSymlink = { appName, dagEntry ? "writeBoundary" }:
    lib.mkIf pkgs.stdenv.isDarwin {
      "setup${lib.strings.toUpper (lib.substring 0 1 appName)}${lib.substring 1 (-1) appName}Symlink" =
        lib.hm.dag.entryAfter [dagEntry] ''
          # Path to the default macOS ${appName} config location
          APP_DEFAULT_PATH="$HOME/Library/Application Support/${appName}"
          # Path to our home-manager ${appName} config
          APP_HM_PATH="${config.xdg.configHome}/${appName}"

          echo "Setting up ${appName} configuration symlink for Darwin..."

          # Create the Application Support directory if it doesn't exist
          mkdir -p "$(dirname "$APP_DEFAULT_PATH")"

          # Check if the default path already exists
          if [ -e "$APP_DEFAULT_PATH" ] || [ -L "$APP_DEFAULT_PATH" ]; then
            # Check if it's already a symlink to our config
            if [ -L "$APP_DEFAULT_PATH" ] && [ "$(readlink "$APP_DEFAULT_PATH")" = "$APP_HM_PATH" ]; then
              echo "${appName} symlink already correctly configured"
            else
              echo "Backing up existing ${appName} config..."
              # Create backup with timestamp
              BACKUP_PATH="$APP_DEFAULT_PATH.backup.$(date +%Y%m%d_%H%M%S)"
              if ! mv "$APP_DEFAULT_PATH" "$BACKUP_PATH"; then
                echo "ERROR: Failed to backup existing ${appName} config" >&2
                exit 1
              fi
              echo "Existing config backed up to: $BACKUP_PATH"
            fi
          fi

          # Remove any existing symlink or directory (if backup failed above, we'll error out)
          rm -rf "$APP_DEFAULT_PATH" 2>/dev/null || true

          # Create the symlink
          echo "Creating symlink: $APP_DEFAULT_PATH -> $APP_HM_PATH"
          if ! ln -sf "$APP_HM_PATH" "$APP_DEFAULT_PATH"; then
            echo "ERROR: Failed to create ${appName} configuration symlink" >&2
            exit 1
          fi

          # Verify the symlink was created correctly
          if [ ! -L "$APP_DEFAULT_PATH" ] || [ "$(readlink "$APP_DEFAULT_PATH")" != "$APP_HM_PATH" ]; then
            echo "ERROR: ${appName} symlink verification failed" >&2
            exit 1
          fi

          echo "Successfully configured ${appName} symlink on Darwin"
        '';
    };
}