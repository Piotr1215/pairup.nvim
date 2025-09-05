-- Telescope integration for pairup.nvim
local M = {}

local pickers = require('telescope.pickers')
local finders = require('telescope.finders')
local conf = require('telescope.config').values
local actions = require('telescope.actions')
local action_state = require('telescope.actions.state')
local entry_display = require('telescope.pickers.entry_display')

function M.session_picker(sessions, callback)
  if not sessions or #sessions == 0 then
    vim.notify('No sessions found', vim.log.levels.INFO)
    return
  end

  -- Prepare entries for telescope
  local entries = {}
  for _, session in ipairs(sessions) do
    table.insert(entries, session)
  end

  -- Add "New Session" option
  table.insert(entries, {
    id = 'new',
    description = 'Start a new session',
    created_at = os.time(),
    is_new = true,
  })

  local displayer = entry_display.create({
    separator = ' │ ',
    items = {
      { width = 30 }, -- Summary/description
      { width = 15 }, -- Date
      { remaining = true }, -- Session ID
    },
  })

  local make_display = function(entry)
    local session = entry.value
    local date_str = session.is_new and '' or os.date('%b %d %H:%M', session.created_at or 0)
    local desc = session.description or session.intent or 'No description'

    -- Truncate long descriptions
    if #desc > 30 then
      desc = desc:sub(1, 27) .. '...'
    end

    return displayer({
      desc,
      date_str,
      session.is_new and '' or (session.claude_session_id or session.id or ''),
    })
  end

  pickers
    .new({}, {
      prompt_title = 'Select Claude Session',
      finder = finders.new_table({
        results = entries,
        entry_maker = function(session)
          return {
            value = session,
            display = make_display,
            ordinal = (session.description or session.intent or '') .. ' ' .. (session.id or ''),
          }
        end,
      }),
      sorter = conf.generic_sorter({}),
      attach_mappings = function(prompt_bufnr, map)
        actions.select_default:replace(function()
          local selection = action_state.get_selected_entry()
          actions.close(prompt_bufnr)

          if selection and selection.value then
            callback(selection.value)
          end
        end)
        return true
      end,
    })
    :find()
end

return M
