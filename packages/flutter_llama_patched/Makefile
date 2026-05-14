.PHONY: help install test test-unit test-integration coverage clean format analyze

# Default target
.DEFAULT_GOAL := help

help: ## Show this help message
	@echo "Flutter Llama - Available commands:"
	@echo ""
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-20s\033[0m %s\n", $$1, $$2}'

install: ## Install dependencies
	@echo "📦 Installing dependencies..."
	@flutter pub get
	@cd example && flutter pub get
	@echo "✅ Dependencies installed"

test: test-unit ## Run all tests (default: unit tests only)

test-unit: ## Run unit tests
	@echo "🧪 Running unit tests..."
	@flutter test --reporter expanded

test-integration: ## Run integration tests (requires device)
	@echo "🔗 Running integration tests..."
	@cd example && flutter test integration_test/

test-all: ## Run all tests (unit + integration)
	@make test-unit
	@make test-integration

coverage: ## Generate test coverage report
	@echo "📊 Generating coverage report..."
	@flutter test --coverage
	@genhtml coverage/lcov.info -o coverage/html 2>/dev/null || echo "⚠️  Install lcov for HTML report: brew install lcov"
	@echo "✅ Coverage report generated: coverage/lcov.info"

coverage-html: coverage ## Generate and open HTML coverage report
	@if command -v genhtml >/dev/null 2>&1; then \
		genhtml coverage/lcov.info -o coverage/html; \
		open coverage/html/index.html 2>/dev/null || xdg-open coverage/html/index.html 2>/dev/null || echo "Open coverage/html/index.html manually"; \
	else \
		echo "❌ Install lcov first: brew install lcov"; \
	fi

format: ## Format code
	@echo "🎨 Formatting code..."
	@dart format .
	@echo "✅ Code formatted"

format-check: ## Check code formatting
	@echo "🔍 Checking code formatting..."
	@dart format --output=none --set-exit-if-changed .

analyze: ## Analyze code for issues
	@echo "🔍 Analyzing code..."
	@flutter analyze
	@echo "✅ Analysis complete"

lint: format-check analyze ## Run all linting (format check + analyze)

clean: ## Clean build artifacts
	@echo "🧹 Cleaning..."
	@flutter clean
	@cd example && flutter clean
	@rm -rf coverage/
	@echo "✅ Cleaned"

setup-ollama: ## Setup Ollama and download test model
	@echo "🤖 Setting up Ollama..."
	@if ! command -v ollama >/dev/null 2>&1; then \
		echo "Installing Ollama..."; \
		brew install ollama; \
	fi
	@echo "Starting Ollama service..."
	@ollama serve &
	@sleep 2
	@echo "Pulling test model (q2_k - 72MB)..."
	@ollama pull nativemind/braindler:q2_k
	@echo "✅ Ollama setup complete"

check-ollama: ## Check Ollama installation and models
	@echo "🔍 Checking Ollama..."
	@if command -v ollama >/dev/null 2>&1; then \
		echo "✅ Ollama installed"; \
		echo ""; \
		echo "Available models:"; \
		ollama list; \
	else \
		echo "❌ Ollama not installed"; \
		echo "Run: make setup-ollama"; \
	fi

run-example: ## Run example app
	@echo "🚀 Running example app..."
	@cd example && flutter run

build-android: ## Build Android APK
	@echo "🤖 Building Android APK..."
	@cd example && flutter build apk --release
	@echo "✅ APK built: example/build/app/outputs/flutter-apk/app-release.apk"

build-ios: ## Build iOS app
	@echo "🍎 Building iOS app..."
	@cd example && flutter build ios --release --no-codesign
	@echo "✅ iOS app built"

doctor: ## Run Flutter doctor
	@flutter doctor -v

outdated: ## Check for outdated dependencies
	@echo "📦 Checking for outdated dependencies..."
	@flutter pub outdated

upgrade: ## Upgrade dependencies
	@echo "⬆️  Upgrading dependencies..."
	@flutter pub upgrade
	@cd example && flutter pub upgrade
	@echo "✅ Dependencies upgraded"

git-status: ## Show git status and test results
	@echo "📊 Git Status:"
	@git status --short
	@echo ""
	@echo "📈 Test Statistics:"
	@echo "Unit tests: $$(grep -r "test(" test/ | wc -l | xargs) tests"
	@echo "Test files: $$(find test/ -name "*_test.dart" | wc -l | xargs) files"

stats: ## Show project statistics
	@echo "📊 Project Statistics:"
	@echo ""
	@echo "📁 Files:"
	@find lib/ -name "*.dart" | wc -l | xargs echo "  Lib files:"
	@find test/ -name "*.dart" | wc -l | xargs echo "  Test files:"
	@find example/ -name "*.dart" | wc -l | xargs echo "  Example files:"
	@echo ""
	@echo "📝 Lines of code:"
	@find lib/ -name "*.dart" -exec wc -l {} \; | awk '{sum+=$$1} END {print "  Lib: " sum}'
	@find test/ -name "*.dart" -exec wc -l {} \; | awk '{sum+=$$1} END {print "  Tests: " sum}'
	@echo ""
	@echo "🧪 Tests:"
	@grep -r "test\\|testWidgets" test/ 2>/dev/null | wc -l | xargs echo "  Total tests:"

ci: clean install lint test coverage ## Run full CI pipeline locally
	@echo "✅ CI pipeline completed successfully!"






