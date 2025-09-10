# Claude RPC Instructions

You can interact with Neovim through RPC commands. Here are the available functions:

## Core Functions

### execute(command)
Execute any Vim command in the main editing window.

**Examples:**
- `execute("w")` - Save the file
- `execute("42")` - Jump to line 42
- `execute("%s/old/new/g")` - Replace all occurrences
- `execute([[%s/'old'/'new'/g]])` - Use Lua long strings for quotes

### get_context()
Get information about the current Neovim session including windows, buffers, and file status.

### read_main_buffer(start_line, end_line)
Read contents of the main editing buffer.
- `start_line`: Starting line (1-based), defaults to 1
- `end_line`: Ending line, defaults to -1 (entire buffer)

## Overlay Functions

When suggesting code changes in Neovim, you have exactly TWO overlay functions available:

## 1. overlay_single(line, new_text, reasoning)
For changing a single line of code.

**Parameters:**
- `line`: Line number (1-based)
- `new_text`: The replacement text (use empty string "" to delete)
- `reasoning`: Clear explanation of why this change is needed

## 2. overlay_multiline(start_line, end_line, new_lines, reasoning)
For changing multiple consecutive lines.

**Parameters:**
- `start_line`: First line number to replace (1-based)
- `end_line`: Last line number to replace (inclusive)
- `new_lines`: Array of replacement lines (use empty array [] to delete)
- `reasoning`: Clear explanation of why this change is needed

## Important Rules:
1. ALWAYS use these functions for code suggestions - never try to edit files directly
2. ALWAYS provide a clear reasoning for each suggestion
3. For deletions, pass empty array [] as new_lines in multiline, or empty string '' as new_text in single
4. Line numbers are 1-based (first line is 1, not 0)
5. The old text is automatically captured from the buffer - you only provide the new text
6. DO NOT use any other overlay functions - only these two exist

## Examples:

### Single line change:
```lua
overlay_single(42, "const result = await fetchData();", "Added await for async operation")
```

### Multi-line replacement:
```lua
overlay_multiline(10, 15, {
  "function calculate(x, y) {",
  "  const sum = x + y;",
  "  return sum;",
  "}"
}, "Simplified function implementation")
```

### Delete a line:
```lua
overlay_single(25, "", "Removed unused variable")
```

### Delete multiple lines:
```lua
overlay_multiline(30, 35, {}, "Removed deprecated code block")
```