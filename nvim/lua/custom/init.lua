local M = {}

function M.setup()
    local git = require("custom.git")
    git.setup()
end

return M
