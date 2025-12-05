--[[
  Custom Neovim Plugit for Git
  :GitRemoteUrlOpen - Opens the current file's GitHub link in the browser.
  :GitRemoteUrlCopy - Copies the current file's GitHub link to the system clipboard.
]]

local M = {}

--- Finds the relative path of the current buffer to the Git repository root.
--- @return string|nil The relative path or nil if not in a git repo.
local function get_relative_file_path()
    -- Get the full path of the current file
    local full_path = vim.fn.expand('%:p')
    if full_path == '' then
        return nil
    end

    -- Get the git root directory (or nil if error/not a git repo)
    local git_root = vim.fn.system('git rev-parse --show-toplevel 2>/dev/null')
    git_root = git_root:gsub('\n', '') -- Remove trailing newline

    if vim.v.shell_error ~= 0 or git_root == '' then
        return nil
    end

    -- Calculate the relative path
    local relative_path = full_path:gsub('^' .. vim.fn.escape(git_root, '\\') .. '/', '')
    return relative_path
end

--- Retrieves and cleans the remote 'origin' URL.
--- Converts git@github.com:user/repo.git to https://github.com/user/repo
--- @return string|nil The cleaned base URL or nil on failure.
local function get_clean_remote_url()
    local remote_url = vim.fn.system('git config --get remote.origin.url 2>/dev/null')
    remote_url = remote_url:gsub('\n', '')

    if vim.v.shell_error ~= 0 or remote_url == '' then
        return nil
    end

    -- Convert SSH format to HTTPS
    if remote_url:match('^git@github%.com') then
        remote_url = remote_url:gsub('^git@github%.com:', 'https://github.com/')
    end

    -- Remove trailing .git
    remote_url = remote_url:gsub('%.git$', '')

    return remote_url
end

--- Retrieves the current branch name.
--- @return string|nil The branch name or 'HEAD' if detached.
local function get_branch_name()
    local branch = vim.fn.system('git rev-parse --abbrev-ref HEAD 2>/dev/null')
    branch = branch:gsub('\n', '')
    if vim.v.shell_error ~= 0 then
        return 'main' -- Fallback to 'main'
    end
    return branch
end

--- Constructs the full GitHub link for the current line and file.
--- @return string|nil The full GitHub link or nil if unable to generate.
local function create_github_link()
    local base_url = get_clean_remote_url()
    local branch = get_branch_name()
    local file_path = get_relative_file_path()
    local current_line = vim.fn.line('.')

    if not base_url or not file_path then
        vim.notify('Not in a Git repository or file is not saved.', vim.log.levels.WARN)
        return nil
    end

    -- GitHub file link format: BASE_URL/blob/BRANCH/PATH/TO/FILE#L<LINE_NUMBER>
    return string.format('%s/blob/%s/%s#L%d', base_url, branch, file_path, current_line)
end

--- Opens the generated link in the default system browser.
local function open_link()
    local link = create_github_link()
    if not link then return end

    local cmd
    if vim.loop.os_uname().sysname == 'Darwin' then
        cmd = 'open' -- macOS
    elseif vim.loop.os_uname().sysname == 'Linux' then
        cmd = 'xdg-open' -- Linux/WSL
    else
        cmd = 'start ""' -- Windows (needs special handling, this is a basic attempt)
    end

    vim.fn.system(string.format('%s "%s"', cmd, link))
    vim.notify('Opened link in browser: ' .. link, vim.log.levels.INFO)
end

--- Copies the generated link to the system clipboard.
local function copy_link()
    local link = create_github_link()
    if not link then return end

    -- Use the '+' register for system clipboard
    vim.fn.setreg('+', link, 'c')
    vim.notify('Copied GitHub link to clipboard: ' .. link, vim.log.levels.INFO)
end

-- Public initialization function called by lazy.nvim
function M.setup()
    -- :GitRemoteUrlOpen command
    vim.api.nvim_create_user_command('GitRemoteUrlOpen', open_link, {
        desc = 'Open current file remote GitHub link',
        bang = false,
        nargs = 0,
    })

    -- :GitRemoteUrlCopy command
    vim.api.nvim_create_user_command('GitRemoteUrlCopy', copy_link, {
        desc = 'Copy current file remote GitHub link to clipboard',
        bang = false,
        nargs = 0,
    })
end

return M
