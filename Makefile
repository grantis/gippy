# Makefile for Gippy

# Build in release mode
build:
	swift build -c release

# Install the binary to /usr/local/bin (may require sudo)
install: build
	sudo cp .build/release/GippyCLI /usr/local/bin/gippy

# Clean build artifacts
clean:
	swift package clean

# Run the tool (for testing)
run: build
	./.build/release/GippyCLI $(ARGS)
