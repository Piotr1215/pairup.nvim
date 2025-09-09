local helpers = require('test.helpers')

describe('pairup package validation', function()
  it('should reference the correct Claude CLI package name', function()
    local health_file = vim.fn.readfile('lua/pairup/health.lua')
    local found_correct_package = false
    local found_incorrect_package = false

    for _, line in ipairs(health_file) do
      if line:match('@anthropic%-ai/claude%-code') then
        found_correct_package = true
      end
      if line:match('@anthropic%-ai/claude%-cli') then
        found_incorrect_package = true
      end
    end

    assert.is_true(found_correct_package, 'Health check should reference @anthropic-ai/claude-code')
    assert.is_false(found_incorrect_package, 'Health check should not reference @anthropic-ai/claude-cli')
  end)

  it('should verify package integrity and authenticity', function()
    if vim.fn.executable('npm') == 0 then
      pending('npm not available')
      return
    end

    -- Verify package exists and get its integrity hash
    local integrity_cmd = 'npm view @anthropic-ai/claude-code dist.integrity 2>/dev/null'
    local integrity = vim.trim(vim.fn.system(integrity_cmd))

    -- Package must exist and have SHA-512 integrity hash
    assert.is_not_equal('', integrity, 'Package must exist in npm registry')
    assert.is_not_nil(integrity:match('^sha512%-'), 'Package must have SHA-512 integrity hash')

    -- Verify maintainers are from Anthropic
    local maintainer_cmd =
      'npm view @anthropic-ai/claude-code maintainers --json 2>/dev/null | grep -c "@anthropic.com"'
    local anthropic_count = tonumber(vim.trim(vim.fn.system(maintainer_cmd)))
    assert.is_true(anthropic_count > 0, 'Package should have maintainers from @anthropic.com')
  end)
end)
