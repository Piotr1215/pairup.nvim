#!/usr/bin/env bash

# Integration test for marker to overlay conversion
# Tests the complete flow: markers → overlays → accept all → verify result

set -e

echo "Running marker to overlay integration test..."

# Create temp file for testing
TEMP_FILE="/tmp/test_readme.md"
RESULT_FILE="/tmp/test_result.md"

# Copy test file with markers
cp test/integration/marker_overlay/README_with_markers.md "$TEMP_FILE"

# Run Neovim to process markers and accept all overlays
nvim --headless -u test/minimal_init.vim \
  -c "edit $TEMP_FILE" \
  -c "lua require('pairup').setup()" \
  -c "lua require('pairup.marker_parser_direct').parse_and_apply()" \
  -c "write! $RESULT_FILE" \
  -c "qa!"

# Compare result with expected
echo "Comparing results..."

if diff -u test/integration/marker_overlay/README_expected.md "$RESULT_FILE" > /tmp/diff_output.txt; then
  echo "Test PASSED: Results match expected output"
  rm -f "$TEMP_FILE" "$RESULT_FILE" /tmp/diff_output.txt
  exit 0
else
  echo "Test FAILED: Differences found:"
  cat /tmp/diff_output.txt
  echo ""
  echo "Expected lines: $(wc -l < test/integration/marker_overlay/README_expected.md)"
  echo "Actual lines: $(wc -l < "$RESULT_FILE")"
  # Keep files for debugging
  echo "Result file kept at: $RESULT_FILE"
  rm -f "$TEMP_FILE"
  exit 1
fi