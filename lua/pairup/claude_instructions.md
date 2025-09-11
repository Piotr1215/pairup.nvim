# Claude RPC Instructions

You can interact with Neovim through RPC commands using the luaeval approach with _A parameter.

## ⚠️ CRITICAL: Vimscript Dictionary Syntax Required!

When using `luaeval()` from command line, you MUST use **Vimscript dictionary syntax**, NOT Lua table syntax:

### ✅ CORRECT (Vimscript):
```bash
nvim --server :6666 --remote-expr "luaeval('require(\"pairup.rpc\").execute(_A)', {'line': 42, 'new_text': 'hello'})"
```
- Uses `:` for key-value pairs
- Uses `[]` for arrays
- Uses single quotes for strings

### ❌ WRONG (Lua syntax):
```bash
nvim --server :6666 --remote-expr 'luaeval("require(\"pairup.rpc\").execute(_A)", {line = 42, new_text = "hello"})'
```
- This will cause `E720: Missing colon in Dictionary` error!

## Code Suggestions (Overlays)

Use this single pattern for ALL code suggestions:

```bash
nvim --server :6666 --remote-expr "luaeval('require(\"pairup.rpc\").execute(_A)', TABLE)"
```

**CRITICAL**: TABLE must use Vimscript dictionary syntax (colons, not equals):
- Use `:` not `=` for key-value pairs
- Use `[]` for arrays, not `{}`
- Use single quotes for strings inside the dictionary

### Single Line Change
```vim
{'line': 42, 'new_text': 'const result = await fetchData();', 'reasoning': 'Added await for async operation'}
```

Complete command example:
```bash
nvim --server :6666 --remote-expr "luaeval('require(\"pairup.rpc\").execute(_A)', {'line': 42, 'new_text': 'const result = await fetchData();', 'reasoning': 'Added await for async operation'})"
```

### Multiple Line Change
```vim
{'start_line': 10, 'end_line': 15, 'new_lines': ['function calculate(x, y) {', '  const sum = x + y;', '  return sum;', '}'], 'reasoning': 'Simplified function implementation'}
```

Complete command example:
```bash
nvim --server :6666 --remote-expr "luaeval('require(\"pairup.rpc\").execute(_A)', {'start_line': 10, 'end_line': 15, 'new_lines': ['function calculate(x, y) {', '  const sum = x + y;', '  return sum;', '}'], 'reasoning': 'Simplified function implementation'})"
```

### Single Line with Variants
```vim
{'line': 15, 'variants': [{'new_text': 'export default MyComponent;', 'reasoning': 'ES6 default export'}, {'new_text': 'module.exports = MyComponent;', 'reasoning': 'CommonJS export'}]}
```

Complete command example:
```bash
nvim --server :6666 --remote-expr "luaeval('require(\"pairup.rpc\").execute(_A)', {'line': 15, 'variants': [{'new_text': 'export default MyComponent;', 'reasoning': 'ES6 default export'}, {'new_text': 'module.exports = MyComponent;', 'reasoning': 'CommonJS export'}]})"
```

### Multiple Lines with Variants
```vim
{'start_line': 20, 'end_line': 22, 'variants': [{'new_lines': ['try {', '  await processData();', '} catch (e) { console.error(e); }'], 'reasoning': 'Try-catch with console error'}, {'new_lines': ['try {', '  await processData();', '} catch (e) { throw new Error(e); }'], 'reasoning': 'Try-catch with re-throw'}]}
```

Complete command example:
```bash
nvim --server :6666 --remote-expr "luaeval('require(\"pairup.rpc\").execute(_A)', {'start_line': 20, 'end_line': 22, 'variants': [{'new_lines': ['try {', '  await processData();', '} catch (e) { console.error(e); }'], 'reasoning': 'Try-catch with console error'}, {'new_lines': ['try {', '  await processData();', '} catch (e) { throw new Error(e); }'], 'reasoning': 'Try-catch with re-throw'}]})"
```

### Delete Operations
- Single line: `{'line': 25, 'new_text': '', 'reasoning': 'Removed unused variable'}`
- Multiple lines: `{'start_line': 30, 'end_line': 35, 'new_lines': [], 'reasoning': 'Removed deprecated code'}`

## Complex Content - IMPORTANT!

**WARNING**: Complex strings with quotes are tricky. Best approach is to use double quotes for outer string and escape inner quotes:

```bash
# For simple content with single quotes:
nvim --server :6666 --remote-expr "luaeval('require(\"pairup.rpc\").execute(_A)', {'line': 42, 'new_text': 'const x = \"hello\"', 'reasoning': 'Simple quotes'})"

# For complex content, escape carefully:
nvim --server :6666 --remote-expr "luaeval('require(\"pairup.rpc\").execute(_A)', {'line': 42, 'new_text': 'const json = \"{\\\"key\\\": \\\"value\\\"}\"', 'reasoning': 'JSON string'})"
```

## Vim Commands

Execute any vim command using the same pattern:

```bash
nvim --server :6666 --remote-expr "luaeval('require(\"pairup.rpc\").execute(_A)', {'command': 'w'})"
```

Common commands:
- `{'command': 'w'}` - Save file
- `{'command': '42'}` - Jump to line 42
- `{'command': '%s/old/new/g'}` - Replace all occurrences
- `{'command': 'u'}` - Undo
- `{'command': 'normal gg'}` - Go to top of file

## Other RPC Methods

You can also call other RPC methods using the method parameter:

### Get Context
```bash
nvim --server :6666 --remote-expr "luaeval('require(\"pairup.rpc\").execute(_A)', {'method': 'get_context'})"
```

### Read Buffer
```bash
nvim --server :6666 --remote-expr "luaeval('require(\"pairup.rpc\").execute(_A)', {'method': 'read_main_buffer', 'args': {'start_line': 1, 'end_line': 50}})"
```

### List Overlays
```bash
nvim --server :6666 --remote-expr "luaeval('require(\"pairup.rpc\").execute(_A)', {'method': 'overlay_list'})"
```

### Accept/Reject Overlays
```bash
nvim --server :6666 --remote-expr "luaeval('require(\"pairup.rpc\").execute(_A)', {'method': 'overlay_accept', 'args': {'line': 42}})"
nvim --server :6666 --remote-expr "luaeval('require(\"pairup.rpc\").execute(_A)', {'method': 'overlay_reject', 'args': {'line': 42}})"
```

### Get Capabilities
```bash
nvim --server :6666 --remote-expr "luaeval('require(\"pairup.rpc\").execute(_A)', {'method': 'get_capabilities'})"
```

### Get Statistics
```bash
nvim --server :6666 --remote-expr "luaeval('require(\"pairup.rpc\").execute(_A)', {'method': 'get_stats'})"
```

## Important Rules

1. **ALWAYS use Vimscript dictionary syntax** - Colons `:` not equals `=` for key-value pairs
2. **Use double quotes for outer string** - `"luaeval('...')"` not `'luaeval("...")'`
3. **Arrays use brackets** - `[]` not `{}`
4. **Line numbers are 1-based** - First line is 1, not 0
5. **Provide clear reasoning** - Every suggestion needs an explanation
6. **Variants for alternatives** - Use when multiple approaches are valid
7. **Test your command** - If you get `E720: Missing colon`, you used Lua syntax by mistake

## When to Use Variants

- Multiple valid approaches (async/await vs promises)
- Different complexity levels (simple vs comprehensive)
- Style alternatives (verbose vs concise)
- Limit to 2-3 meaningful variants
- Order from most to least recommended

## Benefits of This Approach

1. **No escaping issues** - Complex content passes through unchanged
2. **Single pattern** - One way to do everything
3. **Lua native** - Direct table passing, no JSON parsing
4. **Robust** - Handles any content including the RPC commands themselves
5. **Simple** - Less to remember, less to go wrong