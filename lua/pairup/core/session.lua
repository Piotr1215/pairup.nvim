-- Session abstraction for terminal-based Claude instances
-- Provides common functionality for both LOCAL and PERIPHERAL modes

local M = {}

-- Create new session instance
---@param config table Session configuration
---@return table Session instance
function M.new(config)
  vim.validate({
    type = { config.type, 'string' },
    buffer_name = { config.buffer_name, 'string' },
    cache_prefix = { config.cache_prefix, 'string' },
    buffer_marker = { config.buffer_marker, 'function' },
    terminal_cmd = { config.terminal_cmd, 'function' },
  })

  local session = {
    type = config.type,
    buffer_name = config.buffer_name,
    cache_prefix = config.cache_prefix,
    buffer_marker = config.buffer_marker,
    terminal_cmd = config.terminal_cmd,
    on_start = config.on_start,
    on_stop = config.on_stop,
    should_auto_scroll = config.should_auto_scroll,
  }

  -- Cache keys for vim.g
  local buf_cache_key = config.cache_prefix .. '_buf'
  local job_cache_key = config.cache_prefix .. '_job'

  -- Check if session is running (fast check)
  function session:is_running()
    local cached_buf = vim.g[buf_cache_key]
    return cached_buf and vim.api.nvim_buf_is_valid(cached_buf) or false
  end

  -- Find session buffer, window, and job
  function session:find()
    -- Fast path: check cache first
    local cached_buf = vim.g[buf_cache_key]
    if cached_buf and vim.api.nvim_buf_is_valid(cached_buf) then
      -- Find window if visible
      for _, win in ipairs(vim.api.nvim_list_wins()) do
        if vim.api.nvim_win_get_buf(win) == cached_buf then
          return cached_buf, win, vim.g[job_cache_key]
        end
      end
      return cached_buf, nil, vim.g[job_cache_key]
    end

    -- Cache miss or invalid - clear and do full search
    vim.g[buf_cache_key] = nil
    vim.g[job_cache_key] = nil

    -- Search visible windows first
    for _, win in ipairs(vim.api.nvim_list_wins()) do
      local buf = vim.api.nvim_win_get_buf(win)
      if self.buffer_marker(buf) then
        vim.g[buf_cache_key] = buf
        vim.g[job_cache_key] = vim.b[buf].terminal_job_id
        return buf, win, vim.b[buf].terminal_job_id
      end
    end

    -- Search all buffers
    for _, buf in ipairs(vim.api.nvim_list_bufs()) do
      if vim.api.nvim_buf_is_valid(buf) and self.buffer_marker(buf) then
        vim.g[buf_cache_key] = buf
        vim.g[job_cache_key] = vim.b[buf].terminal_job_id
        return buf, nil, vim.b[buf].terminal_job_id
      end
    end

    return nil, nil, nil
  end

  -- Send message to terminal
  function session:send_message(message)
    local buf, win, job_id = self:find()

    if not buf or not job_id then
      return false
    end

    local ok = pcall(vim.fn.chansend, job_id, message)
    if not ok then
      vim.g[buf_cache_key] = nil
      vim.g[job_cache_key] = nil
      return false
    end

    -- Send Enter and scroll after delay
    vim.defer_fn(function()
      pcall(vim.fn.chansend, job_id, string.char(13))

      -- Auto-scroll if configured
      if win and self.should_auto_scroll and self.should_auto_scroll() then
        vim.api.nvim_win_call(win, function()
          if vim.api.nvim_get_mode().mode ~= 't' then
            vim.cmd('norm G')
          end
        end)
      end
    end, 500)

    return true
  end

  -- Start session (spawn terminal)
  function session:start(opts)
    opts = opts or {}

    -- Don't start if already running
    local existing_buf = self:find()
    if existing_buf then
      return false
    end

    local orig_buf = vim.api.nvim_get_current_buf()

    -- Create terminal buffer
    local buf = vim.api.nvim_create_buf(true, false)
    vim.api.nvim_set_current_buf(buf)

    -- Generate terminal command
    local cmd = self.terminal_cmd(opts.cwd or vim.fn.getcwd())

    -- Spawn terminal
    local job_id = vim.fn.termopen(
      cmd,
      vim.tbl_extend('force', opts.termopen_opts or {}, {
        on_exit = function()
          vim.g[buf_cache_key] = nil
          vim.g[job_cache_key] = nil
        end,
      })
    )

    if job_id <= 0 then
      vim.api.nvim_set_current_buf(orig_buf)
      vim.api.nvim_buf_delete(buf, { force = true })
      return false
    end

    -- Set buffer name
    pcall(vim.api.nvim_buf_set_name, buf, self.buffer_name)

    -- Mark buffer for identification
    vim.b[buf].terminal_job_id = job_id

    -- Cache for fast lookup
    vim.g[buf_cache_key] = buf
    vim.g[job_cache_key] = job_id

    -- Restore original buffer
    vim.api.nvim_set_current_buf(orig_buf)

    -- Call on_start hook
    if self.on_start then
      self.on_start(buf, job_id)
    end

    return true
  end

  -- Stop session (cleanup everything)
  function session:stop()
    local buf, win, job_id = self:find()

    if not buf then
      return
    end

    -- Call on_stop hook before cleanup
    if self.on_stop then
      self.on_stop()
    end

    -- Close window if exists
    if win and #vim.api.nvim_list_wins() > 1 then
      vim.api.nvim_win_close(win, false)
    end

    -- Stop job
    if job_id then
      vim.fn.jobstop(job_id)
    end

    -- Delete buffer
    vim.api.nvim_buf_delete(buf, { force = true })

    -- Clear cache
    vim.g[buf_cache_key] = nil
    vim.g[job_cache_key] = nil
  end

  -- Toggle session window visibility
  function session:toggle(opts)
    opts = opts or {}

    local buf, win = self:find()

    if win then
      -- Window visible: close it
      if #vim.api.nvim_list_wins() > 1 then
        vim.api.nvim_win_close(win, false)
      end
      return true
    elseif buf then
      -- Buffer exists but not visible: show it
      local width = opts.split_width or vim.o.columns
      local position = opts.split_position or 'rightbelow'
      vim.cmd(string.format('%s %dvsplit', position, width))
      vim.api.nvim_set_current_buf(buf)
      vim.cmd('wincmd p')
      return false
    else
      -- No session: start it
      self:start(opts)
      return false
    end
  end

  return session
end

return M
