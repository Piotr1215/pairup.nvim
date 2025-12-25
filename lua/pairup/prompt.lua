-- Claude prompt for pairup.nvim
-- Reads from prompt.md (single source of truth)

local M = {}

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

-- Cache template
local cached_base = nil

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

  return cached_base
end

local DRAFT_MODE_ADDENDUM = [[

DRAFT MODE ACTIVE:
Your edits are being captured for user review, not applied immediately.
If you see "Edit captured as draft" - this is expected. Do NOT retry.
Continue with other tasks; the user will apply drafts when ready.
]]

---Build the prompt with actual values
---@param filepath string
---@param markers table {command, question, constitution}
---@return string
function M.build(filepath, markers)
  local template = M.get_template()

  local result = template
    :gsub('{filepath}', filepath)
    :gsub('{cc_marker}', markers.command)
    :gsub('{uu_marker}', markers.question)
    :gsub('{constitution_marker}', markers.constitution)
    :gsub('{plan_marker}', markers.plan or 'ccp:')

  if require('pairup.drafts').is_enabled() then
    result = result .. DRAFT_MODE_ADDENDUM
  end

  return result
end

return M
