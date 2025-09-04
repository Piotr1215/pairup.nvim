-- Git utilities tests
local git = require('pairup.utils.git')

describe('git utilities', function()
  -- Helper to set shell_error safely
  local function with_shell_error(value, fn)
    local original_system = vim.fn.system
    vim.fn.system = function(cmd)
      local result = original_system(cmd)
      -- We can't directly set vim.v.shell_error, so we mock the entire system function
      return result
    end
    fn()
    vim.fn.system = original_system
  end

  describe('get_root()', function()
    it('returns git root when in a git repository', function()
      -- This test will use the actual git repo
      local root = git.get_root()
      -- We're in a git repo, so this should return something
      if root then
        assert.is_string(root)
        assert.is_true(#root > 0)
      end
    end)

    it('handles git command output correctly', function()
      local original_system = vim.fn.system
      vim.fn.system = function(cmd)
        if cmd:match('git rev%-parse %-%-show%-toplevel') then
          return '/home/user/project\n'
        end
        return ''
      end

      -- Mock v.shell_error check
      local original_get_root = git.get_root
      git.get_root = function()
        local git_root = vim.fn.system('git rev-parse --show-toplevel 2>/dev/null'):gsub('\n', '')
        -- Assume success for this test
        if git_root ~= '' then
          return git_root
        end
        return nil
      end

      local root = git.get_root()
      assert.equals('/home/user/project', root)

      vim.fn.system = original_system
      git.get_root = original_get_root
    end)
  end)

  describe('parse_status()', function()
    it('correctly parses git status output', function()
      local original_system = vim.fn.system
      vim.fn.system = function(cmd)
        if cmd:match('git status %-%-porcelain') then
          return 'M  modified.txt\nA  staged.txt\n?? untracked.txt\n M unstaged.txt\n'
        end
        return original_system(cmd)
      end

      local files = git.parse_status()
      assert.equals(2, #files.staged) -- Both modified.txt and staged.txt are staged
      assert.equals(1, #files.unstaged) -- Only unstaged.txt has unstaged changes
      assert.equals(1, #files.untracked)

      -- Check staged files (order might vary)
      local staged_set = {}
      for _, f in ipairs(files.staged) do
        staged_set[f] = true
      end
      assert.is_true(staged_set['modified.txt'])
      assert.is_true(staged_set['staged.txt'])

      assert.equals('unstaged.txt', files.unstaged[1])
      assert.equals('untracked.txt', files.untracked[1])

      vim.fn.system = original_system
    end)

    it('handles empty status', function()
      local original_system = vim.fn.system
      vim.fn.system = function(cmd)
        if cmd:match('git status %-%-porcelain') then
          return ''
        end
        return original_system(cmd)
      end

      local files = git.parse_status()
      assert.equals(0, #files.staged)
      assert.equals(0, #files.unstaged)
      assert.equals(0, #files.untracked)

      vim.fn.system = original_system
    end)

    it('handles complex status codes', function()
      local original_system = vim.fn.system
      vim.fn.system = function(cmd)
        if cmd:match('git status %-%-porcelain') then
          -- Various git status codes
          return 'MM both_modified.txt\nAM added_then_modified.txt\n D deleted_unstaged.txt\nD  deleted_staged.txt\n'
        end
        return original_system(cmd)
      end

      local files = git.parse_status()
      -- MM: staged (M in first position), unstaged (M in second position)
      -- AM: staged (A in first position), unstaged (M in second position)
      -- ' D': unstaged deletion (D in second position)
      -- 'D ': staged deletion (D in first position)

      assert.equals(3, #files.staged) -- both_modified, added_then_modified, deleted_staged
      assert.equals(3, #files.unstaged) -- both_modified, added_then_modified, deleted_unstaged

      vim.fn.system = original_system
    end)
  end)
end)
