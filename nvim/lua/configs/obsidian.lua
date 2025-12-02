vim.opt.conceallevel = 1

local options = {
  workspaces = {
    {
      name = "secondbrain",
      path = "~/Library/Mobile Documents/iCloud~md~obsidian/Documents/Second brain",
    },
    -- use obsidian outside of vault
    {
      name = "no-vault",
      path = function()
        -- alternatively use the CWD:
        -- return assert(vim.fn.getcwd())
        return assert(vim.fs.dirname(vim.api.nvim_buf_get_name(0)))
      end,
      overrides = {
        notes_subdir = vim.NIL,  -- have to use 'vim.NIL' instead of 'nil'
        new_notes_location = "current_dir",
        templates = {
          folder = vim.NIL,
        },
        disable_frontmatter = true,
      },
    },
  },
  templates = {
    folder = "5. Templates",
    date_format = "%Y-%m-%d-%a",
    time_format = "%H:%M",
  },
  attachments = {
    img_folder = "7.\\ Files",  -- default folder to save images
  },
  ui = {
    enable = false,  -- use render-markdown plugin for ui 
  },
}

return options
