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

### overlay_list()
Get a list of all current overlay suggestions in the main buffer.

**Returns:** JSON object with:
- `success`: Boolean indicating success
- `overlays`: Array of overlay objects with line, old_text, new_text, and reasoning
- `count`: Total number of overlays

## Overlay Functions

When suggesting code changes in Neovim, you have FOUR overlay functions available:

### STANDARD OVERLAYS (Single suggestion)

## 1. overlay_single(line, new_text, reasoning)
For changing a single line of code with ONE suggestion.

**Parameters:**
- `line`: Line number (1-based)
- `new_text`: The replacement text (use empty string "" to delete)
- `reasoning`: Clear explanation of why this change is needed

## 2. overlay_multiline_json(start_line, end_line, new_lines_json, reasoning)
For changing multiple consecutive lines with ONE suggestion.

**Parameters:**
- `start_line`: First line number to replace (1-based)
- `end_line`: Last line number to replace (inclusive)
- `new_lines_json`: JSON-encoded array of replacement lines (use "[]" to delete)
- `reasoning`: Clear explanation of why this change is needed

### MULTI-VARIANT OVERLAYS (Multiple alternative suggestions)

## 3. overlay_single_variants_json(line, variants_json)
For providing MULTIPLE alternative suggestions for a single line change.

**Parameters:**
- `line`: Line number (1-based)
- `variants_json`: JSON-encoded array of variant objects, each with:
  - `new_text`: The replacement text for this variant
  - `reasoning`: Explanation for this specific variant

**Example:**
```lua
overlay_single_variants_json(42, '[{"new_text": "const data = await fetch(url);", "reasoning": "More concise with await"}, {"new_text": "const data = fetch(url).then(r => r.json());", "reasoning": "Traditional promise chain"}]')
```

## 4. overlay_multiline_variants_json(start_line, end_line, variants_json)
For providing MULTIPLE alternative suggestions for multi-line changes.

**Parameters:**
- `start_line`: First line number to replace (1-based)
- `end_line`: Last line number to replace (inclusive)
- `variants_json`: JSON-encoded array of variant objects, each with:
  - `new_lines`: Array of replacement lines for this variant
  - `reasoning`: Explanation for this specific variant

**Example:**
```lua
overlay_multiline_variants_json(10, 12, '[{"new_lines": ["async function getData() {", "  return await api.call();", "}"], "reasoning": "Async/await pattern"}, {"new_lines": ["function getData() {", "  return api.call().then(process);", "}"], "reasoning": "Promise chain pattern"}]')
```

## 5. overlay_multiline_variants_b64(start_line, end_line, variants_b64)
Alternative to overlay_multiline_variants_json using base64 encoding to avoid JSON escaping issues.

**Parameters:**
- `start_line`: First line number to replace (1-based)
- `end_line`: Last line number to replace (inclusive)
- `variants_b64`: Base64-encoded JSON array of variant objects

**Usage:** First encode your JSON to base64, then pass it:
```bash
# JSON: [{"new_lines": ["line1", "line2"], "reasoning": "reason"}]
# Base64: W3sibmV3X2xpbmVzIjogWyJsaW5lMSIsICJsaW5lMiJdLCAicmVhc29uaW5nIjogInJlYXNvbiJ9XQ==
overlay_multiline_variants_b64(10, 12, 'W3sibmV3X2xpbmVzIjogWyJsaW5lMSIsICJsaW5lMiJdLCAicmVhc29uaW5nIjogInJlYXNvbiJ9XQ==')
```

## Important Rules:
1. ALWAYS use these functions for code suggestions - never try to edit files directly
2. ALWAYS provide a clear reasoning for each suggestion (or for each variant)
3. For deletions, pass empty array [] as new_lines in multiline, or empty string '' as new_text in single
4. Line numbers are 1-based (first line is 1, not 0)
5. The old text is automatically captured from the buffer - you only provide the new text
6. Use VARIANT functions when you want to offer multiple alternatives for the user to choose from
7. Users can cycle through variants with Tab/Shift+Tab before accepting

## When to Use Multi-Variant Suggestions:
- When there are multiple valid approaches (e.g., async/await vs promises)
- When offering different levels of complexity (simple vs comprehensive)
- When providing style alternatives (verbose vs concise)
- Limit to 2-3 meaningful variants maximum
- Order variants from most recommended to least recommended

## Examples:

### Standard single line change:
```lua
overlay_single(42, "const result = await fetchData();", "Added await for async operation")
```

### Multi-variant single line (offering alternatives):
```lua
overlay_single_variants_json(15, '[{"new_text": "export default MyComponent;", "reasoning": "ES6 default export"}, {"new_text": "module.exports = MyComponent;", "reasoning": "CommonJS export"}]')
```

### Standard multi-line replacement:
```lua
overlay_multiline_json(10, 15, '["function calculate(x, y) {", "  const sum = x + y;", "  return sum;", "}"]', "Simplified function implementation")
```

### Multi-variant multi-line (offering alternatives):
```lua
overlay_multiline_variants_json(20, 22, '[{"new_lines": ["try {", "  await processData();", "} catch (e) { console.error(e); }"], "reasoning": "Try-catch with console error"}, {"new_lines": ["try {", "  await processData();", "} catch (e) { throw new Error(e); }"], "reasoning": "Try-catch with re-throw"}]')
```

### Delete a line:
```lua
overlay_single(25, "", "Removed unused variable")
```

### Delete multiple lines:
```lua
overlay_multiline_json(30, 35, "[]", "Removed deprecated code block")
```