local config_root = vim.fn.stdpath('config')

return {
  -- Improve vim skills by playing games
  {
    "ThePrimeagen/vim-be-good",
  },

  -- bookmark project files
  {
    "ThePrimeagen/harpoon",
    branch = "harpoon2",
    dependencies = { "nvim-lua/plenary.nvim" }
  },

  {
    "stevearc/conform.nvim",
    -- event = 'BufWritePre', -- uncomment for format on save
    opts = require "configs.conform",
  },

  -- Full signature help, docs and completion on lua files
  {
    "folke/lazydev.nvim",
    ft = "lua", -- only load on lua files
    event = {
      "BufReadPre",
      "BufNewFile",
    },
    opts = {
      library = {
       { path = "${3rd}/luv/library", words = { "vim%.uv" } },
      },
    },
  },

  -- a collection of LSP server configurations for the Nvim LSP client
  {
    "neovim/nvim-lspconfig",
    config = function()
      require("nvchad.configs.lspconfig").defaults()
      require "configs.lspconfig"
    end,
  },

  {
    "williamboman/mason-lspconfig.nvim",
      dependencies = {
        "williamboman/mason.nvim",
        "neovim/nvim-lspconfig",
        { "mason-org/mason.nvim", opts = {}},
      },
      automatic_enable = {
        "pyright",
        "pylsp",
        "ruff",
      },
      config = function()
        local servers = {
          "html", -- HTML LSP
          "rust_analyzer", -- Rust Analyzer
          "pyright",
          "pylsp",
          "ruff",
          "tailwindcss", -- Tailwind CSS LSP
          "sqls", -- SQL LSP
          "eslint", -- ESLint LSP
          "nextls", -- Next.js LSP
          "jsonls", -- JSON LSP
          "bashls", -- Bash LSP
          "cssls", -- CSS LSP
          "dockerls", -- Dockerfile LSP
          "docker_compose_language_service", -- Docker Compose LSP
          "yamlls", -- YAML LSP
          "nginx_language_server", -- Nginx LSP
          "lua_ls", -- Lua LSP
          "gopls", -- golang
          "emmet_ls",
          "cmake",
        }
      
        local lspconfig = require "lspconfig"
        local masonlsp = require "mason-lspconfig"
        local nvlsp = require "nvchad.configs.lspconfig"

        masonlsp.setup({
          ensure_installed = servers,
          handlers = {
            function(server_name)
              lspconfig[server_name].setup {
                on_attach = nvlsp.on_attach,
                on_init = nvlsp.on_init,
                capabilities = nvlsp.capabilities,
              }
            end,
          },
        })
      end,
  },

  -- basic highlighting for any language syntax tree parser
  {
    "nvim-treesitter/nvim-treesitter",
    opts = require "configs.treesitter",
  },

  -- Git Fugitive is the premier Vim plugin for Git
  { "tpope/vim-fugitive" },

  -- Git branch viewer for Vim/Neovim
  { "rbong/vim-flog", dependencies = {
    "tpope/vim-fugitive",
  }, lazy = false },

  -- Git diff side by side DiffviewFileHistory
  { "sindrets/diffview.nvim", lazy = false },

  -- a plugin to place, toggle and display marks.
  {
    "chentoast/marks.nvim",
    event = "VeryLazy",
  },

  -- {
  --   "epwalsh/obsidian.nvim",
  --   version = "*",  -- recommended, use latest release instead of latest commit
  --   lazy = false,
  --   ft = "markdown",
  --   -- Replace the above line with this if you only want to load obsidian.nvim for markdown files in your vault:
  --   -- event = {
  --   --   -- If you want to use the home shortcut '~' here you need to call 'vim.fn.expand'.
  --   --   -- E.g. "BufReadPre " .. vim.fn.expand "~" .. "/my-vault/*.md"
  --   --   -- refer to `:h file-pattern` for more examples
  --   --   "BufReadPre path/to/my-vault/*.md",
  --   --   "BufNewFile path/to/my-vault/*.md",
  --   -- },
  --   dependencies = {
  --     "nvim-lua/plenary.nvim",
  --   },
  --   opts = require "configs.obsidian",
  --   config = function(_, opts)
  --       require('obsidian').setup(opts)
  --   end
  -- },

  -- {
  --   "MeanderingProgrammer/markdown.nvim",
  --   name = "render-markdown",
  --   enabled = true,
  --   lazy = false, -- Force immediate load
  --   dependencies = {
  --     "nvim-treesitter/nvim-treesitter", -- Mandatory
  --     "nvim-tree/nvim-web-devicons",     -- Optional but recommended
  --   },
  --   ft = { "markdown", "md" },
  --   config = function()
  --     require("render-markdown").setup({
  --       enabled = false,
  --       file_types = { "markdown", "codecompanion" },
  --       anti_conceal = { enabled = false }
  --     })
  --   end
  -- },

  ---- block for all custom modules managed by custom/init.lua
  {
    'custom', 
    dir = config_root .. '/lua',
    lazy = false, 
    config = function()
        require('custom').setup()
    end
  },  
}

