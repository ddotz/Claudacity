# Claudacity Makefile
# Development utilities for code quality and building

.PHONY: setup install-tools lint format format-check build clean help

# Default target
help:
	@echo "Claudacity Development Commands"
	@echo "================================"
	@echo ""
	@echo "Setup:"
	@echo "  make setup          - Install all development tools"
	@echo "  make install-tools  - Install SwiftLint and SwiftFormat via Homebrew"
	@echo ""
	@echo "Code Quality:"
	@echo "  make lint           - Run SwiftLint on source files"
	@echo "  make lint-fix       - Run SwiftLint with auto-fix"
	@echo "  make format         - Format code with SwiftFormat"
	@echo "  make format-check   - Check formatting without changing files"
	@echo "  make check          - Run both lint and format-check"
	@echo ""
	@echo "Build:"
	@echo "  make build          - Build the project (Debug)"
	@echo "  make build-release  - Build the project (Release)"
	@echo "  make clean          - Clean build artifacts"
	@echo ""
	@echo "Test:"
	@echo "  make test           - Run unit tests"
	@echo ""

# Setup and installation
setup: install-tools
	@echo "Development environment setup complete!"

install-tools:
	@echo "Installing development tools..."
	@if ! command -v brew &> /dev/null; then \
		echo "Error: Homebrew is required. Install from https://brew.sh"; \
		exit 1; \
	fi
	@echo "Installing SwiftLint..."
	@brew install swiftlint || brew upgrade swiftlint
	@echo "Installing SwiftFormat..."
	@brew install swiftformat || brew upgrade swiftformat
	@echo "Tools installed successfully!"

# Code quality
lint:
	@echo "Running SwiftLint..."
	@swiftlint lint --config .swiftlint.yml

lint-fix:
	@echo "Running SwiftLint with auto-fix..."
	@swiftlint lint --fix --config .swiftlint.yml
	@swiftlint lint --config .swiftlint.yml

format:
	@echo "Formatting code with SwiftFormat..."
	@swiftformat Claudacity --config .swiftformat

format-check:
	@echo "Checking code formatting..."
	@swiftformat Claudacity --config .swiftformat --lint

check: lint format-check
	@echo "All checks passed!"

# Build commands
build:
	@echo "Building Claudacity (Debug)..."
	@xcodebuild -project Claudacity.xcodeproj \
		-scheme Claudacity \
		-configuration Debug \
		-destination 'platform=macOS' \
		build | xcbeautify || xcodebuild -project Claudacity.xcodeproj \
		-scheme Claudacity \
		-configuration Debug \
		-destination 'platform=macOS' \
		build

build-release:
	@echo "Building Claudacity (Release)..."
	@xcodebuild -project Claudacity.xcodeproj \
		-scheme Claudacity \
		-configuration Release \
		-destination 'platform=macOS' \
		build | xcbeautify || xcodebuild -project Claudacity.xcodeproj \
		-scheme Claudacity \
		-configuration Release \
		-destination 'platform=macOS' \
		build

clean:
	@echo "Cleaning build artifacts..."
	@xcodebuild -project Claudacity.xcodeproj \
		-scheme Claudacity \
		clean
	@rm -rf DerivedData
	@echo "Clean complete!"

# Test commands
test:
	@echo "Running tests..."
	@xcodebuild -project Claudacity.xcodeproj \
		-scheme Claudacity \
		-destination 'platform=macOS' \
		test | xcbeautify || xcodebuild -project Claudacity.xcodeproj \
		-scheme Claudacity \
		-destination 'platform=macOS' \
		test
