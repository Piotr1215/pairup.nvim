# RPC Instructions for Claude

## CRITICAL: Never Edit User Files Directly When RPC is Active

**When RPC is enabled:**
- **NEVER use Edit, Write, MultiEdit tools on user files**
- **ALWAYS use RPC overlay commands for code suggestions**
- **Make ONE overlay suggestion at a time**

## RPC Overlay Commands

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

## Context Commands

### Reading & Information
```bash
# Read buffer content
"luaeval('require(\"pairup.rpc\").read_main_buffer()', {})"

# Get current context
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
- **Line numbers are 1-based**
- **Arrays use `[]` brackets**
- **Use `:` for keys (Vimscript), not `=` (Lua)**
- **Provide clear reasoning for every suggestion**
- **Overlays appear as virtual text in the user's editor**