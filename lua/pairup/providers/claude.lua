-- Claude provider for pairup.nvim

local M = {}
local config = require('pairup.config')
local state = require('pairup.utils.state')
local sessions = require('pairup.core.sessions')

-- Provider name
M.name = 'claude'

-- Check if Claude process is actually running
function M.is_process_running(job_id)
  if not job_id then
    return false
  end
  -- jobwait with timeout 0 returns -1 if still running
  local result = vim.fn.jobwait({ job_id }, 0)[1]
  return result == -1
end

-- Wait for Claude process to be ready
function M.wait_for_process_ready(buf, callback)
  local job_id = vim.b[buf].terminal_job_id
  if not job_id then
    return
  end

  local check_count = 0
  local max_checks = 300 -- 30 seconds max (Claude can take time to start)

  local function check_process()
    check_count = check_count + 1

    if check_count > max_checks then
      vim.notify('Claude process took too long to start (30s timeout)', vim.log.levels.WARN)
      return
    end

    -- Check if process is running
    if M.is_process_running(job_id) then
      -- Process is running, but let's also check if the buffer has content
      -- This helps ensure Claude has actually started and is ready
      local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
      local has_content = false
      for _, line in ipairs(lines) do
        -- Check if there's any non-empty line (Claude has output something)
        if line ~= '' then
          has_content = true
          break
        end
      end

      if has_content then
        -- Claude has started and produced output, now safe to send commands
        -- Add a small delay to ensure it's fully ready
        vim.defer_fn(function()
          if callback then
            callback()
          end
        end, 500)
      else
        -- Process running but no output yet, keep waiting
        vim.defer_fn(check_process, 100)
      end
    else
      -- Process not running yet, check again
      vim.defer_fn(check_process, 100)
    end
  end

  -- Start checking after initial delay
  vim.defer_fn(check_process, 2000) -- Wait 2 seconds before first check
end

-- Find Claude terminal buffer
function M.find_terminal()
  -- First check if buffer is in a window
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    local buf = vim.api.nvim_win_get_buf(win)
    if vim.b[buf].is_pairup_assistant and vim.b[buf].provider == 'claude' then
      return buf, win, vim.b[buf].terminal_job_id
    end
  end

  -- If not in a window, search all buffers
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_valid(buf) and vim.b[buf].is_pairup_assistant and vim.b[buf].provider == 'claude' then
      return buf, nil, vim.b[buf].terminal_job_id
    end
  end

  return nil, nil, nil
end

-- Send message to Claude terminal
function M.send_to_terminal(message)
  local buf, win, job_id = M.find_terminal()

  if not buf or not job_id then
    vim.notify('Claude assistant not running. Use :PairupStart to begin.', vim.log.levels.WARN)
    return false
  end

  -- Send message first
  vim.fn.chansend(job_id, message)

  -- Wait for message to be processed, then send ACTUAL Enter key (not newline)
  vim.defer_fn(function()
    -- Send Control-M (carriage return) which is the actual Enter key
    vim.fn.chansend(job_id, string.char(13))

    -- Jump to end to maintain autoscroll for next output
    if win and config.get('terminal.auto_scroll') then
      vim.api.nvim_win_call(win, function()
        if vim.api.nvim_get_mode().mode ~= 't' then
          vim.cmd('norm G')
        end
      end)
    end
  end, 500)

  return true
end

-- Start Claude assistant with resume flag
function M.start_with_resume()
  -- Check if already running
  local existing_buf = M.find_terminal()
  if existing_buf then
    -- Claude assistant already running
    return false
  end

  -- Clear tracked directories for fresh session
  state.clear_directories()

  -- Get directory for Claude - prefer git root, fallback to cwd
  local git = require('pairup.utils.git')
  local git_root = git.get_root()
  local cwd = git_root or vim.fn.getcwd()

  -- Track initial directory as already added
  state.add_directory(cwd)

  -- Get Claude configuration
  local claude_config = config.get_provider_config('claude')

  -- Build claude command with --resume flag for interactive session picker
  local claude_cmd = claude_config.path .. ' --resume'

  -- Calculate split size
  local width = math.floor(vim.o.columns * config.get('terminal.split_width'))
  local position = config.get('terminal.split_position') == 'left' and 'leftabove' or 'rightbelow'

  -- Open terminal with --resume flag
  vim.cmd(string.format('%s %dvsplit term://%s//%s', position, width, cwd, claude_cmd))

  -- Mark this terminal as pairup assistant with Claude provider
  local buf = vim.api.nvim_get_current_buf()
  vim.b[buf].is_pairup_assistant = true
  vim.b[buf].provider = 'claude'
  vim.b[buf].terminal_job_id = vim.b[buf].terminal_job_id or vim.api.nvim_buf_get_var(buf, 'terminal_job_id')

  -- Store state
  state.set('claude_buf', buf)
  state.set('claude_win', vim.api.nvim_get_current_win())
  state.set('claude_job_id', vim.b[buf].terminal_job_id)

  -- Setup terminal behavior
  if config.get('terminal.auto_insert') then
    vim.cmd('startinsert')

    vim.api.nvim_create_autocmd('BufEnter', {
      buffer = buf,
      callback = function()
        vim.cmd('startinsert')
      end,
    })
  end

  -- Setup terminal navigation keymaps
  M.setup_terminal_keymaps(buf)

  -- Don't populate intent since user is resuming

  -- Return to previous window but keep terminal in insert mode
  if config.get('terminal.auto_insert') then
    vim.cmd('stopinsert')
  end
  vim.cmd('wincmd p')

  -- Update indicator
  require('pairup.utils.indicator').update()

  return true
end

-- Start Claude assistant
function M.start(intent_mode, session_id)
  -- Check if already running
  local existing_buf = M.find_terminal()
  if existing_buf then
    -- Claude assistant already running
    return false
  end

  -- If session_id provided, show which context we're working with
  if session_id then
    -- Look up the session to get its summary
    local all_sessions = sessions.get_all_project_sessions()
    for _, sess in ipairs(all_sessions) do
      if sess.id == session_id or sess.claude_session_id == session_id then
        -- Loading context from previous session
        -- Store for reference
        vim.g.pairup_context_session = sess.description
        break
      end
    end
  end

  -- Clear tracked directories for fresh session
  state.clear_directories()

  -- Get directory for Claude - prefer git root, fallback to cwd
  local git = require('pairup.utils.git')
  local git_root = git.get_root()
  local cwd = git_root or vim.fn.getcwd()

  -- Track initial directory as already added
  state.add_directory(cwd)

  -- Get Claude configuration
  local claude_config = config.get_provider_config('claude')

  -- Build claude command with directory permissions and auto-accept edits
  local claude_cmd = claude_config.path

  -- If session_id provided, try to resume it
  if session_id then
    -- Try to use --resume with the session ID
    claude_cmd = claude_cmd .. ' --resume ' .. session_id
    -- Attempting to resume session
  end
  -- Otherwise start Claude normally

  -- In test mode, use a simple echo command instead of actual Claude
  if vim.g.pairup_test_mode then
    claude_cmd = "echo 'Mock Claude CLI running'"
  else
    -- Only add flags when not in test mode
    if claude_config.add_dir_on_start then
      claude_cmd = claude_cmd .. ' --add-dir ' .. vim.fn.shellescape(cwd)
    end

    -- Default to plan mode unless configured otherwise
    local permission_mode = claude_config.permission_mode or 'plan'
    claude_cmd = claude_cmd .. ' --permission-mode ' .. permission_mode
  end

  -- Calculate split size
  local width = math.floor(vim.o.columns * config.get('terminal.split_width'))
  local position = config.get('terminal.split_position') == 'left' and 'leftabove' or 'rightbelow'

  -- Open terminal
  vim.cmd(string.format('%s %dvsplit term://%s//%s', position, width, cwd, claude_cmd))

  -- Mark this terminal as pairup assistant with Claude provider
  local buf = vim.api.nvim_get_current_buf()
  vim.b[buf].is_pairup_assistant = true
  vim.b[buf].provider = 'claude'
  vim.b[buf].terminal_job_id = vim.b[buf].terminal_job_id or vim.api.nvim_buf_get_var(buf, 'terminal_job_id')

  -- Store state
  state.set('claude_buf', buf)
  state.set('claude_win', vim.api.nvim_get_current_win())
  state.set('claude_job_id', vim.b[buf].terminal_job_id)

  -- Setup terminal behavior
  if config.get('terminal.auto_insert') then
    vim.cmd('startinsert')

    vim.api.nvim_create_autocmd('BufEnter', {
      buffer = buf,
      callback = function()
        vim.cmd('startinsert')
      end,
    })
  end

  -- Setup terminal navigation keymaps
  M.setup_terminal_keymaps(buf)

  -- Wait for Claude process to be ready before populating intent
  if intent_mode ~= false and config.get('auto_populate_intent') ~= false then
    M.wait_for_process_ready(buf, function()
      M.populate_intent()
    end)
  end

  -- Return to previous window but keep terminal in insert mode
  if config.get('terminal.auto_insert') then
    vim.cmd('stopinsert')
  end
  vim.cmd('wincmd p')

  -- Update indicator
  require('pairup.utils.indicator').update()

  return true
end

-- Setup terminal keymaps
function M.setup_terminal_keymaps(buf)
  -- Terminal-specific navigation with higher priority
  local keymaps = {
    ['<C-l>'] = '<C-\\><C-n><C-w>l',
    ['<C-h>'] = '<C-\\><C-n><C-w>h',
    ['<C-j>'] = '<C-\\><C-n><C-w>j',
    ['<C-k>'] = '<C-\\><C-n><C-w>k',
  }

  for key, mapping in pairs(keymaps) do
    vim.keymap.set('t', key, mapping, {
      buffer = buf,
      noremap = true,
      silent = true,
      desc = 'Navigate from Pairup terminal',
    })
  end
end

-- Toggle Claude window
function M.toggle(intent_mode, session_id)
  local buf, win = M.find_terminal()

  if win then
    -- Window is visible, hide it and pause git diff sending
    -- Don't close if it's the last window
    if #vim.api.nvim_list_wins() > 1 then
      vim.api.nvim_win_close(win, false)
    end
    config.set('enabled', false)
    require('pairup.utils.indicator').update()
    return true -- hidden
  elseif buf then
    -- Buffer exists but no window, create one and resume git diff sending
    local width = math.floor(vim.o.columns * config.get('terminal.split_width'))
    local position = config.get('terminal.split_position') == 'left' and 'leftabove' or 'rightbelow'
    vim.cmd(string.format('%s %dvsplit', position, width))
    vim.api.nvim_set_current_buf(buf)

    -- If intent mode requested and Claude process is ready, populate intent
    if intent_mode and config.get('auto_populate_intent') then
      local job_id = vim.b[buf].terminal_job_id
      -- Check if Claude process is already running
      if M.is_process_running(job_id) then
        vim.defer_fn(function()
          M.populate_intent()
        end, 100)
      else
        -- Wait for process to be ready
        M.wait_for_process_ready(buf, function()
          M.populate_intent()
        end)
      end
    else
      vim.cmd('wincmd p')
    end

    config.set('enabled', true)
    require('pairup.utils.indicator').update()
    return false -- shown
  else
    -- No Claude session exists, start one
    M.start(intent_mode, session_id)
    require('pairup.utils.indicator').update()
    return false -- shown
  end
end

-- Populate intent in Claude input
function M.populate_intent()
  local buf, win, job_id = M.find_terminal()
  if not buf or not job_id then
    return
  end

  -- Prevent double population
  if vim.b[buf].intent_populated then
    return
  end
  vim.b[buf].intent_populated = true

  -- Focus the terminal window
  if win then
    vim.api.nvim_set_current_win(win)

    -- Get current file name first
    local current_file = vim.fn.expand('#:t')
    if current_file == '' then
      current_file = 'the current file'
    end

    -- Get intent template
    local intent_template = config.get('intent_template')
      or "This is just an intent declaration. I'm planning to work on the file `%s` to..."
    local intent_text = string.format(intent_template, current_file)

    -- Check if RPC instructions are available
    local ok, rpc = pcall(require, 'pairup.rpc')
    local rpc_instructions = nil
    if ok and rpc and rpc.get_instructions then
      rpc_instructions = rpc.get_instructions()
    end

    -- Combine RPC instructions and intent if both exist
    local combined_text
    if rpc_instructions then
      -- Add the intent text directly after RPC instructions with proper newlines
      combined_text = rpc_instructions .. '\n\n' .. intent_text
    else
      combined_text = intent_text
    end

    -- Update the session intent if we have one
    if config.get('persist_sessions') then
      local current_session = sessions.get_current_session()
      if current_session then
        current_session.intent = intent_text .. ' [to be completed by user]'
        -- Will be updated when user completes and sends
      end
    end

    -- Send everything in one go
    vim.fn.chansend(job_id, combined_text)

    -- Place cursor at end of intent for user to continue typing
    vim.cmd('startinsert!')

    -- Notify user that intent is ready to be completed
    vim.defer_fn(function()
      -- Ready for intent
    end, 100)
  end
end

-- Prompt for session choice
function M.prompt_session_choice(existing_sessions)
  local choices = {}
  for i, session in ipairs(existing_sessions) do
    local date = os.date('%b %d', session.created_at)
    local desc = session.description or string.sub(session.intent or 'No intent', 1, 50)
    table.insert(choices, string.format('[%d] %s (%s)', i, desc, date))
  end
  table.insert(choices, string.format('[%d] Start a new session', #choices + 1))

  local prompt = 'Previous sessions involving this file:\n' .. table.concat(choices, '\n') .. '\nChoice: '
  local choice_str = vim.fn.input(prompt)
  local choice_num = tonumber(choice_str)

  if choice_num and choice_num > 0 and choice_num <= #existing_sessions then
    return existing_sessions[choice_num].id
  elseif choice_num == #existing_sessions + 1 then
    return 'new'
  end

  return nil
end

-- Stop Claude completely
function M.stop()
  local buf, win, job_id = M.find_terminal()

  if not buf then
    -- Claude is not running
    return
  end

  -- Close window if visible
  if win and #vim.api.nvim_list_wins() > 1 then
    vim.api.nvim_win_close(win, false)
  end

  -- Stop the job if running
  if job_id then
    vim.fn.jobstop(job_id)
  end

  -- Delete the buffer
  vim.api.nvim_buf_delete(buf, { force = true })

  -- Reset state
  state.clear()
  config.set('enabled', true)

  -- Update indicator
  require('pairup.utils.indicator').update()

  -- Claude session stopped
end

-- Extract Claude's session summary and save to pairup session store
function M.detect_and_save_claude_session()
  -- Get the current project directory path for Claude
  local cwd = vim.fn.getcwd()
  -- Claude sanitizes the path - replaces / and . with - (keeps leading dash)
  local project_path = cwd:gsub('[/.]', '-')

  -- Claude saves sessions in ~/.claude/projects/<project-path>/
  local claude_sessions_dir = vim.fn.expand('~/.claude/projects/' .. project_path .. '/')

  -- Check if the directory exists
  if vim.fn.isdirectory(claude_sessions_dir) == 0 then
    return false
  end

  -- Find the most recent session file
  local session_files = vim.fn.glob(claude_sessions_dir .. '*.jsonl', false, true)

  if #session_files > 0 then
    -- Sort by modification time to get the most recent
    table.sort(session_files, function(a, b)
      local a_stat = vim.loop.fs_stat(a)
      local b_stat = vim.loop.fs_stat(b)
      return (a_stat and a_stat.mtime.sec or 0) > (b_stat and b_stat.mtime.sec or 0)
    end)

    local latest_session = session_files[1]
    local session_id = vim.fn.fnamemodify(latest_session, ':t:r')

    -- Read the JSONL session file to extract summary
    local file = io.open(latest_session, 'r')
    if file then
      local summary = nil
      local first_user_message = nil
      local mentioned_files = {}

      -- Read all lines to find summary and extract info
      for line in file:lines() do
        local ok, data = pcall(vim.json.decode, line)
        if ok and data then
          -- Look for summary entries
          if data.type == 'summary' and data.summary then
            summary = data.summary
          end
          -- Get first user message
          if not first_user_message and data.type == 'user' and data.message then
            if data.message.content and type(data.message.content) == 'string' then
              first_user_message = data.message.content:sub(1, 200)
            elseif data.message.content and data.message.content[1] and data.message.content[1].text then
              first_user_message = data.message.content[1].text:sub(1, 200)
            end
          end
        end
      end
      file:close()

      -- Save to our own session store with Claude's summary
      local pairup_session = {
        id = session_id,
        claude_session_id = session_id,
        description = summary or 'Claude session',
        intent = first_user_message or 'No intent captured',
        files = {},
        created_at = os.time(),
        ended_at = os.time(),
      }

      -- Add current file if available
      local current_file = vim.fn.expand('%:p')
      if current_file ~= '' then
        table.insert(pairup_session.files, current_file)
      end

      -- Save the session
      sessions.save_session(pairup_session)
      -- Session saved
      return true
    end
  end
  return false
end

-- Send arbitrary message
function M.send_message(message)
  if message and message ~= '' then
    return M.send_to_terminal('\n>>> ' .. message .. '\n\n')
  end
  return false
end

-- Restore window layout to configured split width
function M.restore_layout()
  local buf, win = M.find_terminal()

  if not win then
    vim.notify('Claude window is not visible', vim.log.levels.WARN)
    return false
  end

  -- Get configured split width (default to 0.4 if not set)
  local split_width = config.get('terminal.split_width') or 0.4
  local target_width = math.floor(vim.o.columns * split_width)

  -- Get current window width
  local current_width = vim.api.nvim_win_get_width(win)

  -- Calculate the resize amount
  local resize_amount = target_width - current_width

  if resize_amount == 0 then
    return true
  end

  -- Save current window
  local current_win = vim.api.nvim_get_current_win()

  -- Focus the Claude window to resize it
  vim.api.nvim_set_current_win(win)

  -- Resize the window
  if resize_amount > 0 then
    vim.cmd(string.format('vertical resize +%d', math.abs(resize_amount)))
  else
    vim.cmd(string.format('vertical resize -%d', math.abs(resize_amount)))
  end

  -- Return to previous window
  vim.api.nvim_set_current_win(current_win)

  return true
end

return M
