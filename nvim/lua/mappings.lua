require "nvchad.mappings"

-- add yours here

local map = vim.keymap.set

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

