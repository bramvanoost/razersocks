VERSION := $(shell sed -n 's/.*static let version = "\(.*\)"/\1/p' Sources/RazerSocksCore/CLI.swift)
PREFIX  ?= /usr/local
BIN     := dist/razersocks
ARCHIVE := dist/razersocks-$(VERSION)-macos-universal.tar.gz
ARM64   := --triple arm64-apple-macosx12.0 --scratch-path .build/universal-arm64
X86_64  := --triple x86_64-apple-macosx12.0 --scratch-path .build/universal-x86_64

.PHONY: build test universal dist install clean version

build:
	swift build -c release

test:
	swift test

# One build per architecture, joined with lipo.
universal:
	swift build -c release $(ARM64)
	swift build -c release $(X86_64)
	mkdir -p dist
	lipo -create -output $(BIN) \
		"$$(swift build -c release $(ARM64) --show-bin-path)/razersocks" \
		"$$(swift build -c release $(X86_64) --show-bin-path)/razersocks"
	codesign --force --sign - $(BIN)
	lipo $(BIN) -verify_arch arm64
	lipo $(BIN) -verify_arch x86_64

dist: universal
	tar -czf $(ARCHIVE) -C dist razersocks -C .. LICENSE README.md
	cd dist && shasum -a 256 $(notdir $(ARCHIVE)) > $(notdir $(ARCHIVE)).sha256

install: universal
	install -d $(PREFIX)/bin
	install -m 755 $(BIN) $(PREFIX)/bin/razersocks

version:
	@echo $(VERSION)

clean:
	rm -rf .build dist
