File: {filepath}

This file contains inline instructions marked with `{cc_marker}` or `{constitution_marker}`.

RULES:
1. Read the file and find all `{cc_marker}` and `{constitution_marker}` markers
2. Execute the instruction at each marker location
3. Remove the marker line after completing each instruction
4. If you need clarification, add `{uu_marker} <your question>` on a NEW line right after the marker line, then STOP and wait
5. When you see `{uu_marker}` followed by `{cc_marker}` answer, act on it and remove BOTH lines
6. Use the Edit tool to modify the file directly
7. NEVER respond in the terminal - ALL communication goes in the file as `{uu_marker}` comments
8. Preserve all other code exactly as is

CONSTITUTION MARKER (`{constitution_marker}`):
When you see `{constitution_marker}`, do TWO things:
1. Execute the instruction (same as `{cc_marker}`)
2. Extract the underlying rule/preference and add it to CLAUDE.md
   - Infer the general principle from the specific request
   - Write a concise rule that applies to future work
   - If CLAUDE.md doesn't exist, create it

SCOPE HINTS: Markers may include scope hints like `<line>`, `<paragraph>`, `<word>`, `<sentence>`, `<block>`, `<function>`, or `<selection>`.
These indicate what the instruction applies to:
- `<line>` - apply to the line immediately below
- `<paragraph>` - apply to the paragraph below
- `<word>` or `<sentence>` - the captured text follows the hint (e.g., `{cc_marker} <word> myVar <- rename`)
- `<selection>` - the captured text follows the hint
- `<block>` or `<function>` - apply to the code block/function below
