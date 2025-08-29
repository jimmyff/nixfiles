{ pkgs, username, ... }:
{
  programs = {
    nushell = { 
      enable = true;

      # The config.nu can be anywhere you want if you like to edit your Nushell with Nu
      # configFile.source = ./.../config.nu;
      # for editing directly to config.nu 
      extraConfig = ''
      let carapace_completer = {|spans|
      carapace $spans.0 nushell ...$spans | from json
      }
      $env.config = {
        show_banner: false,
        completions: {
        case_sensitive: false   # case-sensitive completions
        quick: true             # set to false to prevent auto-selecting completions
        partial: true           # set to false to prevent partial filling of the prompt
        algorithm: "fuzzy"      # prefix or fuzzy
        external: {
        # set to false to prevent nushell looking into $env.PATH to find more suggestions
            enable: true 
        # set to lower can improve completion performance at the cost of omitting some options
            max_results: 100 
            completer: $carapace_completer # check 'carapace_completer' 
          }
        }
      } 
      $env.PATH = ($env.PATH | 
      split row (char esep) |
      prepend /home/${username}/.apps |
      append /usr/bin/env
      )
      '';
      shellAliases = {
        vi = "hx";
        vim = "hx";
        nano = "hx";
      };
    };  

    # Carapace / completions
    carapace.enable = true;
    carapace.enableNushellIntegration = true;

    # Starship / prompt
    starship = { 
      enable = true;
      settings = {
        add_newline = true;
        character = { 
          success_symbol = "[➜](bold green)";
          error_symbol = "[➜](bold red)";
        };
      };
    };

    # Zoxide / enhanced cd
    zoxide = {
      enable = true;
      enableNushellIntegration = true;
      # options = [
      # ];
    };

    # FZF / fuzzy finder
    fzf = {
      enable = true;
      # enableNushellIntegration = true;
    };
  };
}