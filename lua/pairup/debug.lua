-- Debug utilities for pairup.nvim
local M = {}

function M.check_keymaps()
  local config = require('pairup.config')
  local keymaps = config.get('keymaps')

  print('=== Pairup Keymap Debug Info ===')
  print('Config keymaps:', vim.inspect(keymaps))
  print('')

  if keymaps then
    for name, key in pairs(keymaps) do
      local mapping = vim.fn.maparg(key, 'n', false, true)
      if mapping and mapping.rhs then
        print(string.format('✓ %s (%s): %s', name, key, mapping.rhs or 'set'))
      else
        print(string.format('✗ %s (%s): NOT SET', name, key))
      end
    end
  else
    print('No keymaps configured')
  end

  print('')
  print('=== All Leader Mappings ===')
  vim.cmd('nmap <leader>')
end

function M.reload()
  -- Unload all pairup modules
  for k, _ in pairs(package.loaded) do
    if k:match('^pairup') then
      package.loaded[k] = nil
    end
  end

  -- Clear the loaded flag
  vim.g.loaded_pairup = nil

  -- Reload
  require('pairup')
  print('Pairup reloaded. Run setup again.')
end

function M.test_keymaps()
  print('Testing keymap setup...')

  local pairup = require('pairup')

  -- Clear and re-setup
  M.reload()

  pairup.setup({
    provider = 'claude',
    keymaps = {
      toggle = '<leader>pt', -- Using different keys to test
      send_context = '<leader>pc',
    },
  })

  -- Check if they were set
  vim.defer_fn(function()
    M.check_keymaps()
  end, 100)
end

return M
