SHELL := /usr/bin/env bash

PREFIX ?= /opt/devops-desk
BIN_DIR ?= /usr/local/bin

.PHONY: install uninstall check link permissions

install: check permissions copy link k9s
	@echo "✓ devops-desk installed"

check:
	@echo "Checking dependencies..."
	@command -v aws >/dev/null || (echo "aws missing"; exit 1)
	@command -v kubectl >/dev/null || (echo "kubectl missing"; exit 1)
	@command -v fzf >/dev/null || (echo "fzf missing"; exit 1)

permissions:
	@echo "Setting permissions..."
	chmod +x bin/devops-desk
	chmod +x commands/*.sh
	chmod +x lib/*.sh

copy:
	@echo "Installing to $(PREFIX)"
	sudo mkdir -p $(PREFIX)
	sudo cp -R bin commands lib config k9s $(PREFIX)

link:
	@echo "Linking binary"
	sudo ln -sf $(PREFIX)/bin/devops-desk $(BIN_DIR)/devops-desk

k9s:
	@if command -v k9s >/dev/null; then \
		echo "Installing k9s plugins"; \
		mkdir -p $$HOME/.config/k9s/skins; \
		cp k9s/plugins.yaml $$HOME/.config/k9s/plugins.yaml; \
		cp k9s/skin.yaml $$HOME/.config/k9s/skins/devops-desk.yaml; \
	fi

uninstall:
	@echo "Removing devops-desk"
	sudo rm -rf $(PREFIX)
	sudo rm -f $(BIN_DIR)/devops-desk
