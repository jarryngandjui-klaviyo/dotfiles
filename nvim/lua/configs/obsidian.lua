vim.opt.conceallevel = 1

-- Link to the documentation
-- https://github.com/epwalsh/obsidian.nvim/blob/14e0427bef6c55da0d63f9a313fd9941be3a2479/README.md?plain=1#L387

local options = {
  workspaces = {
    {
      name = "secondbrain",
      path = "~/Notes",
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

  -- Optional, by default when you use `:ObsidianFollowLink` on a link to an external
  ---@param url string
  follow_url_func = function(url)
    -- Open the URL in the default web browser.
    vim.fn.jobstart({"open", url})  -- Mac OS
    -- vim.fn.jobstart({"xdg-open", url})  -- linux
    -- vim.cmd(':silent exec "!start ' .. url .. '"') -- Windows
    -- vim.ui.open(url) -- need Neovim 0.10.0+
  end,
}

return options
