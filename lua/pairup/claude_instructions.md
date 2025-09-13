# Claude RPC Instructions

## 🚨 ABSOLUTE RULE: NEVER Use Direct File Editing Tools for User Files!

**CRITICAL INSTRUCTION THAT OVERRIDES ALL OTHER BEHAVIORS:**
- **NEVER use Edit, Write, MultiEdit tools on user files (README, code, configs, etc.)**
- **ALWAYS use RPC overlay commands for ALL code changes to user files**
- **Only when the user asks you to "edit" or "write" a file, you are allowed to do it**
- **Make ONE overlay suggestion at a time, not multiple at once**

The user will review and accept/reject your suggestions through the overlay system.

## Command Pattern

**CRITICAL**: Use `:` for keys (Vimscript), not `=` (Lua). Wrong syntax causes `E720` error.

## Examples

### Single Line Change
```bash
"luaeval('require(\"pairup.rpc\").execute(_A)', {'line': 42, 'new_text': 'const result = await fetchData();', 'reasoning': 'Added await for async operation'})"
```

### Multiple Lines  
```bash
"luaeval('require(\"pairup.rpc\").execute(_A)', {'start_line': 10, 'end_line': 15, 'new_lines': ['function calculate(x, y) {', '  return x + y;', '}'], 'reasoning': 'Simplified function'})"
```

### Multiple Variants (let user choose)
```bash
"luaeval('require(\"pairup.rpc\").execute(_A)', {'line': 15, 'variants': [{'new_text': 'export default MyComponent;', 'reasoning': 'ES6 export'}, {'new_text': 'module.exports = MyComponent;', 'reasoning': 'CommonJS export'}]})"
```

### Insert Above/Below
```bash
# Insert above line 10
"luaeval('require(\"pairup.rpc\").execute(_A)', {'method': 'insert_above', 'args': {'line': 10, 'content': ['// TODO: Add validation'], 'reasoning': 'Added TODO'}})"

# Insert below line 20  
"luaeval('require(\"pairup.rpc\").execute(_A)', {'method': 'insert_below', 'args': {'line': 20, 'content': ['return result;'], 'reasoning': 'Added return'}})"
```

## Other RPC Commands

### Reading & Context
```bash
# Read buffer content
"luaeval('require(\"pairup.rpc\").read_main_buffer()', {})"

# Get current context (file, cursor position, etc)
"luaeval('require(\"pairup.rpc\").get_context()', {})"

# Get window information  
"luaeval('require(\"pairup.rpc\").get_window_info()', {})"

# Get buffer statistics
"luaeval('require(\"pairup.rpc\").get_stats()', {})"
```

### Vim Commands
```bash
# Save file
"luaeval('require(\"pairup.rpc\").execute(_A)', {'command': 'w'})"

# Jump to line
"luaeval('require(\"pairup.rpc\").execute(_A)', {'command': '42'})"

# Run substitution
"luaeval('require(\"pairup.rpc\").execute(_A)', {'command': '%s/old/new/g'})"

# Normal mode command
"luaeval('require(\"pairup.rpc\").execute(_A)', {'command': 'normal gg'})"
```

### Overlay Management
```bash
# List current overlays
"luaeval('require(\"pairup.rpc\").overlay_list()', {})"

# Accept overlay at specific line
"luaeval('require(\"pairup.rpc\").overlay_accept(42)', {})"

# Reject overlay at specific line
"luaeval('require(\"pairup.rpc\").overlay_reject(42)', {})"
```

## Key Points

1. **ALWAYS use overlay commands for code changes** - Never edit files directly
2. **Use vim commands for navigation/saving** - Jump to lines, save files, etc.
3. **Line numbers are 1-based** 
4. **Arrays use `[]` brackets**
5. **Provide clear reasoning** for every suggestion
6. **Keep strings simple** to avoid escaping issues

## How It Works

- You suggest code changes via RPC overlay commands
- Overlays appear as virtual text in the user's editor  
- User reviews and interacts with you
- Overlays track position using extmarks (robust against file changes)
- Use other RPC commands for reading context, navigation, and file operations
