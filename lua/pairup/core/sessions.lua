local M = {}

local Path = vim.fs.dirname
local uv = vim.loop

M.sessions = {}
M.current_session = nil
M.session_files = {}

local function get_session_dir()
  local session_dir

  -- First, check if we're in a git repository with .claude directory
  local git_root = vim.fn.systemlist('git rev-parse --show-toplevel')[1]
  if git_root and vim.fn.isdirectory(git_root) == 1 then
    local claude_dir = git_root .. '/.claude'
    if vim.fn.isdirectory(claude_dir) == 1 then
      -- Use project-local .claude directory if it exists
      session_dir = claude_dir .. '/pairup_sessions'
      vim.fn.mkdir(session_dir, 'p')
      return session_dir
    end
  end

  -- Fallback to XDG_STATE_HOME for session data (can be wiped by user)
  local state_dir = vim.fn.stdpath('state')
  session_dir = state_dir .. '/pairup/sessions'
  vim.fn.mkdir(session_dir, 'p')
  return session_dir
end

local function generate_session_id()
  local uuid = vim.fn.system('uuidgen'):gsub('\n', '')
  if uuid == '' then
    uuid = string.format(
      '%08x-%04x-%04x-%04x-%012x',
      math.random(0, 0xffffffff),
      math.random(0, 0xffff),
      math.random(0, 0xffff),
      math.random(0, 0xffff),
      math.random(0, 0xffffffffffff)
    )
  end
  return uuid
end

function M.create_session(intent, description)
  local session_id = generate_session_id()
  local session = {
    id = session_id,
    intent = intent,
    description = description or '',
    files = {},
    created_at = os.time(),
    claude_session_id = nil,
  }

  M.sessions[session_id] = session
  M.current_session = session

  vim.g.pairup_current_session_id = session_id
  vim.g.pairup_current_intent = intent
  vim.g.pairup_session_files = {}

  return session_id
end

function M.add_file_to_session(filepath)
  if not M.current_session then
    return
  end

  local abs_path = vim.fn.fnamemodify(filepath, ':p')

  if not vim.tbl_contains(M.current_session.files, abs_path) then
    table.insert(M.current_session.files, abs_path)
    vim.g.pairup_session_files = M.current_session.files
  end

  M.session_files[abs_path] = M.session_files[abs_path] or {}
  if not vim.tbl_contains(M.session_files[abs_path], M.current_session.id) then
    table.insert(M.session_files[abs_path], M.current_session.id)
  end
end

function M.save_session(session)
  session = session or M.current_session
  if not session then
    return
  end

  local session_dir = get_session_dir()
  local session_file = string.format('%s/%s.json', session_dir, session.id)

  local json_str = vim.json.encode(session)
  local file = io.open(session_file, 'w')
  if file then
    file:write(json_str)
    file:close()
  end

  M.save_file_index()

  return session.id
end

function M.save_file_index()
  local session_dir = get_session_dir()
  local index_file = session_dir .. '/file_index.json'

  local json_str = vim.json.encode(M.session_files)
  local file = io.open(index_file, 'w')
  if file then
    file:write(json_str)
    file:close()
  end
end

function M.load_file_index()
  local session_dir = get_session_dir()
  local index_file = session_dir .. '/file_index.json'

  local file = io.open(index_file, 'r')
  if file then
    local content = file:read('*all')
    file:close()
    if content and content ~= '' then
      M.session_files = vim.json.decode(content) or {}
    end
  end
end

function M.load_session(session_id)
  local session_dir = get_session_dir()
  local session_file = string.format('%s/%s.json', session_dir, session_id)

  -- Check if file exists before trying to read
  if vim.fn.filereadable(session_file) == 0 then
    return nil
  end

  local file = io.open(session_file, 'r')
  if file then
    local content = file:read('*all')
    file:close()
    if content and content ~= '' then
      local ok, session = pcall(vim.json.decode, content)
      if ok and session then
        M.sessions[session_id] = session
        return session
      end
    end
  end

  return nil
end

-- Get Claude sessions from the project directory (no external calls)
function M.get_claude_active_sessions()
  -- Just use the existing get_all_project_sessions function
  -- It already loads Claude sessions from the project directory
  return M.get_all_project_sessions()
end

function M.get_all_project_sessions()
  local sessions = {}

  -- First, load all pairup saved sessions for this project
  local session_dir = get_session_dir()
  local session_files = vim.fn.glob(session_dir .. '/*.json', false, true)

  for _, session_file in ipairs(session_files) do
    local session_id = vim.fn.fnamemodify(session_file, ':t:r')
    local session = M.load_session(session_id)
    if session then
      table.insert(sessions, session)
    end
  end

  -- Also load Claude's sessions from project directory (skip in test mode)
  if not vim.g.pairup_test_mode then
    local cwd = vim.fn.getcwd()
    -- Claude sanitizes the path - replaces / and . with - (keeps leading dash)
    local project_path = cwd:gsub('[/.]', '-')
    local claude_sessions_dir = vim.fn.expand('~/.claude/projects/' .. project_path .. '/')

    if vim.fn.isdirectory(claude_sessions_dir) == 1 then
      local claude_files = vim.fn.glob(claude_sessions_dir .. '*.jsonl', false, true)

      for _, claude_file in ipairs(claude_files) do
        local session_id = vim.fn.fnamemodify(claude_file, ':t:r')

        -- Skip if we already have this session
        local already_have = false
        for _, s in ipairs(sessions) do
          if s.claude_session_id == session_id then
            already_have = true
            break
          end
        end

        if not already_have then
          -- Read Claude session to get summary
          local file = io.open(claude_file, 'r')
          if file then
            local summary = nil
            local first_line_count = 0

            for line in file:lines() do
              first_line_count = first_line_count + 1
              if first_line_count > 10 then
                break
              end -- Only check first 10 lines

              local ok, data = pcall(vim.json.decode, line)
              if ok and data and data.type == 'summary' and data.summary then
                summary = data.summary
                break
              end
            end
            file:close()

            -- Create a lightweight session entry
            local stat = vim.loop.fs_stat(claude_file)
            table.insert(sessions, {
              id = session_id,
              claude_session_id = session_id,
              description = summary or ('Claude session ' .. session_id:sub(1, 8)),
              intent = '',
              files = {},
              created_at = stat and stat.mtime.sec or os.time(),
              is_claude_only = true, -- Mark as Claude-only session
            })
          end
        end
      end
    end
  end

  -- Sort by creation time (newest first)
  table.sort(sessions, function(a, b)
    return (a.created_at or 0) > (b.created_at or 0)
  end)

  return sessions
end

function M.get_sessions_for_file(filepath)
  local abs_path = vim.fn.fnamemodify(filepath, ':p')
  M.load_file_index()

  local sessions = {}

  -- First, load pairup saved sessions
  local session_ids = M.session_files[abs_path] or {}
  local valid_ids = {}

  for _, session_id in ipairs(session_ids) do
    local session = M.load_session(session_id)
    if session then
      table.insert(sessions, session)
      table.insert(valid_ids, session_id)
    end
  end

  -- Update index if any sessions were missing
  if #valid_ids < #session_ids then
    M.session_files[abs_path] = valid_ids
    M.save_file_index()
  end

  -- Also load Claude's sessions from project directory (skip in test mode)
  if not vim.g.pairup_test_mode then
    local cwd = vim.fn.getcwd()
    -- Claude sanitizes the path - replaces / and . with - (keeps leading dash)
    local project_path = cwd:gsub('[/.]', '-')
    local claude_sessions_dir = vim.fn.expand('~/.claude/projects/' .. project_path .. '/')

    if vim.fn.isdirectory(claude_sessions_dir) == 1 then
      local claude_files = vim.fn.glob(claude_sessions_dir .. '*.jsonl', false, true)

      for _, claude_file in ipairs(claude_files) do
        local session_id = vim.fn.fnamemodify(claude_file, ':t:r')

        -- Skip if we already have this session
        local already_have = false
        for _, s in ipairs(sessions) do
          if s.claude_session_id == session_id then
            already_have = true
            break
          end
        end

        if not already_have then
          -- Read Claude session to get summary
          local file = io.open(claude_file, 'r')
          if file then
            local summary = nil
            local first_line_count = 0

            for line in file:lines() do
              first_line_count = first_line_count + 1
              if first_line_count > 10 then
                break
              end -- Only check first 10 lines

              local ok, data = pcall(vim.json.decode, line)
              if ok and data and data.type == 'summary' and data.summary then
                summary = data.summary
                break
              end
            end
            file:close()

            if summary then
              -- Create a lightweight session entry
              local stat = vim.loop.fs_stat(claude_file)
              table.insert(sessions, {
                id = session_id,
                claude_session_id = session_id,
                description = summary,
                intent = '',
                files = { abs_path },
                created_at = stat and stat.mtime.sec or os.time(),
                is_claude_only = true, -- Mark as Claude-only session
              })
            end
          end
        end
      end
    end
  end

  -- Sort by creation time (newest first)
  table.sort(sessions, function(a, b)
    return (a.created_at or 0) > (b.created_at or 0)
  end)

  return sessions
end

function M.resume_session(session_id)
  local session = M.load_session(session_id)
  if session then
    M.current_session = session
    vim.g.pairup_current_session_id = session.id
    vim.g.pairup_current_intent = session.intent
    vim.g.pairup_session_files = session.files
    return session
  end
  return nil
end

function M.end_current_session()
  if M.current_session then
    M.current_session.ended_at = os.time()
    M.save_session(M.current_session)

    M.current_session = nil
    vim.g.pairup_current_session_id = nil
    vim.g.pairup_current_intent = nil
    vim.g.pairup_session_files = nil
  end
end

function M.set_claude_session_id(claude_id)
  if M.current_session then
    M.current_session.claude_session_id = claude_id
  end
end

function M.get_current_session()
  return M.current_session
end

function M.wipe_all_sessions()
  local session_dir = get_session_dir()

  -- Remove all session files
  local files = vim.fn.glob(session_dir .. '/*.json', false, true)
  for _, file in ipairs(files) do
    os.remove(file)
  end

  -- Clear in-memory data
  M.sessions = {}
  M.current_session = nil
  M.session_files = {}

  -- Save empty index
  M.save_file_index()

  -- All pairup sessions wiped
end

function M.wipe_old_sessions(days)
  days = days or 30
  local cutoff_time = os.time() - (days * 86400)
  local session_dir = get_session_dir()
  local removed_count = 0

  -- Load all sessions and check their age
  local files = vim.fn.glob(session_dir .. '/*.json', false, true)
  for _, file in ipairs(files) do
    local session_id = vim.fn.fnamemodify(file, ':t:r')
    local session = M.load_session(session_id)

    if session and (session.created_at or 0) < cutoff_time then
      os.remove(file)
      M.sessions[session_id] = nil
      removed_count = removed_count + 1
    end
  end

  -- Update file index
  if removed_count > 0 then
    M.load_file_index()
    M.save_file_index()
    -- Wiped old sessions
  end
end

function M.setup()
  M.load_file_index()

  -- Optional: Auto-clean old sessions on startup
  local config = require('pairup.config')
  if config.get('auto_clean_sessions') then
    M.wipe_old_sessions(config.get('session_retention_days') or 30)
  end
end

return M
