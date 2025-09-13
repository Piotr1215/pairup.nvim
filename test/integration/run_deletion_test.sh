#!/usr/bin/env bash

# Integration test for deletion markers
# Tests that negative LINE_COUNT correctly deletes lines

set -e

echo "Running deletion marker integration test..."

# Create temp file for testing
TEMP_FILE="/tmp/test_deletion.py"
RESULT_FILE="/tmp/test_deletion_result.py"

# Copy test file with markers
cp test/integration/marker_overlay/deletion_test.py "$TEMP_FILE"

# Run Neovim to process markers including deletions
nvim --headless -u test/minimal_init.vim \
  -c "edit $TEMP_FILE" \
  -c "lua require('pairup').setup()" \
  -c "lua require('pairup.marker_parser_direct').parse_and_apply()" \
  -c "write! $RESULT_FILE" \
  -c "qa!"

# Compare result with expected
echo "Comparing results..."

if diff -u test/integration/marker_overlay/deletion_expected.py "$RESULT_FILE" > /tmp/deletion_diff.txt; then
  echo "Deletion test PASSED: Results match expected output"
  rm -f "$TEMP_FILE" "$RESULT_FILE" /tmp/deletion_diff.txt
  exit 0
else
  echo "Deletion test FAILED: Differences found:"
  cat /tmp/deletion_diff.txt
  echo ""
  echo "Expected lines: $(wc -l < test/integration/marker_overlay/deletion_expected.py)"
  echo "Actual lines: $(wc -l < "$RESULT_FILE")"
  # Keep files for debugging
  echo "Result file kept at: $RESULT_FILE"
  rm -f "$TEMP_FILE"
  exit 1
fi