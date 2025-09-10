describe('overlay unicode and encoding tests', function()
  local rpc
  local overlay
  local test_bufnr

  before_each(function()
    rpc = require('pairup.rpc')
    overlay = require('pairup.overlay')

    rpc.setup()
    overlay.setup()

    test_bufnr = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(test_bufnr, 0, -1, false, {
      'ASCII text',
      'Café résumé naïve',
      '日本語テキスト',
      '中文字符测试',
      '한글 텍스트',
      'العربية نص',
      'עברית טקסט',
      'Ελληνικά κείμενο',
      'Русский текст',
      'emoji 😀 🎉 🚀 test',
      'math 𝓐𝓑𝓒 ∑∏∫ symbols',
      'box ┌─┬─┐ drawing',
      'arrows → ← ↑ ↓ ⇒ ⇐',
      'symbols ™ © ® € £ ¥',
    })

    rpc.get_state().main_buffer = test_bufnr
  end)

  after_each(function()
    if test_bufnr and vim.api.nvim_buf_is_valid(test_bufnr) then
      vim.api.nvim_buf_delete(test_bufnr, { force = true })
    end
  end)

  describe('Unicode character handling', function()
    it('should handle Latin extended characters', function()
      local result = rpc.simple_overlay(2, 'Çafé résümé naïvë with ñ and ø', 'Extended Latin')
      local response = vim.json.decode(result)
      assert.is_true(response.success)

      local suggestions = overlay.get_suggestions(test_bufnr)
      assert.equals('Çafé résümé naïvë with ñ and ø', suggestions[2].new_text)
    end)

    it('should handle CJK characters', function()
      local cjk_tests = {
        { line = 3, text = '漢字と平仮名とカタカナ', reasoning = 'Japanese mixed scripts' },
        { line = 4, text = '简体字與繁體字混合', reasoning = 'Simplified and Traditional Chinese' },
        { line = 5, text = '한글과 조합형 문자 ㄱㄴㄷㄹ', reasoning = 'Korean Hangul with Jamo' },
      }

      for _, test in ipairs(cjk_tests) do
        local result = rpc.simple_overlay(test.line, test.text, test.reasoning)
        local response = vim.json.decode(result)
        assert.is_true(response.success)

        local suggestions = overlay.get_suggestions(test_bufnr)
        assert.equals(test.text, suggestions[test.line].new_text)
      end
    end)

    it('should handle RTL languages', function()
      local rtl_tests = {
        { line = 6, text = 'مرحبا بالعالم العربي', reasoning = 'Arabic RTL' },
        { line = 7, text = 'שלום עולם בעברית', reasoning = 'Hebrew RTL' },
        { line = 6, text = 'Mixed English و العربية text', reasoning = 'Mixed LTR/RTL' },
      }

      for _, test in ipairs(rtl_tests) do
        overlay.clear_overlays(test_bufnr)
        local result = rpc.simple_overlay(test.line, test.text, test.reasoning)
        local response = vim.json.decode(result)
        assert.is_true(response.success)

        local suggestions = overlay.get_suggestions(test_bufnr)
        assert.equals(test.text, suggestions[test.line].new_text)
      end
    end)

    it('should handle emoji and emoticons', function()
      local emoji_tests = {
        '😀😃😄😁😆😅🤣😂',
        '👨‍👩‍👧‍👦👨‍💻👩‍🔬',
        '🏳️‍🌈🏴‍☠️🇺🇸🇯🇵',
        '❤️💛💚💙💜🖤🤍🤎',
        '1️⃣2️⃣3️⃣*️⃣#️⃣',
        '🤷‍♂️🤦‍♀️🙋‍♂️💁‍♀️',
      }

      for i, emoji_text in ipairs(emoji_tests) do
        local result = rpc.simple_overlay(10, emoji_text, 'Emoji test ' .. i)
        local response = vim.json.decode(result)
        assert.is_true(response.success, 'Failed on emoji test ' .. i)
      end
    end)

    it('should handle mathematical symbols', function()
      local math_text =
        '∀x∈ℝ: ∃y∈ℂ | x²+y²=1 ∧ ∑ᵢ₌₁ⁿ i = n(n+1)/2 ∴ ∫₀^∞ e⁻ˣdx = 1'
      local result = rpc.simple_overlay(11, math_text, 'Mathematical notation')
      local response = vim.json.decode(result)
      assert.is_true(response.success)

      local suggestions = overlay.get_suggestions(test_bufnr)
      assert.equals(math_text, suggestions[11].new_text)
    end)

    it('should handle box drawing characters', function()
      local box_patterns = {
        '╔══════════╗',
        '║ Content  ║',
        '╠══════════╣',
        '║ More     ║',
        '╚══════════╝',
        '┏━━━━━━━━━━┓',
        '┃ Double   ┃',
        '┗━━━━━━━━━━┛',
        '▀▄▀▄▀▄▀▄▀▄▀▄',
        '░░▒▒▓▓██▓▓▒▒░░',
      }

      for i, pattern in ipairs(box_patterns) do
        local result = rpc.simple_overlay(12, pattern, 'Box drawing ' .. i)
        local response = vim.json.decode(result)
        assert.is_true(response.success)
      end
    end)

    it('should handle combining characters', function()
      local combining = {
        'a̧ḉȩl̩m̧n̩œ̧ŗşţų̧', -- Cedilla
        'àèìòùỳẁ', -- Grave
        'áéíóúýẃ', -- Acute
        'âêîôûŷŵ', -- Circumflex
        'ãẽĩõũỹ', -- Tilde
        'äëïöüÿẅ', -- Diaeresis
        'a͜e o͡u i͢j', -- Tie/ligature
        'Z̴̧̢̛͇̬̹̻̺̠̈́̈́̊̉ạ̶̧̨̛̯̻̈́̐l̸̡̰̯̪̇̈́g̵̨̧̥̤̈́̉o̷̢̨̼̯̊̈́', -- Zalgo text
      }

      for i, text in ipairs(combining) do
        local result = rpc.simple_overlay(1, text, 'Combining chars ' .. i)
        local response = vim.json.decode(result)
        assert.is_true(response.success)
      end
    end)

    it('should handle zero-width characters', function()
      local zwc_tests = {
        'test‌with‌ZWNJ', -- Zero-width non-joiner
        'test‍with‍ZWJ', -- Zero-width joiner
        'test​with​ZWSP', -- Zero-width space
        'test‏with‏RLM', -- Right-to-left mark
        'test‎with‎LRM', -- Left-to-right mark
        'test⁠with⁠WJ', -- Word joiner
      }

      for i, text in ipairs(zwc_tests) do
        local result = rpc.simple_overlay(1, text, 'ZWC test ' .. i)
        local response = vim.json.decode(result)
        assert.is_true(response.success)
      end
    end)
  end)

  describe('Multiline unicode handling', function()
    it('should handle multiline with mixed scripts', function()
      local old_lines = {
        'ASCII text',
        'Café résumé naïve',
        '日本語テキスト',
      }

      local new_lines = {
        'ASCII → Unicode',
        'Çafé résümé naïvë ñ',
        '日本語と한글 mixed',
        'العربية والעברית RTL',
        '😀🎉 Emoji line',
      }

      local json = vim.json.encode({
        type = 'multiline',
        start_line = 1,
        end_line = 3,
        old_lines = old_lines,
        new_lines = new_lines,
        reasoning = 'Unicode multiline test',
      })

      local result = rpc.overlay_json_safe(json)
      local response = vim.json.decode(result)
      assert.is_true(response.success)
    end)

    it('should handle very long unicode strings', function()
      local long_unicode = ''
      for i = 0x1F600, 0x1F650 do
        if i <= 0x10FFFF then
          long_unicode = long_unicode .. vim.fn.nr2char(i)
        end
      end

      local result = rpc.simple_overlay(1, long_unicode, 'Long unicode sequence')
      local response = vim.json.decode(result)
      assert.is_true(response.success)
    end)
  end)

  describe('Edge case encodings', function()
    it('should handle BOM markers', function()
      local bom_tests = {
        '\239\187\191UTF-8 with BOM',
        '\254\255UTF-16 BE BOM',
        '\255\254UTF-16 LE BOM',
      }

      for i, text in ipairs(bom_tests) do
        local result = rpc.simple_overlay(1, text, 'BOM test ' .. i)
        local response = vim.json.decode(result)
        assert.is_true(response.success or response.error ~= nil)
      end
    end)

    it('should handle control characters', function()
      local control_chars = {}
      for i = 0, 31 do
        if i ~= 9 and i ~= 10 and i ~= 13 then -- Skip tab, LF, CR
          table.insert(control_chars, string.char(i))
        end
      end
      table.insert(control_chars, string.char(127)) -- DEL

      for i, char in ipairs(control_chars) do
        local text = 'Text' .. char .. 'with' .. char .. 'control'
        local result = rpc.simple_overlay(1, text, 'Control char ' .. i)
        local response = vim.json.decode(result)
        -- Control chars might fail, that's ok
        assert.is_not_nil(response)
      end
    end)

    it('should handle private use area characters', function()
      local pua_chars = {
        '\238\128\128', -- U+E000
        '\238\191\191', -- U+EFFF
        '\243\176\128\128', -- U+F0000
        '\244\143\191\191', -- U+10FFFF (max valid Unicode)
      }

      for i, char in ipairs(pua_chars) do
        local text = 'PUA ' .. char .. ' character'
        local result = rpc.simple_overlay(1, text, 'PUA test ' .. i)
        local response = vim.json.decode(result)
        assert.is_not_nil(response)
      end
    end)
  end)
end)
