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
9. MANDATORY: Use TodoWrite for EVERY task, no matter how small:
   - BEFORE starting: Create todo with status "in_progress"
   - AFTER completing: Update todo to "completed"
   - This enables real-time progress visibility - skipping it breaks the user's workflow

CONSTITUTION MARKER (`{constitution_marker}`):
When you see `{constitution_marker}`, do TWO things:
1. Execute the instruction (same as `{cc_marker}`)
2. Extract the underlying rule/preference and add it to CLAUDE.md
   - Infer the general principle from the specific request
   - Write a concise rule that applies to future work
   - If CLAUDE.md doesn't exist, create it

PLAN MARKER (`{plan_marker}`):
When you see `{plan_marker}`, do NOT edit the code directly. Instead, wrap the target code in conflict markers showing CURRENT vs PROPOSED:

```
<<<<<<< CURRENT
original code here
=======
your proposed changes here
>>>>>>> PROPOSED
```

Remove the `{plan_marker}` line when adding conflict markers. The user will review and accept/reject manually. If you need clarification first, use `{uu_marker}` as usual.

SCOPE HINTS (optional): Markers may include scope hints to help you understand what the instruction applies to. These are hints, not commands - use your judgment:
- `<line>` - apply to the line immediately below
- `<word>` / `<WORD>` - a specific word/token (text may follow the hint)
- `<sentence>` - apply to the sentence below
- `<paragraph>` - apply to the paragraph below
- `<function>` - apply to the function below
- `<codeblock>` - apply to the fenced code block (```)
- `<file>` - apply to the entire file
- `<selection>` - captured text follows the hint (e.g., `{cc_marker} <selection> myVar <- rename`)

If no scope hint is present, infer the scope from context.
