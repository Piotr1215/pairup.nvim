-- Claude provider for pairup.nvim

local M = {}
local config = require('pairup.config')
local state = require('pairup.utils.state')

-- Provider name
M.name = 'claude'

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

-- Start Claude assistant
function M.start()
  -- Check if already running
  local existing_buf = M.find_terminal()
  if existing_buf then
    vim.notify('Claude assistant already running', vim.log.levels.INFO)
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

  -- Build claude command with directory permissions and auto-accept edits
  local claude_cmd = claude_config.path

  -- In test mode, use a simple echo command instead of actual Claude
  if vim.g.pairup_test_mode then
    claude_cmd = "echo 'Mock Claude CLI running'"
  else
    -- Only add flags when not in test mode
    if claude_config.add_dir_on_start then
      claude_cmd = claude_cmd .. ' --add-dir ' .. vim.fn.shellescape(cwd)
    end

    if claude_config.permission_mode then
      claude_cmd = claude_cmd .. ' --permission-mode ' .. claude_config.permission_mode
    end
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
function M.toggle()
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
    vim.cmd('wincmd p')
    config.set('enabled', true)
    require('pairup.utils.indicator').update()
    return false -- shown
  else
    -- No Claude session exists, start one
    M.start()
    require('pairup.utils.indicator').update()
    return false -- shown
  end
end

-- Stop Claude completely
function M.stop()
  local buf, win, job_id = M.find_terminal()

  if not buf then
    vim.notify('Claude is not running', vim.log.levels.INFO)
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

  vim.notify('Claude session stopped', vim.log.levels.INFO)
end

-- Send arbitrary message
function M.send_message(message)
  if message and message ~= '' then
    return M.send_to_terminal('\n>>> ' .. message .. '\n\n')
  end
  return false
end

return M
