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
      globals.mapleader = " ";

      vimAlias = true; # Adds a 'vim' alias to 'nvim'
      viAlias = true; # Adds a 'vi' alias to 'nvim'
      opts = {
        termguicolors = true;
        wrap = false;
      };

      colorschemes = {
        catppuccin = {
          enable = true;
          settings.flavour = "mocha";
        };
      };

      keymaps = [

        # Yazi
        {
          key = "<leader>e"; # "e" for explorer
          action = "<cmd>Yazi<CR>";
          mode = "n"; # Normal mode
          options = {
            silent = true;
            noremap = true;
            # This description will show up in which-key!
            desc = "Open file manager (Yazi)";
          };
        }

        # Telescope
        {
          key = "<leader>ff";
          action = "<cmd>Telescope find_files<CR>";
          mode = "n"; 
          options = {
            silent = true;
            noremap = true;
            desc = "Find Files (Telescope)";
          };
        }
        {
          key = "<leader>fg";
          action = "<cmd>Telescope live_grep<CR>";
          mode = "n"; 
          options = {
            silent = true;
            noremap = true;
            desc = "Grep (Telescope)";
          };
        }
        {
          key = "<leader>fb";
          action = "<cmd>Telescope buffers<CR>";
          mode = "n"; 
          options = {
            silent = true;
            noremap = true;
            desc = "Buffers (Telescope)";
          };
        }
        {
          key = "<leader>fh";
          action = "<cmd>Telescope help_tags<CR>";
          mode = "n"; 
          options = {
            silent = true;
            noremap = true;
            desc = "Help (Telescope)";
          };
        }

        # Basic 
        {
          key = "<leader>w";
          action = ":w<CR>";
          mode = "n"; 
          options = {
            silent = true;
            noremap = true;
            desc = "Write File";
          };
        }

        # Flash
        {
          key = "<leader>t";
          action = "<CMD>lua require('flash').jump()<CR>";
          mode = "n"; 
          options = {
            silent = true;
            noremap = true;
            desc = "Flash!";
          };
        }



      ];
      plugins = {


        # cursor teleporting
        flash.enable = true;
        
        # formatter
        # conform-nvim.enable = true;

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

        # file manager
        yazi = {
          enable = true;
          settings = {
            enable_mouse_support = true;
            manager = {
              show_hidden = true;
              sort_by = "mtime";
              sort_dir_first = true;
              sort_reverse = true;
            };
          };
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
