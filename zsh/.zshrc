# Force proper terminal + key handling
export TERM=xterm-256color

# # minimal safe setup
# autoload -Uz compinit
# compinit
# bindkey -e

# Add this to ~/.zshrc
eval "$(starship init zsh)"

# Enable zsh-autosuggestions
source ~/.zsh/zsh-autosuggestions/zsh-autosuggestions.zsh

# Enable zsh-syntax-highlighting
source ~/.zsh/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh

# Fix Ctrl + Left/Right and Ctrl + W behavior in Kitty and Zsh
autoload -U select-word-style
select-word-style bash

bindkey "^[[1;5C" forward-word        # Ctrl + →
bindkey "^[[1;5D" backward-word       # Ctrl + ←

# Zsh History Settings (for autosuggestions + persistent history)
HISTFILE=~/.zsh_history         # Where the history is stored
HISTSIZE=10000                  # Number of commands to keep in memory
SAVEHIST=10000                  # Number of commands to save to the file

setopt INC_APPEND_HISTORY       # Write to history immediately, not when shell exits
setopt SHARE_HISTORY            # Share history across all sessions
setopt HIST_IGNORE_DUPS         # Don't record duplicate commands
setopt HIST_IGNORE_ALL_DUPS     # Remove older duplicates
setopt HIST_FIND_NO_DUPS        # Don’t show duplicates when searching
setopt HIST_REDUCE_BLANKS       # Remove extra blanks
setopt HIST_VERIFY              # Show command before executing on ! or history expansion

# alias
alias c="clear"
alias z="nvim ~/.zshrc"
alias s="source ~/.zshrc"
alias n="nvim"
alias shut="shutdown -h now"
alias pac="sudo pacman"
alias ls="eza --color=always --git --no-filesize --icons=always"
alias zo="zoxide"
alias hypr="nvim ~/.config/hypr/hyprland.conf"
alias dev="npm run dev"
alias projects="ls ~/code/dev/ --tree --level=2"
alias gitup="git add . && git commit -a -m"
alias gits="git status -s"
alias doc="sudo docker"
alias k="kubectl"
alias ff="fastfetch -l blackarch"
alias img="kitty +kitten icat"
alias leet="nvim leetcode.nvim"
alias warp="warp-cli"
alias zedx='WAYLAND_DISPLAY="" zed'
alias bt="bluetui"
alias b="btop"
alias oc="opencode"
alias clauded="claude --allow-dangerously-skip-permissions"
alias wl="wishlist"
alias ca="claude agents"


eval "$(fzf --zsh)"

export PATH=$HOME/.local/bin:$PATH
export PATH="$PATH:$(go env GOPATH)/bin"
export PATH="$HOME/bin:$PATH"
export PATH="/opt/flutter/bin:$PATH"
export PATH="/opt/android-studio/bin:$PATH"
export PATH="$HOME/.cargo/bin:$PATH"

export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"  # This loads nvm
[ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"  # This loads nvm bash_completion


# bun completions
[ -s "/home/parth/.bun/_bun" ] && source "/home/parth/.bun/_bun"

# bun
export BUN_INSTALL="$HOME/.bun"
export PATH="$BUN_INSTALL/bin:$PATH"
export PATH="$HOME/.local/bin:$PATH"
export ENCORE_INSTALL="/home/parth/.encore"
export PATH="$ENCORE_INSTALL/bin:$PATH"

eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"

# pnpm
export PNPM_HOME="/home/parth/.local/share/pnpm"
case ":$PATH:" in
  *":$PNPM_HOME:"*) ;;
  *) export PATH="$PNPM_HOME:$PATH" ;;
esac
# pnpm end

#
# # ssh
# if ! pgrep -u "$USER" ssh-agent > /dev/null; then
#   eval "$(ssh-agent -s)"
# fi

export PATH="/home/parth/.local/bin:$PATH"

export EDITOR=nvim

# expai: scoped Expertly Claude sandbox (~/code/sandbox/expai). Runs in a subshell so the
# current directory is untouched. e.g. `expai claude`, `expai claude agents`, `expai doctor`.
expai() { ( cd ~/code/sandbox/expai && ./expai "$@" ) }

# Open Neovim in its own Ghostty window with the Monaspace coding font
# (overrides live in ~/.config/nvim/ghostty.conf). Plain `nvim` still runs in-terminal.
nv() {
  setsid -f ghostty --gtk-single-instance=false --class=dev.neovim --title=nvim \
    --config-file="$HOME/.config/nvim/ghostty.conf" \
    --working-directory="$PWD" -e nvim "$@" >/dev/null 2>&1
}

# QODER_DISPATCHER_PATH v1
path=("$HOME/.qoder/entry" ${path:#"$HOME/.qoder/entry"})
export PATH
# END QODER_DISPATCHER_PATH v1
