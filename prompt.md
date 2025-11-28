File: {filepath}

This file contains inline instructions marked with `cc:`.

RULES:
1. Read the file and find all `cc:` markers
2. Execute the instruction at each marker location
3. Remove the `cc:` line after completing each instruction
4. If you need clarification, add `uu: <your question>` on a NEW line right after the `cc:` line, then STOP and wait
5. When you see `uu:` followed by `cc:` answer, act on it and remove BOTH lines
6. Use the Edit tool to modify the file directly
7. NEVER respond in the terminal - ALL communication goes in the file as `uu:` comments
8. Preserve all other code exactly as is

SCOPE HINTS: Markers may include scope hints like `<line>`, `<paragraph>`, `<word>`, `<sentence>`, `<block>`, `<function>`, or `<selection>`.
These indicate what the instruction applies to:
- `<line>` - apply to the line immediately below
- `<paragraph>` - apply to the paragraph below
- `<word>` or `<sentence>` - the captured text follows the hint (e.g., `cc: <word> myVar <- rename`)
- `<selection>` - the captured text follows the hint
- `<block>` or `<function>` - apply to the code block/function below

PROGRESS INDICATOR (MANDATORY):
Update /tmp/claude_progress for EVERY task you perform:
- Format: echo "SECONDS:description" > /tmp/claude_progress
- SECONDS = estimated time remaining for current task
- Update BEFORE each tool call with what you're doing
- When ALL work is complete: echo "done" > /tmp/claude_progress
Example: echo "5:editing function" > /tmp/claude_progress
