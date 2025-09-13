#!/usr/bin/env bash

# Integration test for marker to overlay conversion with Go files
# Tests the complete flow: markers → overlays → accept all → verify result

set -e

echo "Running Go file marker to overlay integration test..."

# Create temp file for testing
TEMP_FILE="/tmp/test_main.go"
RESULT_FILE="/tmp/test_go_result.go"

# Copy test file with markers
cp test/integration/marker_overlay/main_with_markers.go "$TEMP_FILE"

# Run Neovim to process markers and accept all overlays
nvim --headless -u test/minimal_init.vim \
  -c "edit $TEMP_FILE" \
  -c "lua require('pairup').setup()" \
  -c "lua require('pairup.marker_parser_direct').parse_and_apply()" \
  -c "write! $RESULT_FILE" \
  -c "qa!"

# Compare result with expected
echo "Comparing results..."

if diff -u test/integration/marker_overlay/main_expected.go "$RESULT_FILE" > /tmp/go_diff_output.txt; then
  echo "Go test PASSED: Results match expected output"
  rm -f "$TEMP_FILE" "$RESULT_FILE" /tmp/go_diff_output.txt
  exit 0
else
  echo "Go test FAILED: Differences found:"
  cat /tmp/go_diff_output.txt
  echo ""
  echo "Expected lines: $(wc -l < test/integration/marker_overlay/main_expected.go)"
  echo "Actual lines: $(wc -l < "$RESULT_FILE")"
  # Keep files for debugging
  echo "Result file kept at: $RESULT_FILE"
  rm -f "$TEMP_FILE"
  exit 1
fi