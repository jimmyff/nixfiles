{ pkgs, lib, config, inputs, ... }: {

    imports = [
      # Import the nixvim module here
      inputs.nixvim.homeModules.nixvim
    ];

    options = {
        neovim_module.enable = lib.mkEnableOption "enables neovim_module";
    };

    config = lib.mkIf config.neovim_module.enable {
        # Set nvim as the default editor
        home.sessionVariables.EDITOR = "nvim";

        # Use the dedicated nixvim program options
        programs.nixvim = {
            # Enable the program
            enable = true;

            # The nixvim configuration is defined here
            vimAlias = true; # Adds a 'vim' alias to 'nvim'
            viAlias = true; # Adds a 'vi' alias to 'nvim'

            # You can declare plugins directly in Nix
            plugins = {
                # nvim-tree is now nvim-tree.nvim in nixvim
                nvim-tree.enable = true;
                lualine.enable = true;
                telescope.enable = true;
                nix.enable = true;
                web-devicons.enable = true;
                # harpoon = {
                #   enable = true;
                #   keymaps.addFile = "<leader>a";
                # };
                # lsp = {

                };

            };

            # And add Lua snippets with extraConfigLua
            extraConfigLua = ''
                vim.o.number = true
                vim.o.relativenumber = true
            '';
        };
    };
}