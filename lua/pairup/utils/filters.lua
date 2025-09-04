-- Diff filtering utilities for pairup.nvim

local M = {}
local config = require('pairup.config')

-- Check if diff is significant
function M.is_significant_diff(diff)
  if not diff or diff == '' then
    return false
  end

  local lines = vim.split(diff, '\n')
  local added_lines = 0
  local removed_lines = 0
  local has_non_whitespace = false
  local has_non_comment = false

  for _, line in ipairs(lines) do
    if line:match('^%+[^%+]') or line:match('^%+$') then
      added_lines = added_lines + 1
      -- Check if content after + has non-whitespace
      local content = line:sub(2) -- Remove the + prefix
      if content:match('%S') then
        has_non_whitespace = true
      end
      -- Check if it's not just a comment (basic check for common languages)
      if
        not content:match('^%s*//')
        and not content:match('^%s*#')
        and not content:match('^%s*%-%-')
        and not content:match('^%s*/%*')
        and not content:match('^%s*%*/')
      then
        has_non_comment = true
      end
    elseif line:match('^%-[^%-]') or line:match('^%-$') then
      removed_lines = removed_lines + 1
      -- Check if content after - has non-whitespace
      local content = line:sub(2) -- Remove the - prefix
      if content:match('%S') then
        has_non_whitespace = true
      end
      if
        not content:match('^%s*//')
        and not content:match('^%s*#')
        and not content:match('^%s*%-%-')
        and not content:match('^%s*/%*')
        and not content:match('^%s*%*/')
      then
        has_non_comment = true
      end
    end
  end

  local total_changes = added_lines + removed_lines

  -- Apply filters
  if total_changes < config.get('filter.min_change_lines') then
    return false
  end

  if config.get('filter.ignore_whitespace_only') and not has_non_whitespace then
    return false
  end

  if config.get('filter.ignore_comment_only') and not has_non_comment then
    return false
  end

  return true
end

return M
