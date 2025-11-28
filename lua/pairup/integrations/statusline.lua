-- Statusline integration for pairup.nvim
-- Supports: lualine (auto-inject) and native statusline (fallback)

local M = {}

-- Track if we've already injected
local injected = false

---Check if our component is already in lualine config
---@param section table lualine section (e.g., lualine_c)
---@return boolean
local function has_pairup_component(section)
  if not section then
    return false
  end
  for _, component in ipairs(section) do
    if type(component) == 'table' and component.pairup_indicator then
      return true
    end
  end
  return false
end

---Create the pairup lualine component
---@return table lualine component spec
local function create_lualine_component()
  return {
    function()
      return vim.g.pairup_indicator or ''
    end,
    color = function()
      local indicator = vim.g.pairup_indicator or ''
      if indicator:match('off') or indicator:match('error') then
        return { fg = '#ff0000', gui = 'bold' }
      elseif indicator ~= '' then
        return { fg = '#00ff00', gui = 'bold' }
      end
      return { fg = '#666666' }
    end,
    cond = function()
      return (vim.g.pairup_indicator or '') ~= ''
    end,
    pairup_indicator = true, -- marker to identify our component
  }
end

---Inject pairup component into lualine
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

  if has_pairup_component(config.sections.lualine_c) then
    return true
  end

  config.sections.lualine_c = config.sections.lualine_c or {}
  table.insert(config.sections.lualine_c, create_lualine_component())
  lualine.setup(config)

  return true
end

---Inject into native statusline
---@return boolean success
local function inject_native()
  local current = vim.o.statusline

  -- Check if already has pairup
  if current:match('pairup_indicator') then
    return true
  end

  -- If empty or default, set a reasonable statusline with pairup
  if current == '' or current == '%f' then
    vim.o.statusline = '%f %m%r%h%w%=%{g:pairup_indicator} %l,%c %P'
  else
    -- Append to existing statusline
    vim.o.statusline = current .. ' %{g:pairup_indicator}'
  end

  return true
end

---Main injection function - tries lualine first, then native
---@return boolean success
function M.inject()
  if injected then
    return true
  end

  -- Try lualine first
  if package.loaded['lualine'] then
    if inject_lualine() then
      injected = true
      return true
    end
  end

  -- Fallback to native statusline
  if inject_native() then
    injected = true
    return true
  end

  return false
end

---Setup statusline integration (called from pairup.setup)
---@param opts table pairup config
function M.setup(opts)
  if opts.statusline and opts.statusline.auto_inject == false then
    return
  end

  -- Try immediate injection
  if package.loaded['lualine'] then
    vim.schedule(function()
      M.inject()
    end)
    return
  end

  -- Wait for lualine via VeryLazy event
  vim.api.nvim_create_autocmd('User', {
    pattern = 'VeryLazy',
    once = true,
    callback = function()
      vim.schedule(function()
        M.inject()
      end)
    end,
  })

  -- Fallback: inject on first BufEnter (native or lualine)
  vim.api.nvim_create_autocmd('BufEnter', {
    once = true,
    callback = function()
      vim.schedule(function()
        M.inject()
      end)
    end,
  })
end

return M
