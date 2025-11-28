-- vim: ft=lua tw=80
stds.nvim = {
  globals = {
    vim = { fields = {
      "g", "b", "w", "o", "bo", "wo", "go", "v", "fn", "api", "opt",
      "loop", "cmd", "ui", "fs", "keymap", "lsp", "diagnostic",
      "treesitter", "health", "inspect", "schedule", "defer_fn",
      "notify", "validate", "deprecate", "hl", "diff", "uv",
      "list_slice", "split", "trim", "tbl_deep_extend",
      "tbl_isempty", "tbl_count", "schedule_wrap", "log",
    }},
  },
}

std = "lua51+nvim"

-- Test files can have unused variables (describe, it, etc)
files["test/**/*_spec.lua"] = {
  globals = { "describe", "it", "before_each", "after_each", "pending", "assert" },
  ignore = { "211" }, -- unused variables
}

-- Ignore line length in specific files
max_line_length = 120

-- Common patterns to ignore
ignore = {
  "212", -- unused argument (common in callbacks)
}
