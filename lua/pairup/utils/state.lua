-- State management for claude-context.nvim

local M = {}

-- Internal state
local state = {
  claude_buf = nil,
  claude_job_id = nil,
  claude_win = nil,
  session_start = os.time(),
  last_status_update = 0,
  added_directories = {},
  lsp_diagnostics_cache = {},
  pending_updates = {},
}

-- Get state value
function M.get(key)
  return state[key]
end

-- Set state value
function M.set(key, value)
  state[key] = value
end

-- Clear all state
function M.clear()
  state.claude_buf = nil
  state.claude_job_id = nil
  state.claude_win = nil
  state.added_directories = {}
  state.pending_updates = {}
  state.lsp_diagnostics_cache = {}
end

-- Clear directories
function M.clear_directories()
  state.added_directories = {}
end

-- Add directory
function M.add_directory(dir)
  state.added_directories[dir] = true
end

-- Check if directory was added
function M.has_directory(dir)
  return state.added_directories[dir] == true
end

-- Get pending updates
function M.get_pending_updates()
  return state.pending_updates
end

-- Add pending update
function M.add_pending_update(filepath, data)
  state.pending_updates[filepath] = data
end

-- Clear pending updates
function M.clear_pending_updates()
  state.pending_updates = {}
end

-- Update LSP cache for buffer
function M.update_lsp_cache(bufnr, data)
  state.lsp_diagnostics_cache[bufnr] = data
end

-- Get LSP cache for buffer
function M.get_lsp_cache(bufnr)
  return state.lsp_diagnostics_cache[bufnr]
end

return M
