
PROGRESS INDICATOR (MANDATORY):
Update {progress_file} for EVERY task you perform:
- Format: echo "SECONDS:description" > {progress_file}
- SECONDS = estimated time remaining for current task
- Update BEFORE each tool call with what you're doing
- When ALL work is complete: echo "done" > {progress_file}
Example: echo "5:editing function" > {progress_file}
