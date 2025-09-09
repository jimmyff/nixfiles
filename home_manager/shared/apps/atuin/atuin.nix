{
  pkgs,
  lib,
  config,
  ...
}: {
  options = {
    atuin_module.enable = lib.mkEnableOption "enables atuin_module";
  };

  config = lib.mkIf config.atuin_module.enable {
    programs.atuin = {
      enable = true;
      enableNushellIntegration = lib.mkIf config.programs.nushell.enable true;
      
      settings = {
        # Basic atuin configuration
        update_check = false;
        sync_frequency = "5m";
        sync_address = "https://api.atuin.sh";
        auto_sync = true;
        dialect = "us";
        show_preview = true;
        max_preview_height = 4;
        show_help = true;
        exit_mode = "return-original";
        word_jump_mode = "word";
        word_chars = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789";
        scroll_context_lines = 1;
        history_format = "{{time}} :: {{command}}";
        style = "compact";
      };
    };
  };
}