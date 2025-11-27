-- Claude provider for pairup.nvim

local M = {}
local config = require('pairup.config')

M.name = 'claude'

-- Check if Claude process is actually running
function M.is_process_running(job_id)
  if not job_id then
    return false
  end
  local result = vim.fn.jobwait({ job_id }, 0)[1]
  return result == -1
end

-- Find Claude terminal buffer
function M.find_terminal()
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    local buf = vim.api.nvim_win_get_buf(win)
    if vim.b[buf].is_pairup_assistant and vim.b[buf].provider == 'claude' then
      return buf, win, vim.b[buf].terminal_job_id
    end
  end

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
    return false
  end

  vim.fn.chansend(job_id, message)

  vim.defer_fn(function()
    vim.fn.chansend(job_id, string.char(13))

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
  local existing_buf = M.find_terminal()
  if existing_buf then
    return false
  end

  local git = require('pairup.utils.git')
  local git_root = git.get_root()
  local cwd = git_root or vim.fn.getcwd()

  local claude_config = config.get_provider_config('claude')
  local claude_cmd = claude_config.path

  if vim.g.pairup_test_mode then
    claude_cmd = "echo 'Mock Claude CLI running'"
  end

  local buf, job_id

  if config.get('inline.enabled') then
    local orig_buf = vim.api.nvim_get_current_buf()

    buf = vim.api.nvim_create_buf(true, false)
    vim.api.nvim_set_current_buf(buf)

    job_id = vim.fn.termopen(claude_cmd, { cwd = cwd })

    if job_id <= 0 then
      vim.api.nvim_set_current_buf(orig_buf)
      vim.api.nvim_buf_delete(buf, { force = true })
      return false
    end

    vim.b[buf].is_pairup_assistant = true
    vim.b[buf].provider = 'claude'
    vim.b[buf].terminal_job_id = job_id

    vim.api.nvim_set_current_buf(orig_buf)

    M.setup_terminal_keymaps(buf)
    require('pairup.utils.indicator').update()

    return true
  end

  -- Visible terminal mode
  local width = math.floor(vim.o.columns * config.get('terminal.split_width'))
  local position = config.get('terminal.split_position') == 'left' and 'leftabove' or 'rightbelow'

  vim.cmd(string.format('%s %dvsplit term://%s//%s', position, width, cwd, claude_cmd))

  buf = vim.api.nvim_get_current_buf()
  vim.b[buf].is_pairup_assistant = true
  vim.b[buf].provider = 'claude'
  vim.b[buf].terminal_job_id = vim.b[buf].terminal_job_id or vim.api.nvim_buf_get_var(buf, 'terminal_job_id')

  if config.get('terminal.auto_insert') then
    vim.cmd('startinsert')

    vim.api.nvim_create_autocmd('BufEnter', {
      buffer = buf,
      callback = function()
        vim.cmd('startinsert')
      end,
    })
  end

  M.setup_terminal_keymaps(buf)

  if config.get('terminal.auto_insert') then
    vim.cmd('stopinsert')
  end
  vim.cmd('wincmd p')

  require('pairup.utils.indicator').update()

  return true
end

-- Setup terminal keymaps
function M.setup_terminal_keymaps(buf)
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
    if #vim.api.nvim_list_wins() > 1 then
      vim.api.nvim_win_close(win, false)
    end
    require('pairup.utils.indicator').update()
    return true
  elseif buf then
    local width = math.floor(vim.o.columns * config.get('terminal.split_width'))
    local position = config.get('terminal.split_position') == 'left' and 'leftabove' or 'rightbelow'
    vim.cmd(string.format('%s %dvsplit', position, width))
    vim.api.nvim_set_current_buf(buf)
    vim.cmd('wincmd p')
    require('pairup.utils.indicator').update()
    return false
  else
    M.start()
    require('pairup.utils.indicator').update()
    return false
  end
end

-- Stop Claude completely
function M.stop()
  local buf, win, job_id = M.find_terminal()

  if not buf then
    return
  end

  if win and #vim.api.nvim_list_wins() > 1 then
    vim.api.nvim_win_close(win, false)
  end

  if job_id then
    vim.fn.jobstop(job_id)
  end

  vim.api.nvim_buf_delete(buf, { force = true })

  require('pairup.utils.indicator').update()
end

-- Send arbitrary message
function M.send_message(message)
  if message and message ~= '' then
    return M.send_to_terminal('\n>>> ' .. message .. '\n\n')
  end
  return false
end

return M
