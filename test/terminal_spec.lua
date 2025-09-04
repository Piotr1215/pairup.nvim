describe('terminal interactions', function()
  local mock = require('test.helpers.mock')
  local pairup = require('pairup')
  local providers = require('pairup.providers')

  local cleanup_claude
  local cleanup_terminal
  local cleanup_chansend
  local sent_messages

  before_each(function()
    -- Enable test mode
    vim.g.pairup_test_mode = true

    -- Mock Claude CLI
    cleanup_claude = mock.mock_claude_cli()

    -- Mock terminal
    cleanup_terminal = mock.mock_terminal()

    -- Mock chansend and capture messages
    sent_messages, cleanup_chansend = mock.mock_chansend()

    -- Setup plugin with test configuration
    pairup.setup({
      provider = 'claude',
      providers = {
        claude = {
          path = '/usr/bin/mock-claude',
        },
      },
    })
  end)

  after_each(function()
    cleanup_claude()
    cleanup_terminal()
    cleanup_chansend()
    vim.g.pairup_test_mode = nil

    -- Clear any created buffers
    for _, buf in ipairs(vim.api.nvim_list_bufs()) do
      if vim.api.nvim_buf_is_valid(buf) and vim.b[buf].is_pairup_assistant then
        vim.api.nvim_buf_delete(buf, { force = true })
      end
    end
  end)

  it('starts terminal with correct command', function()
    local claude_provider = providers.get('claude')
    assert.is_not_nil(claude_provider)

    -- Start the provider
    local success = claude_provider.start()
    assert.is_true(success)

    -- Check that terminal buffer was created with correct markers
    local buffers = vim.api.nvim_list_bufs()
    local pairup_buf = nil

    for _, buf in ipairs(buffers) do
      if vim.b[buf].is_pairup_assistant then
        pairup_buf = buf
        break
      end
    end

    assert.is_not_nil(pairup_buf)
    assert.equals('claude', vim.b[pairup_buf].provider)
    assert.is_not_nil(vim.b[pairup_buf].terminal_job_id)
  end)

  it('sends messages to terminal', function()
    local claude_provider = providers.get('claude')
    claude_provider.start()

    -- Send a message
    local message = 'Test message to AI'
    local success = claude_provider.send_message(message)
    assert.is_true(success)

    -- Check that message was sent via chansend
    assert.is_true(#sent_messages > 0)

    local found_message = false
    for _, msg in ipairs(sent_messages) do
      if msg.data:match(message) then
        found_message = true
        break
      end
    end
    assert.is_true(found_message, 'Message should have been sent to terminal')
  end)

  it('handles git diff context', function()
    local claude_provider = providers.get('claude')
    claude_provider.start()

    -- Mock git diff
    local original_system = vim.fn.system
    vim.fn.system = function(cmd)
      if cmd:match('git diff') then
        return '+Line added\n-Line removed\n'
      end
      return original_system(cmd)
    end

    -- Send context
    local context = require('pairup.core.context')
    context.send_context(true)

    -- Check that diff was sent
    vim.defer_fn(function()
      local found_diff = false
      for _, msg in ipairs(sent_messages) do
        if msg.data:match('Line added') then
          found_diff = true
          break
        end
      end
      assert.is_true(found_diff, 'Git diff should have been sent')
    end, 100)

    vim.fn.system = original_system
  end)

  it('toggles terminal visibility', function()
    local claude_provider = providers.get('claude')

    -- Start terminal
    claude_provider.start()

    -- Get the terminal buffer
    local term_buf = nil
    for _, buf in ipairs(vim.api.nvim_list_bufs()) do
      if vim.b[buf].is_pairup_assistant then
        term_buf = buf
        break
      end
    end
    assert.is_not_nil(term_buf)

    -- Mock list windows and window buffer functions for testing
    local original_list_wins = vim.api.nvim_list_wins
    local original_win_get_buf = vim.api.nvim_win_get_buf
    local original_win_close = vim.api.nvim_win_close
    local window_visible = true

    vim.api.nvim_list_wins = function()
      if window_visible then
        return { 1001, 1002 } -- At least 2 windows so we can close one
      end
      return { 1002 } -- Just one other window
    end

    vim.api.nvim_win_get_buf = function(win)
      if win == 1001 and window_visible then
        return term_buf
      end
      -- Return a valid buffer that exists but isn't the pairup buffer
      for _, buf in ipairs(vim.api.nvim_list_bufs()) do
        if buf ~= term_buf and vim.api.nvim_buf_is_valid(buf) then
          return buf
        end
      end
      return vim.api.nvim_create_buf(false, true) -- Create a scratch buffer
    end

    vim.api.nvim_win_close = function(win, force)
      if win == 1001 then
        window_visible = false
      end
    end

    -- Toggle should hide
    local hidden = claude_provider.toggle()
    assert.is_true(hidden)

    -- Toggle should show
    local shown = claude_provider.toggle()
    assert.is_false(shown)

    vim.api.nvim_list_wins = original_list_wins
    vim.api.nvim_win_get_buf = original_win_get_buf
    vim.api.nvim_win_close = original_win_close
  end)

  it('stops terminal correctly', function()
    local claude_provider = providers.get('claude')

    -- Start terminal
    claude_provider.start()

    -- Stop terminal
    claude_provider.stop()

    -- Check that no pairup buffers exist
    local pairup_buf = nil
    for _, buf in ipairs(vim.api.nvim_list_bufs()) do
      if vim.api.nvim_buf_is_valid(buf) and vim.b[buf].is_pairup_assistant then
        pairup_buf = buf
        break
      end
    end

    assert.is_nil(pairup_buf, 'Terminal buffer should be cleaned up')
  end)
end)
