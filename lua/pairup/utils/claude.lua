-- Pure functions for Claude-related operations
local M = {}

-- Build Claude command with all options
function M.build_command(config, session_id)
  local cmd_parts = { config.path or 'claude' }

  -- Add session ID if provided
  if session_id then
    table.insert(cmd_parts, '--session-id')
    table.insert(cmd_parts, session_id)
  end

  -- Add permission mode
  if config.permission_mode then
    table.insert(cmd_parts, '--permission-mode')
    table.insert(cmd_parts, config.permission_mode)
  end

  -- Add directory if configured
  if config.add_dir_on_start and config.working_dir then
    table.insert(cmd_parts, '--add-dir')
    table.insert(cmd_parts, config.working_dir)
  end

  -- Add any default args
  if config.default_args then
    for _, arg in ipairs(config.default_args) do
      table.insert(cmd_parts, arg)
    end
  end

  return cmd_parts
end

-- Generate session ID
function M.generate_session_id()
  local uuid = vim.fn.system('uuidgen')
  if uuid and uuid ~= '' then
    return uuid:gsub('\n', '')
  end

  -- Fallback to random generation
  return string.format(
    '%08x-%04x-%04x-%04x-%012x',
    math.random(0, 0xffffffff),
    math.random(0, 0xffff),
    math.random(0, 0xffff),
    math.random(0, 0xffff),
    math.random(0, 0xffffffffffff)
  )
end

-- Build terminal command string
function M.build_terminal_command(position, width, cwd, claude_cmd_parts)
  local claude_cmd = table.concat(claude_cmd_parts, ' ')
  return string.format('%s %dvsplit term://%s//%s', position, width, cwd, claude_cmd)
end

-- Format intent template with filename
function M.format_intent(template, filename)
  return string.format(template, filename or 'the current file')
end

-- Parse session choice from user input
function M.parse_session_choice(input, num_sessions)
  local choice = tonumber(input)

  if not choice then
    return nil
  end

  if choice > 0 and choice <= num_sessions then
    return choice -- Valid session index
  elseif choice == num_sessions + 1 then
    return 'new' -- New session
  end

  return nil
end

return M
