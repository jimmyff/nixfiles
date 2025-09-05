{ pkgs, lib, config, ... }: {

  programs.claude-code = {

    enable = true;
    settings = {
      statusLine = {
        command = "input=$(cat); echo \"[$(echo \"$input\" | jq -r '.model.display_name')] 📁 $(basename \"$(echo \"$input\" | jq -r '.workspace.current_dir')\")\"";
        padding = 0;
        type = "command";
      };
      theme = "dark";
    };
  };

  programs.gemini-cli = {
    enable = true;
    defaultModel = "gemini-2.5-pro";
    settings = {
      theme= "Default";
      vimMode= true;
      preferredEditor = "hx";
      autoAccept = false;
    };

  }; 

}
