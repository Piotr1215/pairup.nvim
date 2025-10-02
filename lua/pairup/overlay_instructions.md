# Overlay Marker Instructions for Claude (Simplified v3.0)

## 🚨 ABSOLUTELY CRITICAL: USE MARKERS FOR ALL CODE CHANGES 🚨

**NOTE**: The overlay system has been simplified. Features like variants, staging workflow, and follow mode have been removed. The core marker → overlay → accept/reject workflow remains unchanged.

**YOU MUST USE THE MARKER SYSTEM FOR ALL CODE MODIFICATIONS**

When working in pairup.nvim sessions:
- ✅ **ALWAYS** use `CLAUDE:MARKER` format for suggesting code changes
- ❌ **NEVER** directly edit files with Edit/Write tools
- ❌ **NEVER** provide raw code blocks expecting users to copy-paste
- ✅ **ALWAYS** output markers that will become interactive overlays

The marker system is THE ONLY WAY you should suggest code changes. This allows users to:
1. Review your suggestions as non-intrusive overlays
2. Cycle through multiple alternatives
3. Accept or reject changes with confidence
4. Maintain control over their codebase

**VIOLATION OF THIS RULE BREAKS THE CORE PAIRUP.NVIM WORKFLOW**

## CRITICAL: How Our Marker System Works

### Understanding Line Number Semantics

Our parser has PRECISE behavior that you MUST understand to place markers correctly:

#### Insertions (LINE_COUNT = 0)
- `CLAUDE:MARKER-N,0` inserts content **AFTER** line N
- The original line N is preserved
- Your content appears between original line N and line N+1
- Example: `CLAUDE:MARKER-8,0` after a line containing `var x = 1` will ADD new content after that variable declaration

#### Replacements (LINE_COUNT > 0)
- `CLAUDE:MARKER-N,C` replaces exactly C lines starting at line N
- Lines N through N+C-1 are removed and replaced with your content
- Example: `CLAUDE:MARKER-10,3` replaces lines 10, 11, and 12

#### Deletions (LINE_COUNT < 0)
- `CLAUDE:MARKER-N,-C` deletes exactly C lines starting at line N
- Lines N through N+C-1 are removed with NO replacement
- No content should follow a deletion marker
- Example: `CLAUDE:MARKER-15,-2` deletes lines 15 and 16

### Critical Rules for Correct Marker Placement:
1. **Line numbers ALWAYS refer to the ORIGINAL file** - before any markers are applied
2. **Count lines EXACTLY** - off-by-one errors will cause incorrect replacements
3. **Insertions happen AFTER the target line** - not before!
4. **When multiple markers target the same line**:
   - Insertions (count=0) are processed first
   - Then replacements (count>0) are processed
   - This can cause complex interactions - avoid when possible
5. **Preserve formatting precisely** - include necessary blank lines in your content

## Creating Code Suggestions with Markers

When suggesting code improvements, use the marker format to create interactive overlays that the user can accept or reject.

### Format (REASONING IS MANDATORY):
```
CLAUDE:MARKER-START_LINE,LINE_COUNT | Clear reasoning for the change
replacement line 1
replacement line 2
replacement line 3
```

### Rules:
1. **START_LINE**: The line number where the change begins (1-based) in the ORIGINAL file
2. **LINE_COUNT**:
   - Positive: Replace that many lines
   - Zero: Insert after the target line
   - Negative: Delete that many lines (no replacement content)
3. **Reasoning**: ALWAYS include a clear reason after the pipe `|`
4. The lines after the marker are the replacement/insertion text (omit for deletions)
5. Preserve exact indentation and formatting in replacement lines
6. User converts markers to overlays with `:PairMarkerToOverlay`

### Examples:

**Single line improvement:**
```python
# Current code on line 7
result = x * 2

CLAUDE:MARKER-7,1 | Added type hint for better code clarity
result: int = x * 2
```

**Multi-line refactor:**
```python
# Current code starting at line 15
def process(data):
    result = []
    for item in data:
        result.append(item * 2)
    return result

CLAUDE:MARKER-15,5 | Simplified with list comprehension for better performance
def process(data: list) -> list:
    """Process data by doubling each item."""
    return [item * 2 for item in data]
```

**Complex change with special characters:**
```javascript
// Current code at line 22
const config = {
  api: "http://localhost",
  timeout: 1000
};

CLAUDE:MARKER-22,4 | Added proper typing and environment variable support
const config: Config = {
  api: process.env.API_URL || "http://localhost:3000",
  timeout: Number(process.env.TIMEOUT) || 5000,
  headers: { "Content-Type": "application/json" }
};
```

**Removing unnecessary code:**
```python
# Current code starting at line 30
def old_function():
    print("Deprecated")
    return None

def new_function():
    return calculate()

CLAUDE:MARKER-30,-3 | Remove deprecated function that's no longer used
```

### Important Implementation Notes:
- **APPEND MARKERS TO FILE END**: Use Write/Edit tools to add markers at the END of the file
- **NEVER MODIFY CODE DIRECTLY**: Only append markers, never change existing code lines
- **MARKERS GET CONVERTED**: User runs `:PairMarkerToOverlay` to transform markers into overlays
- **MULTIPLE SUGGESTIONS**: You can provide multiple marker variants for the same location
- **USER CONTROL**: Users review overlays and accept/reject with keybindings

## 🔴 CRITICAL: How to Use Markers Correctly 🔴

### ✅ CORRECT Example - Markers at END of file:

```python
# file.py content (lines 1-10)
def process(data):
    result = []
    for item in data:
        result.append(item * 2)
    return result

def main():
    data = [1, 2, 3]
    print(process(data))

# END OF ORIGINAL FILE CONTENT
# CLAUDE ADDS MARKERS BELOW THIS LINE:

CLAUDE:MARKER-1,5 | Refactor to use list comprehension
def process(data):
    return [item * 2 for item in data]

CLAUDE:MARKER-8,1 | Add type hints to main function
def main() -> None:
```

### ❌ WRONG Example - Markers inline (NEVER DO THIS):

```python
def process(data):
    result = []
CLAUDE:MARKER-2,3 | Use list comprehension  # ❌ WRONG - INLINE
    return [item * 2 for item in data]
    for item in data:
        result.append(item * 2)
    return result
```

### The ONLY Correct Workflow:
1. Read the file to understand current code
2. Scroll to the VERY END of the file
3. Use Edit/Write to APPEND all CLAUDE:MARKER sections at the BOTTOM
4. NEVER put markers between existing code lines
5. User runs `:PairMarkerToOverlay` to convert markers to overlays

## 🚫 DO NOT:
- Place markers inline with existing code
- Insert markers in the middle of the file
- Mix markers with original content
- Modify any existing lines

## ✅ ALWAYS DO:
- Put ALL markers at the END of the file
- Keep markers together in one section at the bottom
- Leave original file content completely untouched
- Use line numbers to reference where changes should apply

The marker system ensures users maintain full control over their code while benefiting from your suggestions.

## 🔄 v3.0 Overlay System

### How to Use Overlays

**Marker Format** (unchanged):
```
CLAUDE:MARKER-START_LINE,LINE_COUNT | Reasoning for the change
replacement line 1
replacement line 2
```

**What You Can Do**:
- ✅ **Single best suggestion** - Provide one well-reasoned change per location
- ✅ **Multiline replacements** - Replace any number of lines
- ✅ **Insertions** - Use `LINE_COUNT=0` to insert after a line
- ✅ **Deletions** - Use negative `LINE_COUNT` to remove lines
- ✅ **Clear reasoning** - ALWAYS explain why the change improves the code

**User Workflow**:
```
1. You append markers to end of file
2. User runs :PairMarkerToOverlay
3. User reviews overlays (visual feedback)
4. User accepts or rejects each suggestion
   - Accept: Change applied immediately
   - Reject: Overlay removed
   - Accept all: Batch process all overlays
```

**Best Practices**:
- Provide ONE suggestion per location (no alternatives)
- Make reasoning specific and valuable
- Test your suggestions mentally before outputting
- Preserve exact indentation and formatting
- Use line numbers from ORIGINAL file (before any markers)