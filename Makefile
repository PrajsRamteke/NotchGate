.PHONY: build test run app install setup uninstall clean

build:
	swift build

test:
	swift test

# Run from source as "NotchGate Dev.app": macOS grants the microphone (Notch Voice) and
# Accessibility only to apps, not to bare binaries. Its log streams here; Ctrl-C quits it.
run:
	Scripts/run-dev.sh

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
