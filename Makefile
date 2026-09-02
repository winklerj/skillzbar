APP_DST := $(HOME)/Applications/SkillzBar.app
BIN_LINK := $(HOME)/.local/bin/skillzbar

.PHONY: build release test bundle run install uninstall clean

build:            ## debug build
	swift build

release:          ## release build
	swift build -c release

test:             ## unit tests
	swift test

bundle: release   ## assemble build/SkillzBar.app
	scripts/bundle.sh

run: bundle       ## quit running instance, launch bundle
	-pkill -x SkillzBar
	open build/SkillzBar.app

install: bundle   ## copy to ~/Applications, symlink CLI to ~/.local/bin/skillzbar, relaunch
	-pkill -x SkillzBar
	mkdir -p $(HOME)/Applications $(HOME)/.local/bin
	rm -rf $(APP_DST) && cp -R build/SkillzBar.app $(APP_DST)
	ln -sf $(APP_DST)/Contents/MacOS/SkillzBar $(BIN_LINK)
	open $(APP_DST)
	@echo "installed. CLI: $(BIN_LINK) (ensure ~/.local/bin is on PATH)"

uninstall:
	-pkill -x SkillzBar
	rm -rf $(APP_DST) $(BIN_LINK)

clean:
	rm -rf .build build
