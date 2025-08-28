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
            # options = {

              # disable line wrapping
            #  wrap = false;
              
              # Color scheme
            #  termguicolors = true;
            #};

            #colorschemes = {
            #  gruvbox.enable = false;
            #  catppuccin = {
            #    enable = true;
            #    # Choose the 'mocha' variant
            #    settings.flavour = "mocha";
            #  };
            #};

            colorschemes.catppuccin.enable = true;
            

            plugins = {
              # file explorer
              nvim-tree.enable = true;

              # status line
              lualine.enable = true;

              # fizzy finder
              telescope.enable = true;

              # nix syntax highlighting
              nix.enable = true;

              # icons
              web-devicons.enable = true;
              
              # syntax highlighting
              treesitter = {
                enable = true;
                settings = {
                  indent.enable = true;
                  highlight.enable = true;
                };
                grammarPackages =  with pkgs.vimPlugins.nvim-treesitter.builtGrammars; [
                    bash
                    dart
                    json
                    markdown
                    nix
                    regex
                    toml
                    vim
                    vimdoc
                    xml
                ];
              };
                # harpoon = {
                #   enable = true;
                #   keymaps.addFile = "<leader>a";
                # };
              lsp = {
                enable = true;
                servers.dartls.enable = true;
              };
              
              # auto completion engine
              cmp = {
                enable = true;
                settings.sources = [
                  { name = "nvim_lsp"; } # Completions from your language server
                  { name = "buffer"; }   # Completions from text in your open files
                  { name = "path"; }     # File path completions
                ];
              };
              
              # git annotate line numbers
              gitsigns.enable = true;
              
              # learn key bindings after leader key
              which-key.enable = true;
              
              # indents
              indent-blankline.enable = true;

            };

            # And add Lua snippets with extraConfigLua
            extraConfigLua = ''
                vim.o.number = true
                vim.o.relativenumber = true
            '';
        };
    };
}
