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
      require('pairup').toggle_git_diff_send()
    end,
  },
  lsp = {
    impl = function(args, opts)
      require('pairup').toggle_lsp()
    end,
  },
  -- Inline mode commands (cc:/uu: markers)
  inline = {
    impl = function(args, opts)
      require('pairup.inline').process()
    end,
  },
  questions = {
    impl = function(args, opts)
      require('pairup.inline').update_quickfix()
    end,
  },
  -- Periodic updates
  ['updates-start'] = {
    impl = function(args, opts)
      require('pairup.core.periodic').start_periodic_updates()
    end,
  },
  ['updates-stop'] = {
    impl = function(args, opts)
      require('pairup.core.periodic').stop_periodic_updates()
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
  require('pairup.inline').update_quickfix()
end, { desc = 'Show uu: questions in quickfix' })

vim.keymap.set('n', '<Plug>(pairup-inline)', function()
  require('pairup.inline').process()
end, { desc = 'Process cc: markers' })
