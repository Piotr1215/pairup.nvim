-- Filter utilities tests
local filters = require('pairup.utils.filters')
local config = require('pairup.config')

describe('filter utilities', function()
  before_each(function()
    -- Setup default config
    config.setup()
  end)

  describe('is_significant_diff()', function()
    it('returns false for nil or empty diff', function()
      assert.is_false(filters.is_significant_diff(nil))
      assert.is_false(filters.is_significant_diff(''))
    end)

    it('detects significant changes', function()
      local diff = [[
diff --git a/file.lua b/file.lua
+local function new_function()
+  return "hello"
+end
-old_code()
]]
      assert.is_true(filters.is_significant_diff(diff))
    end)

    it('filters whitespace-only changes when configured', function()
      config.set('filter.ignore_whitespace_only', true)

      -- Need actual diff format with + and - prefixes
      local whitespace_diff = '+  \n-\n+    '
      assert.is_false(filters.is_significant_diff(whitespace_diff))
    end)

    it('allows whitespace changes when configured', function()
      config.set('filter.ignore_whitespace_only', false)

      local whitespace_diff = [[
+  
-
+    
]]
      assert.is_true(filters.is_significant_diff(whitespace_diff))
    end)

    it('filters comment-only changes when configured', function()
      config.set('filter.ignore_comment_only', true)

      -- Lua comments with proper diff format
      local lua_comment = '+-- This is a new comment\n--- Old comment'
      assert.is_false(filters.is_significant_diff(lua_comment))

      -- JavaScript/C comments
      local js_comment = [[
+// New comment
+/* Block comment */
-// Old comment
]]
      assert.is_false(filters.is_significant_diff(js_comment))

      -- Python/Shell comments
      local py_comment = [[
+# New comment
-# Old comment
]]
      assert.is_false(filters.is_significant_diff(py_comment))
    end)

    it('allows comment changes when configured', function()
      config.set('filter.ignore_comment_only', false)

      local comment_diff = [[
+-- This is a new comment
--- Old comment
]]
      assert.is_true(filters.is_significant_diff(comment_diff))
    end)

    it('respects minimum change lines', function()
      config.set('filter.min_change_lines', 3)

      local small_diff = [[
+line1
-line2
]]
      assert.is_false(filters.is_significant_diff(small_diff))

      local larger_diff = [[
+line1
+line2
-line3
-line4
]]
      assert.is_true(filters.is_significant_diff(larger_diff))
    end)

    it('detects mixed content changes', function()
      config.set('filter.ignore_comment_only', true)

      local mixed_diff = [[
+-- New comment
+local actual_code = 'value'
-old_code()
]]
      assert.is_true(filters.is_significant_diff(mixed_diff))
    end)
  end)
end)
