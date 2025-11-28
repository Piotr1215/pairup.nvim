-- Claude prompt for pairup.nvim
-- Reads from prompt.md (single source of truth)

local M = {}
local config = require('pairup.config')

-- Find plugin root directory
local function get_plugin_root()
  local source = debug.getinfo(1, 'S').source:sub(2)
  return vim.fn.fnamemodify(source, ':h:h:h')
end

-- Read a prompt file
local function read_prompt_file(filename)
  local prompt_path = get_plugin_root() .. '/' .. filename
  local f = io.open(prompt_path, 'r')
  if f then
    local content = f:read('*a')
    f:close()
    return content
  end
  return nil
end

-- Cache templates
local cached_base = nil
local cached_progress = nil

function M.get_template()
  if not cached_base then
    cached_base = read_prompt_file('prompt.md')
      or [[
File: {filepath}

This file contains inline instructions marked with `{cc_marker}`.
Execute instructions at each marker, remove the marker when done.
If you need clarification, add `{uu_marker} <your question>` and STOP.
]]
  end

  local template = cached_base

  -- Append progress section if enabled
  if config.get('progress.enabled') then
    if not cached_progress then
      cached_progress = read_prompt_file('prompt_progress.md') or ''
    end
    template = template .. '\n' .. cached_progress
  end

  return template
end

---Build the prompt with actual values
---@param filepath string
---@param cc_marker string
---@param uu_marker string
---@return string
function M.build(filepath, cc_marker, uu_marker)
  local template = M.get_template()

  -- Get progress file path if enabled
  local progress_file = config.get('progress.file') or ''

  -- Replace placeholders
  local result = template
    :gsub('{filepath}', filepath)
    :gsub('{cc_marker}', cc_marker)
    :gsub('{uu_marker}', uu_marker)
    :gsub('{progress_file}', progress_file)

  return result
end

-- Clear cache (for testing or config changes)
function M.clear_cache()
  cached_base = nil
  cached_progress = nil
end

return M
