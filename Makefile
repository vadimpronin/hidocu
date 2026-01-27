# HiDock CLI Makefile

# Build configuration
BUILD_DIR = build
EXECUTABLE = hidock-cli
SCHEME = hidock-cli
PROJECT = hidock-cli.xcodeproj

.PHONY: all build clean release install help

all: build

# Build debug version
build:
	@echo "Building $(EXECUTABLE) (Debug)..."
	@xcodebuild -project $(PROJECT) -scheme $(SCHEME) -configuration Debug \
		-derivedDataPath $(BUILD_DIR) build 2>&1 | grep -E "(error:|warning:|BUILD SUCCEEDED|BUILD FAILED)" || true
	@cp "$(BUILD_DIR)/Build/Products/Debug/$(EXECUTABLE)" "$(BUILD_DIR)/$(EXECUTABLE)" 2>/dev/null || true
	@echo "Built: $(BUILD_DIR)/$(EXECUTABLE)"

# Build release version
release:
	@echo "Building $(EXECUTABLE) (Release)..."
	@xcodebuild -project $(PROJECT) -scheme $(SCHEME) -configuration Release \
		-derivedDataPath $(BUILD_DIR) build 2>&1 | grep -E "(error:|warning:|BUILD SUCCEEDED|BUILD FAILED)" || true
	@cp "$(BUILD_DIR)/Build/Products/Release/$(EXECUTABLE)" "$(BUILD_DIR)/$(EXECUTABLE)" 2>/dev/null || true
	@echo "Built: $(BUILD_DIR)/$(EXECUTABLE)"

# Clean build artifacts
clean:
	@echo "Cleaning..."
	@rm -rf $(BUILD_DIR)
	@xcodebuild -project $(PROJECT) -scheme $(SCHEME) clean 2>/dev/null || true
	@echo "Done."

# Install to /usr/local/bin
install: release
	@echo "Installing to /usr/local/bin/$(EXECUTABLE)..."
	@cp "$(BUILD_DIR)/$(EXECUTABLE)" /usr/local/bin/$(EXECUTABLE)
	@echo "Installed: /usr/local/bin/$(EXECUTABLE)"

# Run the CLI
run: build
	@./$(BUILD_DIR)/$(EXECUTABLE) $(ARGS)

# Show help
help:
	@echo "HiDock CLI Build System"
	@echo ""
	@echo "Usage: make [target]"
	@echo ""
	@echo "Targets:"
	@echo "  build    - Build debug version (default)"
	@echo "  release  - Build release version"
	@echo "  clean    - Remove build artifacts"
	@echo "  install  - Install to /usr/local/bin (requires sudo)"
	@echo "  run      - Build and run (use ARGS='command' for arguments)"
	@echo "  help     - Show this help"
	@echo ""
	@echo "Examples:"
	@echo "  make"
	@echo "  make release"
	@echo "  make run ARGS='info'"
	@echo "  sudo make install"
