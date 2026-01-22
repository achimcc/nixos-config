# Neovim Konfiguration mit rustaceanvim
# Optimiert für Rust-Entwicklung

{ config, pkgs, ... }:

{
  programs.neovim = {
    enable = true;
    defaultEditor = true;
    viAlias = true;
    vimAlias = true;

    extraPackages = with pkgs; [
      rust-analyzer
      cargo
      rustfmt
      clippy
      vscode-extensions.vadimcn.vscode-lldb.adapter # codelldb für Rust-Debugging
    ];

    plugins = with pkgs.vimPlugins; [
      # Farbschema
      {
        plugin = catppuccin-nvim;
        type = "lua";
        config = ''
          require("catppuccin").setup({ flavour = "mocha" })
          vim.cmd.colorscheme "catppuccin"
        '';
      }

      # Rustaceanvim - Rust IDE Features
      {
        plugin = rustaceanvim;
        type = "lua";
        config = ''
          vim.g.rustaceanvim = {
            server = {
              default_settings = {
                ['rust-analyzer'] = {
                  checkOnSave = {
                    command = "clippy",
                  },
                  cargo = {
                    allFeatures = true,
                  },
                },
              },
            },
          }
        '';
      }

      # Completion
      cmp-nvim-lsp
      cmp-buffer
      cmp-path
      {
        plugin = nvim-cmp;
        type = "lua";
        config = ''
          local cmp = require('cmp')
          cmp.setup({
            mapping = cmp.mapping.preset.insert({
              ['<C-Space>'] = cmp.mapping.complete(),
              ['<CR>'] = cmp.mapping.confirm({ select = true }),
              ['<Tab>'] = cmp.mapping.select_next_item(),
              ['<S-Tab>'] = cmp.mapping.select_prev_item(),
            }),
            sources = {
              { name = 'nvim_lsp' },
              { name = 'crates' },
              { name = 'buffer' },
              { name = 'path' },
            },
          })
        '';
      }

      # Crates.nvim - Cargo.toml Unterstützung
      {
        plugin = crates-nvim;
        type = "lua";
        config = ''
          require('crates').setup({
            completion = {
              cmp = { enabled = true },
            },
          })
        '';
      }

      # Treesitter
      {
        plugin = nvim-treesitter.withAllGrammars;
        type = "lua";
        config = ''
          require('nvim-treesitter.configs').setup({
            highlight = { enable = true },
            indent = { enable = true },
          })
        '';
      }

      # Telescope
      plenary-nvim
      {
        plugin = telescope-nvim;
        type = "lua";
        config = ''
          local builtin = require('telescope.builtin')
          vim.keymap.set('n', '<leader>ff', builtin.find_files)
          vim.keymap.set('n', '<leader>fg', builtin.live_grep)
          vim.keymap.set('n', '<leader>fb', builtin.buffers)
        '';
      }

      # Debug Adapter Protocol
      nvim-nio
      {
        plugin = nvim-dap;
        type = "lua";
        config = ''
          local dap = require('dap')

          -- Codelldb Adapter für Rust
          dap.adapters.codelldb = {
            type = 'server',
            port = "''${port}",
            executable = {
              command = '${pkgs.vscode-extensions.vadimcn.vscode-lldb.adapter}/bin/codelldb',
              args = { '--port', "''${port}" },
            },
          }

          dap.configurations.rust = {
            {
              name = "Launch",
              type = "codelldb",
              request = "launch",
              program = function()
                return vim.fn.input('Path to executable: ', vim.fn.getcwd() .. '/target/debug/', 'file')
              end,
              cwd = "''${workspaceFolder}",
              stopOnEntry = false,
            },
          }

          -- Keybindings
          vim.keymap.set('n', '<F5>', dap.continue)
          vim.keymap.set('n', '<F10>', dap.step_over)
          vim.keymap.set('n', '<F11>', dap.step_into)
          vim.keymap.set('n', '<F12>', dap.step_out)
          vim.keymap.set('n', '<leader>b', dap.toggle_breakpoint)
          vim.keymap.set('n', '<leader>B', function() dap.set_breakpoint(vim.fn.input('Breakpoint condition: ')) end)
        '';
      }

      {
        plugin = nvim-dap-ui;
        type = "lua";
        config = ''
          local dapui = require('dapui')
          dapui.setup()

          local dap = require('dap')
          dap.listeners.after.event_initialized['dapui_config'] = function() dapui.open() end
          dap.listeners.before.event_terminated['dapui_config'] = function() dapui.close() end
          dap.listeners.before.event_exited['dapui_config'] = function() dapui.close() end

          vim.keymap.set('n', '<leader>du', dapui.toggle)
        '';
      }

      # Statuszeile
      {
        plugin = lualine-nvim;
        type = "lua";
        config = ''require('lualine').setup({ options = { theme = 'catppuccin' } })'';
      }

      nvim-web-devicons
    ];

    extraLuaConfig = ''
      vim.g.mapleader = ' '
      vim.opt.number = true
      vim.opt.relativenumber = true
      vim.opt.tabstop = 4
      vim.opt.shiftwidth = 4
      vim.opt.expandtab = true
      vim.opt.termguicolors = true
      vim.opt.signcolumn = 'yes'
      vim.opt.clipboard = 'unnamedplus'

      -- LSP Keybindings
      vim.api.nvim_create_autocmd('LspAttach', {
        callback = function(args)
          local opts = { buffer = args.buf }
          vim.keymap.set('n', 'gd', vim.lsp.buf.definition, opts)
          vim.keymap.set('n', 'K', vim.lsp.buf.hover, opts)
          vim.keymap.set('n', '<leader>ca', vim.lsp.buf.code_action, opts)
          vim.keymap.set('n', '<leader>rn', vim.lsp.buf.rename, opts)
          vim.keymap.set('n', 'gr', vim.lsp.buf.references, opts)
          vim.keymap.set('n', '<leader>f', function() vim.lsp.buf.format({ async = true }) end, opts)
        end,
      })
    '';
  };
}
