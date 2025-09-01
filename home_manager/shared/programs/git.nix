{ lib, config, ... }: {

  options = {
    git_module.enable = lib.mkEnableOption "enables git_module";
  };

  config = lib.mkIf config.git_module.enable {
    
    programs.git = {
      enable = true;
      userName = "jimmyff";
      userEmail = "code@rocketware.co.uk";
    };

    # Github cli
    programs.gh = {
      enable = true;
    };

  };
}