{ pkgs, lib, config, inputs, ... }: {

    imports = [ 
        inputs.nvf.homeManagerModules.default
     ];

    options = {
        neovim_module.enable = lib.mkEnableOption "enables neovim_module";
    };

    config = lib.mkIf config.neovim_module.enable {

        # For options see: 
        # https://notashelf.github.io/nvf/options.html

        programs.nvf = {
            enable = true;
            
            settings.vim = {
                viAlias = true;
                vimAlias = true;
                debugMode = {
                    enable = false;
                    level = 16;
                    logFile = "/tmp/nvim.log";
                };

                spellcheck = {
                    enable = true;
                };

                lsp = {
                    # This must be enabled for the language modules to hook into
                    # the LSP API.
                    enable = true;

                    formatOnSave = true;
                    lspkind.enable = false;
                    lightbulb.enable = true;
                    lspsaga.enable = false;
                    trouble.enable = true;
                    lspSignature.enable = false; # conflicts with blink in maximal
                    otter-nvim.enable = true;
                    nvim-docs-view.enable = true;
                };

                debugger = {
                    nvim-dap = {
                        enable = true;
                        ui.enable = true;
                    };
                };

                # This section does not include a comprehensive list of available language modules.
                # To list all available language module options, please visit the nvf manual.
                languages = {
                    enableFormat = true; #
                    enableTreesitter = true;
                    enableExtraDiagnostics = true;

                    # Languages that will be supported in default and maximal configurations.
                    nix.enable = true;
                    markdown.enable = true;

                   
                    #css.enable = true;
                    #html.enable = true;
                    #sql.enable = true;
                    #go.enable = true;
                    #lua.enable = true;
                    #rust = {
                    #    enable = true;
                    #    crates.enable = true;
                    #};
                    nu.enable = false;
                    dart.enable = false;
                };

                visuals = {
                    nvim-scrollbar.enable = true;
                    nvim-web-devicons.enable = true;
                    nvim-cursorline.enable = true;
                    cinnamon-nvim.enable = true;
                    fidget-nvim.enable = true;

                    highlight-undo.enable = true;
                    indent-blankline.enable = true;

                    # Fun
                    cellular-automaton.enable = false;
                };

                statusline = {
                    lualine = {
                        enable = true;
                        theme = "catppuccin";
                    };
                };

                theme = {
                    enable = true;
                    name = "catppuccin";
                    style = "mocha";
                    transparent = false;
                };

                autopairs.nvim-autopairs.enable = true;

                # nvf provides various autocomplete options. The tried and tested nvim-cmp
                # is enabled in default package, because it does not trigger a build. We
                # enable blink-cmp in maximal because it needs to build its rust fuzzy
                # matcher library.
                autocomplete = {
                    nvim-cmp.enable = false;
                    blink-cmp.enable = true;
                };

                snippets.luasnip.enable = true;

                filetree = {
                    neo-tree = {
                        enable = true;
                    };
                };

                tabline = {
                    nvimBufferline.enable = true;
                };

                treesitter.context.enable = true;

                binds = {
                    whichKey.enable = true;
                    cheatsheet.enable = true;
                    hardtime-nvim.enable = true;
                };

                telescope.enable = true;

                git = {
                    enable = true;
                    gitsigns.enable = true;
                    gitsigns.codeActions.enable = false; # throws an annoying debug message
                };

                minimap = {
                    codewindow.enable = false; # lighter, faster, and uses lua for configuration
                };

                dashboard = {
                    dashboard-nvim.enable = false;
                    alpha.enable = true;
                };

                notify = {
                    nvim-notify.enable = true;
                };

                projects = {
                project-nvim.enable = true;
                };

                utility = {
                    ccc.enable = false;
                    vim-wakatime.enable = false;
                    diffview-nvim.enable = true;
                    yanky-nvim.enable = false;
                    icon-picker.enable = true;
                    surround.enable = true;
                    leetcode-nvim.enable = true;
                    multicursors.enable = true;
                    smart-splits.enable = false;

                    motion = {
                        hop.enable = true;
                        leap.enable = true;
                        precognition.enable = true;
                    };
                    images = {
                        image-nvim.enable = false;
                        img-clip.enable = true;
                    };
                };

                notes = {
                    obsidian.enable = false; # FIXME: neovim fails to build if obsidian is enabled
                    neorg.enable = false;
                    orgmode.enable = false;
                    mind-nvim.enable = true;
                    todo-comments.enable = true;
                };

                terminal = {
                    toggleterm = {
                        enable = true;
                        lazygit.enable = true;
                    };
                };

                ui = {
                    borders.enable = true;
                    noice.enable = true;
                    colorizer.enable = true;
                    modes-nvim.enable = false; # the theme looks terrible with catppuccin
                    illuminate.enable = true;
                    breadcrumbs = {
                        enable = true;
                        navbuddy.enable = true;
                    };
                    smartcolumn = {
                        enable = true;
                        setupOpts.custom_colorcolumn = {
                        # this is a freeform module, it's `buftype = int;` for configuring column position
                        nix = "110";
                        ruby = "120";
                        java = "130";
                        go = ["90" "130"];
                        };
                    };
                    fastaction.enable = true;
                };

                assistant = {
                    chatgpt.enable = false;
                    copilot = {
                        enable = false;
                        cmp.enable = false;
                    };
                    codecompanion-nvim.enable = false;
                    avante-nvim.enable = false;
                };

                session = {
                    nvim-session-manager.enable = false;
                };

                gestures = {
                    gesture-nvim.enable = false;
                };

                comments = {
                    comment-nvim.enable = true;
                };

                presence = {
                    neocord.enable = false;
                };
            };
      
        };

        # Set nvim as the default editor
        home.sessionVariables.EDITOR = "nvim";
    };
}