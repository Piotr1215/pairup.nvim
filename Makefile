.PHONY: test test-verbose format clean install-hooks help

# Run tests with Plenary (default)
test:
	@echo "Running unit tests with Plenary..."
	@nvim --headless -c "PlenaryBustedDirectory test/pairup/ {minimal_init='test/minimal_init.vim'}" -c "qa!" 2>&1 | tee /tmp/pairup-test-output.txt
	@if grep -q "Tests Failed" /tmp/pairup-test-output.txt 2>/dev/null; then \
		echo ""; \
		echo "============================================"; \
		echo "UNIT TESTS FAILED - Check output above for details"; \
		echo "============================================"; \
		rm -f /tmp/pairup-test-output.txt; \
		exit 1; \
	else \
		echo ""; \
		echo "============================================"; \
		echo "UNIT TESTS PASSED"; \
		echo "============================================"; \
		rm -f /tmp/pairup-test-output.txt; \
	fi
	@echo ""
	@echo "============================================"
	@echo "ALL TESTS PASSED ✅"
	@echo "============================================"

test-integration:
	@echo "Running integration tests..."
	@failed=0; \
	for test_file in test/pairup/*_spec.lua; do \
		echo "========================================"; \
		echo "Testing: $$test_file"; \
		echo "========================================"; \
		nvim --headless -u test/minimal_init.vim -c "PlenaryBustedFile $$test_file" -c "qa!" 2>&1 | tee /tmp/test_output.txt; \
		if grep -q "Tests Failed" /tmp/test_output.txt; then \
			echo "❌ FAILED: $$test_file"; \
			failed=$$((failed + 1)); \
		else \
			echo "✅ PASSED: $$test_file"; \
		fi; \
		echo ""; \
	done; \
	rm -f /tmp/test_output.txt; \
	if [ $$failed -gt 0 ]; then \
		echo "============================================"; \
		echo "INTEGRATION TESTS FAILED: $$failed test files"; \
		echo "============================================"; \
		exit 1; \
	else \
		echo "============================================"; \
		echo "ALL INTEGRATION TESTS PASSED ✅"; \
		echo "============================================"; \
	fi

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
	@echo "  - Remind to update docs when README changes"
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
