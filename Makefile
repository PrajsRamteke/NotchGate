.PHONY: build test run app install setup uninstall clean

build:
	swift build

test:
	swift test

# Run from source (the hook binary is built alongside, so "Install hooks" works).
run: build
	swift build --product notchgate-hook
	.build/debug/NotchGate

app:
	Scripts/bundle.sh

install:
	Scripts/bundle.sh --install

# One-command setup / removal (same as ./install.sh).
setup:
	./install.sh

uninstall:
	./install.sh --uninstall

clean:
	rm -rf .build dist
