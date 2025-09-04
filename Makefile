.PHONY: test test-verbose format clean install-hooks help

# Run tests with Plenary (default)
test:
	@echo "Running tests with Plenary..."
	@nvim --headless -l test/run_tests.lua 2>&1 | tee /tmp/pairup-test-output.txt
	@echo ""
	@echo "============================================"
	@echo "TEST SUMMARY"
	@echo "============================================"
	@echo -n "Total tests run: "
	@grep -E "Success: |Failed :" /tmp/pairup-test-output.txt | awk '{sum+=$$3} END {print sum}'
	@echo -n "Tests passed: "
	@grep "Success: " /tmp/pairup-test-output.txt | awk '{sum+=$$3} END {print sum}'
	@echo -n "Tests failed: "
	@grep "Failed : " /tmp/pairup-test-output.txt | awk '{sum+=$$3} END {if(sum=="") print 0; else print sum}'
	@echo "============================================"
	@if grep -q "Tests Failed" /tmp/pairup-test-output.txt 2>/dev/null || grep -q "^[[:space:]]*Failed : [1-9]" /tmp/pairup-test-output.txt 2>/dev/null; then rm -f /tmp/pairup-test-output.txt; exit 1; fi
	@rm -f /tmp/pairup-test-output.txt

# Run tests with output visible (not headless)
test-verbose:
	@echo "Running tests with Plenary (verbose)..."
	@nvim -l test/run_tests.lua

# Format Lua code with stylua
format:
	@stylua .

# Install git hooks
install-hooks:
	@git config core.hooksPath .githooks
	@echo "Git hooks installed. Pre-commit hook will:"
	@echo "  - Format code with stylua"
	@echo "  - Run tests"

# Clean test artifacts
clean:
	@rm -rf /tmp/lazy-test /tmp/lazy.nvim /tmp/lazy-lock.json /tmp/pairup-test-output.txt

# Help
help:
	@echo "Available targets:"
	@echo "  make test          - Run comprehensive test suite"
	@echo "  make test-verbose  - Run tests with detailed output"
	@echo "  make format        - Format code with stylua"
	@echo "  make install-hooks - Install git pre-commit hooks"
	@echo "  make clean         - Clean test artifacts"