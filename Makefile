# HiDocu Monorepo Makefile

CLI_DIR = hidock-cli
CLI_EXECUTABLE = hidock-cli
CLI_BUILD_PATH = $(CLI_DIR)/.build
LIBRARY_DIR = JensenUSB

GUI_WORKSPACE = HiDocu.xcworkspace
GUI_SCHEME = HiDocu
GUI_BUILD_DIR = build/gui

.PHONY: all build release clean install hidocu test test-device help

all: build

# Build CLI (Debug)
build:
	@echo "Building $(CLI_EXECUTABLE) (Debug)..."
	@cd $(CLI_DIR) && swift build
	@echo "Built: $(CLI_BUILD_PATH)/debug/$(CLI_EXECUTABLE)"

# Build CLI (Release)
release:
	@echo "Building $(CLI_EXECUTABLE) (Release)..."
	@cd $(CLI_DIR) && swift build -c release
	@echo "Built: $(CLI_BUILD_PATH)/release/$(CLI_EXECUTABLE)"

# Build HiDocu GUI App
hidocu:
	@echo "Building HiDocu App..."
	@xcodebuild -workspace $(GUI_WORKSPACE) -scheme $(GUI_SCHEME) -configuration Release \
		-derivedDataPath $(GUI_BUILD_DIR) build 2>&1 | grep -E "(error:|warning:|BUILD SUCCEEDED|BUILD FAILED)" || true
	@echo "Built: $(GUI_BUILD_DIR)/Build/Products/Release/HiDocu.app"

# Clean build artifacts
clean:
	@echo "Cleaning..."
	@rm -rf $(GUI_BUILD_DIR)
	@cd $(CLI_DIR) && swift package clean
	@rm -rf $(CLI_BUILD_PATH)
	@echo "Done."

# Install CLI to /usr/local/bin
install: release
	@echo "Installing to /usr/local/bin/$(CLI_EXECUTABLE)..."
	@cp "$(CLI_BUILD_PATH)/release/$(CLI_EXECUTABLE)" /usr/local/bin/$(CLI_EXECUTABLE)
	@echo "Installed: /usr/local/bin/$(CLI_EXECUTABLE)"

# Run CLI
run: build
	@$(CLI_BUILD_PATH)/debug/$(CLI_EXECUTABLE) $(ARGS)

# Run Tests (Mock Mode)
test:
	@echo "Running JensenUSB Tests..."
	@cd $(LIBRARY_DIR) && swift test
	@echo "Running hidock-cli Tests..."
	@cd $(CLI_DIR) && swift test

# Run Tests (Real Device - Read-Only)
test-device:
	@echo "Running JensenUSB Device Integration Tests..."
	@cd $(LIBRARY_DIR) && TEST_MODE=REAL swift test --filter DeviceIntegrationTests
	@echo "Running hidock-cli Device Integration Tests..."
	@cd $(CLI_DIR) && TEST_MODE=REAL swift test --filter DeviceIntegrationTests

# Show help
help:
	@echo "HiDocu Monorepo Build System"
	@echo ""
	@echo "Usage: make [target]"
	@echo ""
	@echo "Targets:"
	@echo "  build    - Build CLI (Debug) (default)"
	@echo "  release  - Build CLI (Release)"
	@echo "  hidocu   - Build HiDocu GUI App"
	@echo "  clean    - Remove all build artifacts"
	@echo "  install  - Install CLI to /usr/local/bin"
	@echo "  run      - Build and run CLI (use ARGS='...' for arguments)"
	@echo "  test     - Run all tests in Mock Mode (Default)"
	@echo "  test-device - Run all tests on real device (Safe / Read-Only)"
	@echo "  help     - Show this help"
