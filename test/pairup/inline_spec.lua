-- Tests for inline conversational editing (cc:/uu: markers)
describe('pairup.inline', function()
  local inline
  local config

  before_each(function()
    -- Clear module cache
    package.loaded['pairup.inline'] = nil
    package.loaded['pairup.config'] = nil

    -- Setup config with defaults
    config = require('pairup.config')
    config.setup({})

    inline = require('pairup.inline')
  end)

  describe('detect_markers', function()
    it('should detect cc: markers in buffer', function()
      local buf = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
        'local function test()',
        '  -- cc: add error handling',
        '  return result',
        'end',
      })

      local markers = inline.detect_markers(buf)

      assert.equals(1, #markers)
      assert.equals(2, markers[1].line)
      assert.equals('cc', markers[1].type)
      assert.is_truthy(markers[1].content:match('cc:'))

      vim.api.nvim_buf_delete(buf, { force = true })
    end)

    it('should detect uu: markers in buffer', function()
      local buf = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
        'local function test()',
        '  -- uu: should this return nil on error?',
        '  return result',
        'end',
      })

      local markers = inline.detect_markers(buf)

      assert.equals(1, #markers)
      assert.equals(2, markers[1].line)
      assert.equals('uu', markers[1].type)

      vim.api.nvim_buf_delete(buf, { force = true })
    end)

    it('should detect multiple markers', function()
      local buf = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
        '-- cc: add logging',
        'local x = 1',
        '-- uu: what log level?',
        '-- cc: use INFO level',
        'local y = 2',
      })

      local markers = inline.detect_markers(buf)

      assert.equals(3, #markers)
      assert.equals('cc', markers[1].type)
      assert.equals('uu', markers[2].type)
      assert.equals('cc', markers[3].type)

      vim.api.nvim_buf_delete(buf, { force = true })
    end)

    it('should return empty table for buffer without markers', function()
      local buf = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
        'local function test()',
        '  return 42',
        'end',
      })

      local markers = inline.detect_markers(buf)

      assert.equals(0, #markers)

      vim.api.nvim_buf_delete(buf, { force = true })
    end)

    it('should handle invalid buffer', function()
      local markers = inline.detect_markers(99999)
      assert.equals(0, #markers)
    end)
  end)

  describe('has_cc_markers', function()
    it('should return true when cc: exists', function()
      local buf = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
        '-- cc: do something',
      })

      assert.is_true(inline.has_cc_markers(buf))

      vim.api.nvim_buf_delete(buf, { force = true })
    end)

    it('should return false when only uu: exists', function()
      local buf = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
        '-- uu: question here',
      })

      assert.is_false(inline.has_cc_markers(buf))

      vim.api.nvim_buf_delete(buf, { force = true })
    end)

    it('should return false for empty buffer', function()
      local buf = vim.api.nvim_create_buf(false, true)
      assert.is_false(inline.has_cc_markers(buf))
      vim.api.nvim_buf_delete(buf, { force = true })
    end)
  end)

  describe('has_uu_markers', function()
    it('should return true when uu: exists', function()
      local buf = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
        '-- uu: question here',
      })

      assert.is_true(inline.has_uu_markers(buf))

      vim.api.nvim_buf_delete(buf, { force = true })
    end)

    it('should return false when only cc: exists', function()
      local buf = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
        '-- cc: command here',
      })

      assert.is_false(inline.has_uu_markers(buf))

      vim.api.nvim_buf_delete(buf, { force = true })
    end)
  end)

  describe('build_prompt', function()
    it('should include filepath', function()
      local prompt = inline.build_prompt('/path/to/file.lua')
      assert.is_truthy(prompt:match('/path/to/file.lua'))
    end)

    it('should include marker instructions', function()
      local prompt = inline.build_prompt('/test.lua')
      assert.is_truthy(prompt:match('cc:'))
      assert.is_truthy(prompt:match('uu:'))
      assert.is_truthy(prompt:match('Edit tool'))
    end)

    it('should use custom markers from config', function()
      config.setup({
        inline = {
          markers = {
            command = 'CMD:',
            question = 'ASK:',
          },
        },
      })
      -- Need to reload inline to pick up new config
      package.loaded['pairup.inline'] = nil
      inline = require('pairup.inline')

      local prompt = inline.build_prompt('/test.lua')
      assert.is_truthy(prompt:match('CMD:'))
      assert.is_truthy(prompt:match('ASK:'))
    end)
  end)

  describe('config defaults', function()
    it('should have inline enabled by default', function()
      assert.is_true(config.get('inline.enabled'))
    end)

    it('should have default markers', function()
      assert.equals('cc:', config.get('inline.markers.command'))
      assert.equals('uu:', config.get('inline.markers.question'))
    end)

    it('should have quickfix enabled by default', function()
      assert.is_true(config.get('inline.quickfix'))
    end)
  end)
end)
