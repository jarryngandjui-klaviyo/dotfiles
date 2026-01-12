require "nvchad.mappings"

-- add yours here

local map = vim.keymap.set
local harpoon = require("harpoon")

map("n", ";", ":", { desc = "CMD enter command mode" })
map("i", "jk", "<ESC>")

-- Diagnostic keymaps
map("n", "[d", vim.diagnostic.goto_prev, { desc = "Go to previous diagnostic message" })
map("n", "]d", vim.diagnostic.goto_next, { desc = "Go to next diagnostic message" })
map("n", "<leader>e", vim.diagnostic.open_float, { desc = "Open floating diagnostic message" })
map("n", "<leader>q", vim.diagnostic.setloclist, { desc = "Open diagnostics list" })

-- Git
map("n", "<leader>gl", ":Flog<CR>", { desc = "Git Log" })
map("n", "<leader>gho", ":DiffviewFileHistory<CR>", { desc = "Git File History" })
map("n", "<leader>ghc", ":DiffviewClose<CR>", { desc = "Close the current diffview" })
map("n", "<leader>gc", ":DiffviewOpen HEAD~1<CR>", { desc = "Git Last Commit" })
map("n", "<leader>gro", ":GitRemoteUrlOpen<CR>", { desc = "Open git remote url" })
map("n", "<leader>grc", ":GitRemoteUrlCopy<CR>", { desc = "Copy git remote url to clipboard" })


-- Obsidian
-- map("n", "<leader>obi", ":ObsidianPasteImg", { desc = "Obsidian paste image from clipboard" }) -- pasting images needs work
map("n", "<leader>obl", ":ObsidianBacklinks<CR>", { desc = "Obsidian references to the current buffer" })
map("n", "<leader>obo", ":ObsidianTOC<CR>", { desc = "Obsidian [o]utline" })
map("n", "<leader>obs", ":ObsidianSearch<CR>", { desc = "Obsidian [s]earch with ripgrep" })
map("n", "<leader>obt", ":ObsidianTemplate<CR>", { desc = "Obsidian insert [t]emplate" })
-- Render Markdown
map("n", "<leader>obm", ":RenderMarkdown toggle<CR>", { desc = "Toggle [M]arkdown view in obsidian" })

-- harpoon
local harpoon = require("harpoon")
-- REQUIRED
harpoon:setup()
-- REQUIRED
map("n", "<leader>hpa", function() harpoon:list():add() end, { desc = "Harpoon: Add current file to list" })
map("n", "<leader>hpl", function() harpoon.ui:toggle_quick_menu(harpoon:list()) end, { desc = "Harpoon: Toggle Quick Menu" })

-- Direct Jumps (select first 9 files)
map("n", "<leader>hp1", function() harpoon:list():select(1) end, { desc = "Harpoon: Go to item 1" })
map("n", "<leader>hp2", function() harpoon:list():select(2) end, { desc = "Harpoon: Go to item 2" })
map("n", "<leader>hp3", function() harpoon:list():select(3) end, { desc = "Harpoon: Go to item 3" })
map("n", "<leader>hp4", function() harpoon:list():select(4) end, { desc = "Harpoon: Go to item 4" })
map("n", "<leader>hp5", function() harpoon:list():select(5) end, { desc = "Harpoon: Go to item 5" })
map("n", "<leader>hp6", function() harpoon:list():select(6) end, { desc = "Harpoon: Go to item 6" })
map("n", "<leader>hp7", function() harpoon:list():select(7) end, { desc = "Harpoon: Go to item 7" })
map("n", "<leader>hp8", function() harpoon:list():select(8) end, { desc = "Harpoon: Go to item 8" })
map("n", "<leader>hp9", function() harpoon:list():select(9) end, { desc = "Harpoon: Go to item 9" })

-- Toggle previous & next buffers
map("n", "<leader>hpp", function() harpoon:list():prev() end, { desc = "Harpoon: Previous file in list" })
map("n", "<leader>hpn", function() harpoon:list():next() end, { desc = "Harpoon: Next file in list" })

