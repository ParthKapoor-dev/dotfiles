#!/usr/bin/env bash

set -e

# Colors for better output
GREEN="\033[1;32m"
YELLOW="\033[1;33m"
RED="\033[1;31m"
RESET="\033[0m"

# Default target directory
TARGET="$HOME"

# Check if GNU Stow is installed
if ! command -v stow &>/dev/null; then
    echo -e "${RED}❌ Error: GNU Stow is not installed. Please install it first.${RESET}"
    exit 1
fi

echo -e "${GREEN}🔧 Dotfiles Setup Script Using Stow${RESET}"
echo -e "📦 Target directory: ${YELLOW}$TARGET${RESET}"
echo

# Get current directory (dotfiles root)
DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

cd "$DOTFILES_DIR" || exit 1

# List of stow packages (directories only)
# Skips dot-dirs (.git) and _-prefixed dirs (_patches, _etc: reference only, never stowed).
PACKAGES=($(find . -mindepth 1 -maxdepth 1 -type d ! -name ".*" ! -name "_*" -exec basename {} \; | sort))

if [ ${#PACKAGES[@]} -eq 0 ]; then
    echo -e "${RED}❌ No stow packages found in $DOTFILES_DIR${RESET}"
    exit 1
fi

echo -e "${GREEN}📁 Found ${#PACKAGES[@]} stow packages:${RESET}"
for pkg in "${PACKAGES[@]}"; do
    echo -e "   - ${YELLOW}$pkg${RESET}"
done
echo

# Prompt user for confirmation
read -rp "$(echo -e "${YELLOW}⚠️  Do you want to stow these packages into $TARGET? [y/N]: ${RESET}")" confirm
if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
    echo -e "${RED}Aborted by user.${RESET}"
    exit 1
fi

# Run stow on each package
for pkg in "${PACKAGES[@]}"; do
    echo -e "${GREEN}🔗 Stowing '$pkg'...${RESET}"
    # These target dirs hold files from other sources: link files, never fold the dir.
    case "$pkg" in bin|systemd-desktop) fold=(--no-folding) ;; *) fold=() ;; esac
    if ! stow -t "$TARGET" "${fold[@]}" "$pkg"; then
        echo -e "${RED}❌ Failed to stow $pkg${RESET}"
    fi
done

echo -e "\n${GREEN}✅ All dotfiles linked successfully!${RESET}"
