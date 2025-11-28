-- Claude prompt for pairup.nvim
-- Reads from prompt.md (single source of truth)

local M = {}

-- Find plugin root directory
local function get_plugin_root()
  local source = debug.getinfo(1, 'S').source:sub(2)
  return vim.fn.fnamemodify(source, ':h:h:h')
end

-- Read prompt.md and cache it
local cached_template = nil

function M.get_template()
  if cached_template then
    return cached_template
  end

  local prompt_path = get_plugin_root() .. '/prompt.md'
  local f = io.open(prompt_path, 'r')
  if f then
    cached_template = f:read('*a')
    f:close()
  else
    -- Fallback if file not found
    cached_template = [[
File: {filepath}

This file contains inline instructions marked with `cc:`.
Execute instructions at each marker, remove the marker when done.
If you need clarification, add `uu: <your question>` and STOP.
]]
  end

  return cached_template
end

---Build the prompt with actual values
---@param filepath string
---@param cc_marker string
---@param uu_marker string
---@return string
function M.build(filepath, cc_marker, uu_marker)
  local template = M.get_template()
  -- Replace placeholders
  local result = template
    :gsub('{filepath}', filepath)
    :gsub('`cc:`', '`' .. cc_marker .. '`')
    :gsub('`uu:`', '`' .. uu_marker .. '`')
    :gsub('cc: ', cc_marker .. ' ')
    :gsub('uu: ', uu_marker .. ' ')
  return result
end

return M
