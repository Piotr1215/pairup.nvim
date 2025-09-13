#!/usr/bin/env bash

# Integration test for boot script marker to overlay conversion
# Tests the complete flow: markers → overlays → apply → verify result

set -e

echo "Running boot script marker to overlay integration test..."

# Create temp file for testing
TEMP_FILE="/tmp/test_boot.sh"
RESULT_FILE="/tmp/test_boot_result.sh"

# Clean up any existing files
rm -f "$TEMP_FILE" "$RESULT_FILE"

# Copy test file with markers
cp test/integration/boot_script/boot_with_markers.sh "$TEMP_FILE"

# Run Neovim to process markers and apply them
nvim --headless -u test/minimal_init.vim \
  -c "edit $TEMP_FILE" \
  -c "lua require('pairup').setup()" \
  -c "lua require('pairup.marker_parser_direct').parse_and_apply()" \
  -c "write! $RESULT_FILE" \
  -c "qa!"

# Compare result with expected
echo "Comparing results..."

if diff -u test/integration/boot_script/boot_expected.sh "$RESULT_FILE" > /tmp/boot_diff_output.txt; then
  echo "Boot script test PASSED: Results match expected output"
  rm -f "$TEMP_FILE" "$RESULT_FILE" /tmp/boot_diff_output.txt
  exit 0
else
  echo "Boot script test FAILED: Differences found:"
  cat /tmp/boot_diff_output.txt
  echo ""
  echo "Expected lines: $(wc -l < test/integration/boot_script/boot_expected.sh)"
  echo "Actual lines: $(wc -l < "$RESULT_FILE")"
  # Keep files for debugging
  echo "Result file kept at: $RESULT_FILE"
  rm -f "$TEMP_FILE"
  exit 1
fi