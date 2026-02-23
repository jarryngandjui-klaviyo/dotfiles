# Dotfiles Setup Makefile
# Idempotent setup for macOS terminal environment

# Variables
DOTFILES_DIR := $(shell pwd)
DOTFILES_CONFIG_DIR := $(DOTFILES_DIR)
HOME_DIR := $(HOME)
CONFIG_DIR := $(HOME_DIR)/.config
CLAUDE_SKILLS_DIR := $(HOME_DIR)/.claude/skills
AGENTS_SKILLS_DIR := $(DOTFILES_DIR)/agents/skills

# Colors for output
GREEN := \033[0;32m
YELLOW := \033[1;33m
RED := \033[0;31m
NC := \033[0m # No Color

# Default target
.PHONY: all
all: homebrew shell carapace nvim tmux

# Help target
.PHONY: help
help:
	@echo "Available targets:"
	@echo "  all      - Install everything (default)"
	@echo "  homebrew - Install Homebrew and packages"
	@echo "  node     - Setup Node.js using n version manager"
	@echo "  shell    - Setup Zsh and Starship prompt"
	@echo "  carapace - Install Carapace shell completions"
	@echo "  nvim     - Setup Neovim and LSP dependencies"
	@echo "  tmux     - Setup Tmux and TPM"
	@echo "  starship - Setup Starship prompt"
	@echo "  setup-claude-skills - Link agents/skills to ~/.claude/skills for Claude agents"
	@echo "  clean    - Remove symlinks and configurations"
	@echo "  clean-backups - Remove old zshrc backup files"
	@echo "  verify-zsh-completions - Test if compdef is working"
	@echo "  help     - Show this help message"

# Check if command exists
check-command = $(shell command -v $(1) >/dev/null 2>&1 && echo "yes" || echo "no")

# Check if brew package is installed
check-brew-package = $(shell brew list --formula $(1) >/dev/null 2>&1 && echo "yes" || echo "no")
check-brew-cask = $(shell brew list --cask $(1) >/dev/null 2>&1 && echo "yes" || echo "no")

# Check if cask app exists in Applications folder
check-cask-app = $(shell [ -d "/Applications/$(1).app" ] && echo "yes" || echo "no")

# Install brew package if not installed
install-brew-package:
	@if [ "$(TYPE)" = "cask" ]; then \
		if [ "$(call check-brew-cask,$(PACKAGE))" = "yes" ] || [ "$(call check-cask-app,$(PACKAGE))" = "yes" ]; then \
			echo "$(GREEN)$(PACKAGE) is already installed$(NC)"; \
		else \
			echo "$(YELLOW)Installing $(PACKAGE) as $(TYPE)...$(NC)"; \
			brew install --cask $(PACKAGE) 2>/dev/null || echo "$(YELLOW)$(PACKAGE) installation failed, but app may already exist in Applications folder$(NC)"; \
		fi; \
	else \
		if [ "$(call check-brew-package,$(PACKAGE))" = "yes" ]; then \
			echo "$(GREEN)$(PACKAGE) is already installed$(NC)"; \
		else \
			echo "$(YELLOW)Installing $(PACKAGE) as $(TYPE)...$(NC)"; \
			brew install $(PACKAGE); \
		fi; \
	fi

# Homebrew setup
.PHONY: homebrew
homebrew: check-homebrew install-brew-packages

check-homebrew:
	@if [ "$(call check-command,brew)" = "no" ]; then \
		echo "$(YELLOW)Installing Homebrew...$(NC)"; \
		/bin/bash -c "$$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"; \
		echo 'eval "$$(/opt/homebrew/bin/brew shellenv)"' >> $(HOME_DIR)/.zprofile; \
		eval "$$(/opt/homebrew/bin/brew shellenv)"; \
	else \
		echo "$(GREEN)Homebrew is already installed$(NC)"; \
		echo "$(YELLOW)Updating Homebrew...$(NC)"; \
		brew update && brew upgrade; \
	fi

install-brew-packages: check-homebrew
	@$(MAKE) install-brew-package PACKAGE=ripgrep TYPE=formula
	@$(MAKE) install-brew-package PACKAGE=fd TYPE=formula
	@$(MAKE) install-brew-package PACKAGE=pnpm TYPE=formula
	@$(MAKE) install-brew-package PACKAGE=pipx TYPE=formula
	@$(MAKE) install-brew-package PACKAGE=docker TYPE=cask
	@$(MAKE) install-brew-package PACKAGE=alacritty TYPE=cask
	@$(MAKE) install-brew-package PACKAGE=raycast TYPE=cask
	@$(MAKE) install-brew-package PACKAGE=betterdisplay TYPE=cask
	@$(MAKE) install-brew-package PACKAGE=llvm TYPE=formula
	@$(MAKE) install-brew-package PACKAGE=zsh TYPE=formula
	@$(MAKE) install-brew-package PACKAGE=starship TYPE=formula
	@$(MAKE) install-brew-package PACKAGE=zsh-history-substring-search TYPE=formula
	@$(MAKE) install-brew-package PACKAGE=pngpaste TYPE=formula # nvim obsidian image paste
	@brew tap homebrew/cask-fonts 2>/dev/null || true
	@$(MAKE) install-brew-package PACKAGE=font-jetbrains-mono-nerd-font TYPE=cask
	@brew tap hashicorp/tap 2>/dev/null || true
	@$(MAKE) install-brew-package PACKAGE=hashicorp/tap/terraform TYPE=formula
	@brew install awscli 2>/dev/null || echo "$(GREEN)awscli already installed$(NC)"
	@$(MAKE) setup-node

# Node.js setup
.PHONY: setup-node
setup-node:
	@echo "$(YELLOW)Setting up Node.js...$(NC)"; \
	if [ "$(call check-command,node)" = "no" ]; then \
		echo "$(YELLOW)Installing latest LTS Node.js using n...$(NC)"; \
		n lts; \
		echo "$(GREEN)Node.js LTS installed successfully$(NC)"; \
	else \
		echo "$(GREEN)Node.js is already installed$(NC)"; \
		echo "$(YELLOW)Current Node.js version: $$(node --version)$(NC)"; \
	fi

# Node.js target
.PHONY: node
node: homebrew setup-node

# Shell setup
.PHONY: shell
shell: homebrew setup-zsh setup-starship


setup-zsh:
	@echo "$(YELLOW)Setting up Zsh configuration...$(NC)"; \
	$(MAKE) setup-zshrc-merge; \
	$(MAKE) setup-klaviyorc-merge; \
	ln -sf $(DOTFILES_CONFIG_DIR)/zsh/zprofile $(HOME_DIR)/.zprofile; \
	$(MAKE) verify-zsh-completions; \
	echo "$(GREEN)Zsh configuration setup complete$(NC)"

setup-zshrc-merge:
	@echo "$(YELLOW)Merging zshrc configuration...$(NC)"; \
	ZSH_CONFIG_START="# === DOTFILES ZSH CONFIGURATION START - DO NOT EDIT MANUALLY ==="; \
	ZSH_CONFIG_END="# === DOTFILES ZSH CONFIGURATION END - DO NOT EDIT MANUALLY ==="; \
	BACKUP_FILE="$(HOME_DIR)/.zshrc-backup-$$(date +%Y-%m-%d_%H-%M-%S)"; \
	if [ -f "$(HOME_DIR)/.zshrc" ]; then \
		if grep -q "$$ZSH_CONFIG_START" "$(HOME_DIR)/.zshrc" && grep -q "$$ZSH_CONFIG_END" "$(HOME_DIR)/.zshrc"; then \
			echo "$(GREEN)Existing dotfiles configuration found, updating...$(NC)"; \
			cp "$(HOME_DIR)/.zshrc" "$$BACKUP_FILE"; \
			echo "$(YELLOW)Backed up existing zshrc to $$BACKUP_FILE$(NC)"; \
			awk "/$$ZSH_CONFIG_START/,/$$ZSH_CONFIG_END/ { next } { print }" "$(HOME_DIR)/.zshrc" > "$(HOME_DIR)/.zshrc.tmp"; \
			cat "$(HOME_DIR)/.zshrc.tmp" $(DOTFILES_CONFIG_DIR)/zsh/zshrc > "$(HOME_DIR)/.zshrc"; \
			rm "$(HOME_DIR)/.zshrc.tmp"; \
		else \
			echo "$(YELLOW)No existing dotfiles configuration found, creating backup and merging...$(NC)"; \
			cp "$(HOME_DIR)/.zshrc" "$$BACKUP_FILE"; \
			echo "$(YELLOW)Backed up existing zshrc to $$BACKUP_FILE$(NC)"; \
			cat "$(HOME_DIR)/.zshrc" $(DOTFILES_CONFIG_DIR)/zsh/zshrc > "$(HOME_DIR)/.zshrc"; \
		fi; \
	else \
		echo "$(YELLOW)No existing zshrc found, creating new one...$(NC)"; \
		cp $(DOTFILES_CONFIG_DIR)/zsh/zshrc "$(HOME_DIR)/.zshrc"; \
	fi; \
	echo "$(GREEN)Zshrc configuration merged successfully$(NC)"

setup-klaviyorc-merge:
	@echo "$(YELLOW)Merging klaviyorc configuration...$(NC)"; \
	KLAVIYO_CONFIG_START="# === DOTFILES KLAVIYORC CONFIGURATION START - DO NOT EDIT MANUALLY ==="; \
	KLAVIYO_CONFIG_END="# === DOTFILES KLAVIYORC CONFIGURATION END - DO NOT EDIT MANUALLY ==="; \
	BACKUP_FILE="$(HOME_DIR)/.zshrc-klaviyo-backup-$$(date +%Y-%m-%d_%H-%M-%S)"; \
	if [ -f "$(HOME_DIR)/.zshrc" ]; then \
		if grep -q "$$KLAVIYO_CONFIG_START" "$(HOME_DIR)/.zshrc" && grep -q "$$KLAVIYO_CONFIG_END" "$(HOME_DIR)/.zshrc"; then \
			echo "$(GREEN)Existing klaviyo configuration found, updating...$(NC)"; \
			cp "$(HOME_DIR)/.zshrc" "$$BACKUP_FILE"; \
			echo "$(YELLOW)Backed up existing zshrc to $$BACKUP_FILE$(NC)"; \
			awk "/$$KLAVIYO_CONFIG_START/,/$$KLAVIYO_CONFIG_END/ { next } { print }" "$(HOME_DIR)/.zshrc" > "$(HOME_DIR)/.zshrc.tmp"; \
			cat "$(HOME_DIR)/.zshrc.tmp" $(DOTFILES_CONFIG_DIR)/zsh/klaviyorc > "$(HOME_DIR)/.zshrc.tmp2"; \
			mv "$(HOME_DIR)/.zshrc.tmp2" "$(HOME_DIR)/.zshrc"; \
			rm "$(HOME_DIR)/.zshrc.tmp"; \
		else \
			echo "$(YELLOW)No existing klaviyo configuration found, appending...$(NC)"; \
			cp "$(HOME_DIR)/.zshrc" "$$BACKUP_FILE"; \
			echo "$(YELLOW)Backed up existing zshrc to $$BACKUP_FILE$(NC)"; \
			cat "$(HOME_DIR)/.zshrc" $(DOTFILES_CONFIG_DIR)/zsh/klaviyorc > "$(HOME_DIR)/.zshrc.tmp"; \
			mv "$(HOME_DIR)/.zshrc.tmp" "$(HOME_DIR)/.zshrc"; \
		fi; \
	else \
		echo "$(RED)Error: No .zshrc file found. Please run setup-zshrc-merge first.$(NC)"; \
		exit 1; \
	fi; \
	echo "$(GREEN)Klaviyo configuration merged successfully$(NC)"

verify-zsh-completions:
	@echo "$(YELLOW)Verifying zsh completions...$(NC)"; \
	if zsh -c "autoload -Uz compinit && compinit && type compdef >/dev/null 2>&1"; then \
		echo "$(GREEN)Zsh completions (compdef) are working$(NC)"; \
	else \
		echo "$(RED)Warning: Zsh completions may not be working properly$(NC)"; \
	fi

setup-starship:
	@echo "$(YELLOW)Setting up Starship configuration...$(NC)"; \
	mkdir -p $(CONFIG_DIR); \
	ln -sf $(DOTFILES_CONFIG_DIR)/starship/starship.toml $(CONFIG_DIR)/starship.toml; \
	echo "$(GREEN)Starship configuration setup complete$(NC)"

# Starship setup
.PHONY: starship
starship: homebrew setup-starship

# Carapace setup
.PHONY: carapace
carapace: homebrew setup-carapace

setup-carapace:
	@echo "$(YELLOW)Setting up Carapace shell completions...$(NC)"; \
	$(MAKE) install-brew-package PACKAGE=carapace TYPE=formula; \
	echo "$(GREEN)Carapace setup complete$(NC)"

# Neovim setup
.PHONY: nvim
nvim: homebrew setup-nvim setup-nvim-config setup-lsp-dependencies

setup-nvim:
	@$(MAKE) install-brew-package PACKAGE=neovim TYPE=formula

setup-nvim-config:
	@echo "$(YELLOW)Clean up Neovim configuration...$(NC)"; \
	# Linux / MacOS (unix)
	rm -rf ~/.config/nvim; \
	rm -rf ~/.local/state/nvim; \
	rm -rf ~/.local/share/nvim; \
	NVIM_DIR="$(CONFIG_DIR)/nvim"; \
	git clone https://github.com/NvChad/starter "$$NVIM_DIR"; \
	echo "$(YELLOW)Setting up Neovim configuration...$(NC)"; \
	mkdir -p "$$NVIM_DIR/.backup" "$$NVIM_DIR/lua/config" "$$NVIM_DIR/lua/plugins" "$$NVIM_DIR/lua/custom"; \
	ln -sf $(DOTFILES_CONFIG_DIR)/nvim/init.lua "$$NVIM_DIR/init.lua"; \
	ln -sf $(DOTFILES_CONFIG_DIR)/nvim/lazy-lock.json "$$NVIM_DIR/lazy-lock.json"; \
	cd $(DOTFILES_CONFIG_DIR)/nvim && find . -type f | while read -r file; do \
		file="$${file#./}"; \
		mkdir -p "$$NVIM_DIR/$$(dirname "$$file")"; \
		ln -sf "$(DOTFILES_CONFIG_DIR)/nvim/$$file" "$$NVIM_DIR/$$file"; \
	done; \
	echo "$(GREEN)Neovim configuration setup complete$(NC)"

setup-lsp-dependencies:
	@echo "$(YELLOW)Setting up LSP dependencies...$(NC)"; \
	$(MAKE) install-brew-package PACKAGE=llvm TYPE=formula; \
	$(MAKE) install-brew-package PACKAGE=n TYPE=formula; \
	n auto; \
	npm install -g typescript typescript-language-server; \
	$(MAKE) install-brew-package PACKAGE=pipx TYPE=formula; \
	pipx install python-lsp-server; \
	cd $(HOME_DIR)/.local/share/pipx/venvs/python-lsp-server && \
	source base/activate && \
	python3 -m pip install pylsp-mypy && \
	python3 -m pip install python-lsp-ruff --no-deps; \
	echo "$(GREEN)LSP dependencies setup complete$(NC)"

# Tmux setup
.PHONY: tmux
tmux: homebrew setup-tmux setup-tpm setup-tmux-config

setup-tmux:
	@$(MAKE) install-brew-package PACKAGE=tmux TYPE=formula

setup-tpm:
	@TPM_DIR="$(HOME_DIR)/.tmux/plugins/tpm"; \
	if [ ! -d "$$TPM_DIR" ]; then \
		echo "$(YELLOW)Installing Tmux Plugin Manager...$(NC)"; \
		git clone https://github.com/tmux-plugins/tpm "$$TPM_DIR"; \
	else \
		echo "$(GREEN)TPM is already installed$(NC)"; \
	fi

setup-tmux-config:
	@echo "$(YELLOW)Setting up Tmux configuration...$(NC)"; \
	TMUX_CONFIG_DIR="$(CONFIG_DIR)/tmux"; \
	mkdir -p "$$TMUX_CONFIG_DIR"; \
	ln -sf $(DOTFILES_CONFIG_DIR)/tmux/tmux.conf "$$TMUX_CONFIG_DIR/tmux.conf"; \
	ln -sf $(DOTFILES_CONFIG_DIR)/tmux/tmux.reset.conf "$$TMUX_CONFIG_DIR/tmux.reset.conf"; \
	echo "$(GREEN)Tmux configuration setup complete$(NC)"

setup-tmux-reload:
	@echo "$(YELLOW)Reloading Tmux configuration...$(NC)"
	@tmux source-file ~/.config/tmux/tmux.conf || echo "$(RED)No active tmux sessions found$(NC)"
	@echo "$(GREEN)Tmux configuration reloaded$(NC)"

# Alacritty setup
.PHONY: alacritty
alacritty: homebrew setup-alacritty

setup-alacritty:
	@$(MAKE) install-brew-package PACKAGE=alacritty TYPE=cask; \
	mkdir -p $(CONFIG_DIR)/alacritty; \
	ln -sf $(DOTFILES_CONFIG_DIR)/alacritty/alacritty.toml $(CONFIG_DIR)/alacritty/alacritty.toml; \
	echo "$(GREEN)Alacritty configuration setup complete$(NC)"

# Claude agents skills: symlink dotfiles agents/skills to ~/.claude/skills
.PHONY: setup-claude-skills
setup-claude-skills:
	@echo "$(YELLOW)Linking Claude agent skills...$(NC)"; \
	mkdir -p "$(CLAUDE_SKILLS_DIR)"; \
	if [ ! -d "$(AGENTS_SKILLS_DIR)" ]; then \
		echo "$(YELLOW)No agents/skills directory found, nothing to link$(NC)"; \
		exit 0; \
	fi; \
	for skill_dir in "$(AGENTS_SKILLS_DIR)"/*/; do \
		[ -d "$$skill_dir" ] || continue; \
		skill_name=$$(basename "$$skill_dir"); \
		skill_src="$(AGENTS_SKILLS_DIR)/$$skill_name/SKILL.md"; \
		if [ ! -f "$$skill_src" ]; then \
			echo "$(YELLOW)Skipping $$skill_name (no SKILL.md)$(NC)"; \
			continue; \
		fi; \
		mkdir -p "$(CLAUDE_SKILLS_DIR)/$$skill_name"; \
		ln -sf "$$skill_src" "$(CLAUDE_SKILLS_DIR)/$$skill_name/SKILL.md"; \
		echo "$(GREEN)  $$skill_name -> $(CLAUDE_SKILLS_DIR)/$$skill_name/SKILL.md$(NC)"; \
	done; \
	echo "$(GREEN)Claude agent skills linked$(NC)"

# Clean target
.PHONY: clean
clean:
	@echo "$(YELLOW)Cleaning up symlinks and configurations...$(NC)"; \
	rm -f $(HOME_DIR)/.zprofile; \
	rm -rf $(CONFIG_DIR)/nvim $(CONFIG_DIR)/tmux $(CONFIG_DIR)/alacritty; \
	echo "$(YELLOW)Note: .zshrc and backup files are preserved for safety$(NC)"; \
	echo "$(GREEN)Cleanup complete$(NC)"

# Clean backups target
.PHONY: clean-backups
clean-backups:


# Verify zsh completions target
.PHONY: verify-zsh-completions

# Status check
.PHONY: status
status:
	@echo "$(YELLOW)Checking installation status...$(NC)"; \
	echo "Homebrew: $$([ "$(call check-command,brew)" = "yes" ] && echo "$(GREEN)✓$(NC)" || echo "$(RED)✗$(NC)")"; \
	echo "Node.js: $$([ "$(call check-command,node)" = "yes" ] && echo "$(GREEN)✓$(NC)" || echo "$(RED)✗$(NC)")"; \
	echo "Zsh: $$([ "$(call check-command,zsh)" = "yes" ] && echo "$(GREEN)✓$(NC)" || echo "$(RED)✗$(NC)")"; \
	echo "Carapace: $$([ "$(call check-command,carapace)" = "yes" ] && echo "$(GREEN)✓$(NC)" || echo "$(RED)✗$(NC)")"; \
	echo "Neovim: $$([ "$(call check-command,nvim)" = "yes" ] && echo "$(GREEN)✓$(NC)" || echo "$(RED)✗$(NC)")"; \
	echo "Tmux: $$([ "$(call check-command,tmux)" = "yes" ] && echo "$(GREEN)✓$(NC)" || echo "$(RED)✗$(NC)")"; \
	echo "Alacritty: $$([ "$(call check-brew-cask,alacritty)" = "yes" ] && echo "$(GREEN)✓$(NC)" || echo "$(RED)✗$(NC)")"; \
	echo "Starship: $$([ "$(call check-command,starship)" = "yes" ] && echo "$(GREEN)✓$(NC)" || echo "$(RED)✗$(NC)")"
