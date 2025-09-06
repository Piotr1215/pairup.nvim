#!/bin/bash

# Run RPC tests specifically with clean environment
echo "Running RPC test suite..."
echo "================================"

nvim --headless --noplugin -u test/plenary_init.lua \
  -c "PlenaryBustedFile test/pairup/rpc_spec.lua" \
  -c "qa!"

exit_code=$?

if [ $exit_code -eq 0 ]; then
  echo "✅ All RPC tests passed!"
else
  echo "❌ Some RPC tests failed. Exit code: $exit_code"
fi

exit $exit_code