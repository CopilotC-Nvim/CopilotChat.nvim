UNAME := $(shell uname)
ARCH := $(patsubst aarch64,arm64,$(shell uname -m))

ifeq ($(UNAME), Linux)
    OS := linux
    EXT := so
else ifeq ($(UNAME), Darwin)
    OS := macOS
    EXT := dylib
else
    $(error Unsupported operating system: $(UNAME))
endif

LUA_VERSIONS := luajit lua51
BUILD_DIR := build

.PHONY: help install-cli install-pre-commit install test tiktoken clean

help:
	@echo "Available commands:"
	@echo "  install-cli       - Install Lua and Luarocks using Homebrew"
	@echo "  install-pre-commit - Install pre-commit using pip"
	@echo "  install           - Install vusted using Luarocks"
	@echo "  test              - Run tests using vusted"
	@echo "  tiktoken          - Download tiktoken_core library"
	@echo "  clean             - Remove build directory"

install-cli:
	brew install luarocks
	brew install lua

install-pre-commit:
	pip install pre-commit
	pre-commit install

install:
	luarocks install vusted

test:
	vusted test

all: luajit

luajit: $(BUILD_DIR)/tiktoken_core.$(EXT)
lua51: $(BUILD_DIR)/tiktoken_core-lua51.$(EXT)


define download_release
	curl -LSsf https://github.com/gptlang/lua-tiktoken/releases/latest/download/tiktoken_core-$(1)-$(2)-$(3).$(EXT) -o $(4)
endef

$(BUILD_DIR)/tiktoken_core.$(EXT): | $(BUILD_DIR)
	$(call download_release,$(OS),$(ARCH),luajit,$@)

$(BUILD_DIR)/tiktoken_core-lua51.$(EXT): | $(BUILD_DIR)
	$(call download_release,$(OS),$(ARCH),lua51,$@)

tiktoken: $(BUILD_DIR)/tiktoken_core.$(EXT) $(BUILD_DIR)/tiktoken_core-lua51.$(EXT)

$(BUILD_DIR):
	mkdir -p $(BUILD_DIR)

clean:
	rm -rf $(BUILD_DIR)
