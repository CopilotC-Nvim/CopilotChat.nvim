.PHONY: help
help:
		@echo "install - install vusted"
		@echo "test    - run test"

.PHONY: install-cli
install-cli:
	brew install luarocks
	brew install lua

.PHONY: install
install:
	luarocks install vusted

.PHONY: test
test:
	vusted test
