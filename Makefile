VERSION    := 1.1

# Git info for versioning
GIT_HASH   := $(shell git rev-parse --short HEAD 2>/dev/null || echo "unknown")
GIT_DIRTY  := $(shell git status --porcelain 2>/dev/null)
BUILD_TYPE ?= dev
ifeq ($(BUILD_TYPE),stable)
RELEASE_VERSION := v$(VERSION)-$(if $(GIT_DIRTY),$(shell date +"%Y%m%d%H%M%S"),$(GIT_HASH))
else
RELEASE_VERSION := v$(VERSION)-$(BUILD_TYPE)-$(if $(GIT_DIRTY),$(shell date +"%Y%m%d%H%M%S"),$(GIT_HASH))
endif

# Target directory name in the zip
ZIP_DIR_NAME := ps5-lua-autoloader-$(RELEASE_VERSION)
ZIP_FILE     := $(ZIP_DIR_NAME).zip

SRC_FILES := $(shell find src -type f)
ELFLDR_FILE := $(shell basename $(shell ls src/elfldr-ps5-*.elf 2>/dev/null | head -n 1) 2>/dev/null)

all: $(ZIP_FILE)

$(ZIP_FILE): $(SRC_FILES)
	rm -rf build_dir $(ZIP_FILE)
	mkdir -p build_dir/$(ZIP_DIR_NAME)
	cp -r src/* build_dir/$(ZIP_DIR_NAME)/
	# Replace version string in main.lua
	sed -i.bak "s/@@VERSION@@/$(RELEASE_VERSION)/g" build_dir/$(ZIP_DIR_NAME)/main.lua && rm build_dir/$(ZIP_DIR_NAME)/main.lua.bak
	# Replace elfldr filename in elf_loader.lua
	sed -i.bak "s/@@ELFLDR_FILE@@/$(ELFLDR_FILE)/g" build_dir/$(ZIP_DIR_NAME)/elf_loader.lua && rm build_dir/$(ZIP_DIR_NAME)/elf_loader.lua.bak
	(cd build_dir && zip -r ../$(ZIP_FILE) $(ZIP_DIR_NAME))
	rm -rf build_dir
	echo "Created $(ZIP_FILE)"

clean:
	rm -rf build_dir savedata-*.zip

.PHONY: all clean print-version
print-version:
	@echo $(RELEASE_VERSION)
