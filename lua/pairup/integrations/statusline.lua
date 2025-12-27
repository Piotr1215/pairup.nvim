-- Statusline integration for pairup.nvim
-- Auto-injects into lualine or native statusline

local M = {}

local injected = false

---Check if pairup component exists in lualine section
---@param section table
---@return boolean
local function has_pairup(section)
  if not section then
    return false
  end
  for _, comp in ipairs(section) do
    if comp == 'pairup' then
      return true
    end
    if type(comp) == 'table' and comp[1] == 'pairup' then
      return true
    end
  end
  return false
end

---Inject into lualine
---@return boolean success
local function inject_lualine()
  local ok, lualine = pcall(require, 'lualine')
  if not ok then
    return false
  end

  local config = lualine.get_config()
  if not config or not config.sections then
    return false
  end

  if has_pairup(config.sections.lualine_c) then
    return true -- Already there
  end

  -- Add 'pairup' component (loads from lua/lualine/components/pairup.lua)
  config.sections.lualine_c = config.sections.lualine_c or {}
  table.insert(config.sections.lualine_c, 'pairup')
  lualine.setup(config)

  return true
end

---Inject into native statusline
---@return boolean success
local function inject_native()
  local current = vim.o.statusline

  if current:match('pairup_indicator') or current:match('luaeval.*pairup') then
    return true
  end

  -- Use Lua function to get colored display
  local display_func = '%{%v:lua.require("pairup.utils.indicator").get_colored_display()%}'

  if current == '' or current == '%f' then
    vim.o.statusline = '%f %m%r%h%w%=' .. display_func .. ' %l,%c %P'
  else
    vim.o.statusline = current .. ' ' .. display_func
  end

  return true
end

---Setup statusline integration
---@param opts table pairup config
function M.setup(opts)
  if opts.statusline and opts.statusline.auto_inject == false then
    return
  end

  if injected then
    return
  end

  vim.schedule(function()
    if injected then
      return
    end

    -- Try lualine first
    if package.loaded['lualine'] then
      if inject_lualine() then
        injected = true
        return
      end
    end

    -- Fallback to native
    if inject_native() then
      injected = true
    end
  end)
end

return M
