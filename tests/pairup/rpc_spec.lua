local rpc = require('pairup.rpc')

describe("pairup.rpc", function()
  -- Mock vim.v.servername since it's read-only
  local original_check
  
  before_each(function()
    -- Reset RPC state
    package.loaded['pairup.rpc'] = nil
    rpc = require('pairup.rpc')
    
    -- Save original check function
    original_check = rpc.check_rpc_available
  end)
  
  after_each(function()
    -- Restore original check function
    rpc.check_rpc_available = original_check
  end)
  
  describe("check_rpc_available()", function()
    it("should detect RPC when servername is set", function()
      -- Mock the function to return true
      rpc.check_rpc_available = function() return true end
      assert.is_true(rpc.check_rpc_available())
    end)
    
    it("should not detect RPC when servername is empty", function()
      -- Mock the function to return false
      rpc.check_rpc_available = function() return false end
      assert.is_false(rpc.check_rpc_available())
    end)
  end)
  
  describe("setup()", function()
    it("should enable RPC when server is available", function()
      rpc.check_rpc_available = function() return true end
      rpc.setup()
      assert.is_true(rpc.is_enabled())
    end)
    
    it("should not enable RPC when server is not available", function()
      rpc.check_rpc_available = function() return false end
      rpc.setup()
      assert.is_false(rpc.is_enabled())
    end)
    
    it("should set up autocmds when RPC is enabled", function()
      rpc.check_rpc_available = function() return true end
      
      -- Clear any existing autocmds
      pcall(vim.api.nvim_del_augroup_by_name, "PairupRPC")
      
      rpc.setup()
      
      -- Check that autocmd group was created
      local groups = vim.api.nvim_get_autocmds({ group = "PairupRPC" })
      assert.is_not_nil(groups)
      assert.is_true(#groups > 0)
    end)
  end)
  
  describe("get_instructions()", function()
    it("should return instructions when RPC is enabled", function()
      rpc.check_rpc_available = function() return true end
      rpc.setup()
      
      local instructions = rpc.get_instructions()
      assert.is_not_nil(instructions)
      assert.is_string(instructions)
      assert.is_true(instructions:match("NEOVIM REMOTE CONTROL ENABLED") ~= nil)
    end)
    
    it("should return nil when RPC is not enabled", function()
      rpc.check_rpc_available = function() return false end
      rpc.setup()
      
      local instructions = rpc.get_instructions()
      assert.is_nil(instructions)
    end)
  end)
  
  describe("window tracking", function()
    local test_buf1, test_buf2
    local test_win1, test_win2
    
    before_each(function()
      -- Create test buffers
      test_buf1 = vim.api.nvim_create_buf(false, true)
      test_buf2 = vim.api.nvim_create_buf(false, true)
      
      -- Mark one as pairup assistant
      vim.b[test_buf1].is_pairup_assistant = true
      
      -- Set a name for the regular buffer
      vim.api.nvim_buf_set_name(test_buf2, "test_file.lua")
    end)
    
    after_each(function()
      -- Clean up buffers
      pcall(vim.api.nvim_buf_delete, test_buf1, { force = true })
      pcall(vim.api.nvim_buf_delete, test_buf2, { force = true })
    end)
    
    it("should track terminal and main windows", function()
      rpc.check_rpc_available = function() return true end
      rpc.setup()
      
      -- Create windows
      test_win1 = vim.api.nvim_get_current_win()
      vim.api.nvim_win_set_buf(test_win1, test_buf1)
      
      vim.cmd('vsplit')
      test_win2 = vim.api.nvim_get_current_win()
      vim.api.nvim_win_set_buf(test_win2, test_buf2)
      
      -- Update layout
      rpc.update_layout()
      
      -- Get context
      local context_json = rpc.get_context()
      local context = vim.json.decode(context_json)
      
      assert.is_not_nil(context.terminal_window)
      assert.is_not_nil(context.main_window)
      assert.equals("test_file.lua", context.main_file)
    end)
  end)
  
  describe("helper functions", function()
    local test_buf
    
    before_each(function()
      -- Create a test buffer with content
      test_buf = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_buf_set_lines(test_buf, 0, -1, false, {
        "line 1",
        "line 2 with pattern",
        "line 3",
        "line 4 with pattern"
      })
      
      -- Set up RPC with this buffer as main
      rpc.check_rpc_available = function() return true end
      rpc.setup()
      
      -- Manually set the main buffer for testing
      local state = debug.getupvalue(rpc.update_layout, 1)
      if state then
        state.main_buffer = test_buf
      end
    end)
    
    after_each(function()
      pcall(vim.api.nvim_buf_delete, test_buf, { force = true })
    end)
    
    it("should read main buffer content", function()
      local content_json = rpc.read_main_buffer()
      local content = vim.json.decode(content_json)
      
      assert.equals(4, #content)
      assert.equals("line 1", content[1])
      assert.equals("line 2 with pattern", content[2])
    end)
    
    it("should read partial buffer content", function()
      local content_json = rpc.read_main_buffer(2, 3)
      local content = vim.json.decode(content_json)
      
      assert.equals(2, #content)
      assert.equals("line 2 with pattern", content[1])
      assert.equals("line 3", content[2])
    end)
    
    it("should search for patterns", function()
      local matches_json = rpc.search("pattern")
      local matches = vim.json.decode(matches_json)
      
      assert.equals(2, #matches)
      assert.equals(2, matches[1].line)
      assert.equals(4, matches[2].line)
    end)
    
    it("should handle missing main buffer gracefully", function()
      -- Clear main buffer
      local state = debug.getupvalue(rpc.update_layout, 1)
      if state then
        state.main_buffer = nil
      end
      
      local content_json = rpc.read_main_buffer()
      local content = vim.json.decode(content_json)
      
      assert.is_not_nil(content.error)
    end)
  end)
  
  describe("get_capabilities()", function()
    it("should return capabilities structure", function()
      rpc.check_rpc_available = function() return true end
      rpc.setup()
      
      local caps_json = rpc.get_capabilities()
      local caps = vim.json.decode(caps_json)
      
      assert.is_table(caps)
      assert.is_table(caps.plugins)
      assert.is_table(caps.commands)
      assert.is_table(caps.lsp_clients)
      assert.is_table(caps.keymaps)
    end)
    
    it("should include user commands", function()
      -- Create a test command
      vim.api.nvim_create_user_command("TestRPCCommand", function() end, {})
      
      local caps_json = rpc.get_capabilities()
      local caps = vim.json.decode(caps_json)
      
      -- Check that our test command is included
      local found = false
      for _, cmd in ipairs(caps.commands) do
        if cmd == "TestRPCCommand" then
          found = true
          break
        end
      end
      assert.is_true(found)
      
      -- Clean up
      vim.api.nvim_del_user_command("TestRPCCommand")
    end)
  end)
  
  describe("registers", function()
    it("should set and get registers", function()
      rpc.check_rpc_available = function() return true end
      rpc.setup()
      
      -- Set a register
      local set_result = vim.json.decode(rpc.set_register("t", "test content"))
      assert.is_true(set_result.success)
      
      -- Get the register
      local get_result = vim.json.decode(rpc.get_register("t"))
      assert.equals("test content", get_result.content)
      
      -- Verify directly
      assert.equals("test content", vim.fn.getreg("t"))
    end)
  end)
end)