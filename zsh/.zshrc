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
alias ls="eza --color=always --git --no-filesize --icons=always "
alias hypr="nvim ~/.config/hypr/hyprland.conf"
alias dev="npm run dev"
alias projects="ls ~/code/dev/ --tree --level=2"
alias gitup="git add . && git commit -a -m"
alias gits="git status -s"
alias doc="sudo docker"
alias k="kubectl"
alias ff="fastfetch -l blackarch"
alias img="kitty +kitten icat"

eval "$(fzf --zsh)"

export PATH=$HOME/.local/bin:$PATH
export PATH="$PATH:$(go env GOPATH)/bin"
export PATH="$HOME/bin:$PATH"
export PATH="/opt/flutter/bin:$PATH"
export PATH="/opt/android-studio/bin:$PATH"


export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"  # This loads nvm
[ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"  # This loads nvm bash_completion

# opencode
export PATH=/home/parth/.opencode/bin:$PATH
