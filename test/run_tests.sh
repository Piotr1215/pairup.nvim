#!/bin/bash

# Run pairup.nvim tests with clean environment
echo "Running pairup.nvim test suite..."
echo "================================"

nvim --headless --noplugin -u test/plenary_init.lua \
  -c "PlenaryBustedDirectory test/pairup/" \
  -c "qa!"

exit_code=$?

if [ $exit_code -eq 0 ]; then
  echo "✅ All tests passed!"
else
  echo "❌ Some tests failed. Exit code: $exit_code"
fi

exit $exit_code