.PHONY: help
help:
		@echo "Available commands:"
		@echo "  install-cli       - Install Lua and Luarocks using Homebrew"
		@echo "  install-pre-commit - Install pre-commit using pip"
		@echo "  install           - Install vusted using Luarocks"
		@echo "  test              - Run tests using vusted"

.PHONY: install-cli
install-cli:
	brew install luarocks
	brew install lua

.PHONY: install-pre-commit
install-pre-commit:
	pip install pre-commit
	pre-commit install

.PHONY: install
install:
	luarocks install vusted

.PHONY: test
test:
	vusted test
