-- Claude provider for pairup.nvim

local M = {}
local config = require('pairup.config')
local session_factory = require('pairup.core.session')

M.name = 'claude'

-- Setup terminal keymaps
local function setup_terminal_keymaps(buf)
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

-- Create session instance for local Claude
local local_session = session_factory.new({
  type = 'local',
  buffer_name = 'claude-local',
  cache_prefix = 'pairup_terminal',

  -- Identify local Claude buffers
  buffer_marker = function(buf)
    return vim.b[buf].is_pairup_assistant and vim.b[buf].provider == 'claude'
  end,

  -- Generate terminal command
  terminal_cmd = function(cwd)
    local claude_config = config.get_provider_config('claude')
    local claude_cmd = claude_config.cmd

    if vim.g.pairup_test_mode then
      return "echo 'Mock Claude CLI running'"
    end

    return claude_cmd
  end,

  -- Called after terminal is created
  on_start = function(buf, job_id)
    -- Mark buffer for identification
    vim.b[buf].is_pairup_assistant = true
    vim.b[buf].provider = 'claude'

    -- Setup navigation keymaps
    setup_terminal_keymaps(buf)

    -- Respect auto_insert setting
    if not config.get('terminal.auto_insert') then
      vim.cmd('stopinsert')
    end

    -- Update indicator
    require('pairup.utils.indicator').update()
  end,

  -- Called before cleanup
  on_stop = function()
    -- Clear signs and quickfix when pairup stops
    require('pairup.signs').clear_all()
    vim.fn.setqflist({}, 'r')

    -- Update indicator
    require('pairup.utils.indicator').update()
  end,

  -- Whether to auto-scroll after sending
  should_auto_scroll = function()
    return config.get('terminal.auto_scroll')
  end,
})

-- Public API (delegates to session)

function M.is_running()
  return local_session:is_running()
end

function M.find_terminal()
  return local_session:find()
end

function M.start()
  local git = require('pairup.utils.git')
  local git_root = git.get_root()
  local cwd = git_root or vim.fn.getcwd()

  return local_session:start({ cwd = cwd })
end

function M.stop()
  local_session:stop()
end

function M.toggle()
  local width = math.floor(vim.o.columns * config.get('terminal.split_width'))
  local position = config.get('terminal.split_position') == 'left' and 'leftabove' or 'rightbelow'

  local buf, win_before = local_session:find()
  local result = local_session:toggle({
    split_width = width,
    split_position = position,
  })

  -- If we just showed a hidden buffer, respect auto_insert setting
  if buf and not win_before and not result then
    if not config.get('terminal.auto_insert') then
      vim.cmd('stopinsert')
    end
  end

  return result
end

function M.send_to_terminal(message)
  return local_session:send_message(message)
end

function M.send_message(message)
  if message and message ~= '' then
    return M.send_to_terminal('\n>>> ' .. message .. '\n\n')
  end
  return false
end

return M
