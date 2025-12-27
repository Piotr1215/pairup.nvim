-- Pairup plugin entry point
if vim.g.loaded_pairup then
  return
end
vim.g.loaded_pairup = true

---@class PairupSubcommand
---@field impl fun(args:string[], opts: table) The command implementation
---@field complete? fun(subcmd_arg_lead: string): string[] (optional) Command completions callback

---@type table<string, PairupSubcommand>
local subcommand_tbl = {
  -- Core commands
  start = {
    impl = function(args, opts)
      require('pairup').start(args[1])
    end,
  },
  stop = {
    impl = function(args, opts)
      require('pairup').stop()
    end,
  },
  toggle = {
    impl = function(args, opts)
      require('pairup').toggle()
    end,
  },
  say = {
    impl = function(args, opts)
      require('pairup').send_message(table.concat(args, ' '))
    end,
  },
  -- Toggle commands
  diff = {
    impl = function(args, opts)
      require('pairup').send_diff()
    end,
  },
  lsp = {
    impl = function(args, opts)
      require('pairup').send_lsp()
    end,
  },
  -- Peripheral Claude commands
  peripheral = {
    impl = function(args, opts)
      require('pairup').peripheral_spawn()
    end,
  },
  ['peripheral-stop'] = {
    impl = function(args, opts)
      require('pairup').peripheral_stop()
    end,
  },
  ['peripheral-toggle'] = {
    impl = function(args, opts)
      require('pairup').peripheral_toggle()
    end,
  },
  ['peripheral-diff'] = {
    impl = function(args, opts)
      require('pairup').peripheral_send_diff()
    end,
  },
  -- Inline mode commands (cc:/uu: markers)
  inline = {
    impl = function(args, opts)
      require('pairup.inline').process()
    end,
  },
  markers = {
    impl = function(args)
      local filter = args[1] or 'user'
      local valid = { claude = true, user = true, proposals = true }
      if not valid[filter] then
        vim.notify('Pairup markers: expected "claude", "user", or "proposals"', vim.log.levels.ERROR)
        return
      end
      for _, win in ipairs(vim.fn.getwininfo()) do
        if win.quickfix == 1 then
          vim.cmd('cclose')
          return
        end
      end
      require('pairup.inline').update_quickfix(filter)
      vim.cmd('copen')
      vim.keymap.set('n', 'q', '<cmd>cclose<cr>', { buffer = true })
    end,
    complete = function()
      return { 'claude', 'user', 'proposals' }
    end,
  },
  suspend = {
    impl = function()
      vim.g.pairup_suspended = not vim.g.pairup_suspended
      vim.cmd('redrawstatus')
    end,
  },
  accept = {
    impl = function()
      require('pairup.conflict').accept()
    end,
  },
  edit = {
    impl = function()
      require('pairup.edit').enter()
    end,
  },
  next = {
    impl = function()
      require('pairup.conflict').next()
    end,
  },
  prev = {
    impl = function()
      require('pairup.conflict').prev()
    end,
  },
}

---@param opts table
local function pairup_cmd(opts)
  local fargs = opts.fargs
  local subcommand_key = fargs[1]
  -- Get the subcommand's arguments, if any
  local args = #fargs > 1 and vim.list_slice(fargs, 2, #fargs) or {}
  local subcommand = subcommand_tbl[subcommand_key]
  if not subcommand then
    vim.notify('Pairup: Unknown command: ' .. (subcommand_key or ''), vim.log.levels.ERROR)
    return
  end
  subcommand.impl(args, opts)
end

vim.api.nvim_create_user_command('Pairup', pairup_cmd, {
  nargs = '+',
  desc = 'Pairup AI pair programming',
  complete = function(arg_lead, cmdline, _)
    -- Get the subcommand
    local subcmd_key, subcmd_arg_lead = cmdline:match("^['<,'>]*Pairup[!]*%s(%S+)%s(.*)$")
    if subcmd_key and subcmd_arg_lead and subcommand_tbl[subcmd_key] and subcommand_tbl[subcmd_key].complete then
      return subcommand_tbl[subcmd_key].complete(subcmd_arg_lead)
    end
    -- Check if cmdline is a subcommand
    if cmdline:match("^['<,'>]*Pairup[!]*%s+%w*$") then
      local subcommand_keys = vim.tbl_keys(subcommand_tbl)
      return vim
        .iter(subcommand_keys)
        :filter(function(key)
          return key:find(arg_lead) ~= nil
        end)
        :totable()
    end
  end,
  bang = false,
})

-- <Plug> mappings for lazy.nvim compatibility
vim.keymap.set('n', '<Plug>(pairup-start)', function()
  require('pairup').start()
end, { desc = 'Start Pairup' })

vim.keymap.set('n', '<Plug>(pairup-stop)', function()
  require('pairup').stop()
end, { desc = 'Stop Pairup' })

vim.keymap.set('n', '<Plug>(pairup-toggle)', function()
  require('pairup').toggle()
end, { desc = 'Toggle Pairup' })

vim.keymap.set('n', '<Plug>(pairup-questions)', function()
  vim.cmd('Pairup markers user')
end, { desc = 'Toggle uu: questions quickfix' })

vim.keymap.set('n', '<Plug>(pairup-markers)', function()
  vim.cmd('Pairup markers claude')
end, { desc = 'Toggle cc: markers quickfix' })

vim.keymap.set('n', '<Plug>(pairup-proposals)', function()
  vim.cmd('Pairup markers proposals')
end, { desc = 'Toggle proposals quickfix' })

vim.keymap.set('n', '<Plug>(pairup-inline)', function()
  require('pairup.inline').process()
end, { desc = 'Process cc: markers' })

vim.keymap.set('n', '<Plug>(pairup-next-marker)', function()
  require('pairup.signs').next()
end, { desc = 'Jump to next cc: marker' })

vim.keymap.set('n', '<Plug>(pairup-prev-marker)', function()
  require('pairup.signs').prev()
end, { desc = 'Jump to previous cc: marker' })

vim.keymap.set('n', '<Plug>(pairup-lsp)', function()
  require('pairup').send_lsp()
end, { desc = 'Send LSP diagnostics to Claude' })

vim.keymap.set('n', '<Plug>(pairup-diff)', function()
  require('pairup').send_diff()
end, { desc = 'Send git diff to Claude' })

vim.keymap.set('n', '<Plug>(pairup-toggle-session)', function()
  local providers = require('pairup.providers')
  if providers.find_terminal() then
    require('pairup').stop()
  else
    require('pairup').start()
  end
end, { desc = 'Toggle Pairup session (start/stop)' })

vim.keymap.set('n', '<Plug>(pairup-suspend)', function()
  vim.g.pairup_suspended = not vim.g.pairup_suspended
  vim.cmd('redrawstatus')
end, { desc = 'Suspend auto-processing' })

vim.keymap.set('n', '<Plug>(pairup-accept)', function()
  require('pairup.conflict').accept()
end, { desc = 'Accept conflict section at cursor' })

vim.keymap.set('n', '<Plug>(pairup-conflict-diff)', function()
  require('pairup.conflict').diff()
end, { desc = 'Conflict diff view' })

vim.keymap.set('n', '<Plug>(pairup-proposal-edit)', function()
  require('pairup.edit').enter()
end, { desc = 'Edit proposal in floating window' })

vim.keymap.set('n', '<Plug>(pairup-proposal-next)', function()
  require('pairup.conflict').next()
end, { desc = 'Jump to next proposal' })

vim.keymap.set('n', '<Plug>(pairup-proposal-prev)', function()
  require('pairup.conflict').prev()
end, { desc = 'Jump to previous proposal' })

-- Auto-enter for proposals (when enabled in config)
local augroup = vim.api.nvim_create_augroup('PairupProposals', { clear = true })
vim.api.nvim_create_autocmd('CursorMoved', {
  group = augroup,
  callback = function()
    -- Only check if proposals.auto_enter is enabled
    local ok, config = pcall(require, 'pairup.config')
    if ok and config.get('proposals.auto_enter') then
      require('pairup.edit').maybe_auto_enter()
    end
  end,
})
