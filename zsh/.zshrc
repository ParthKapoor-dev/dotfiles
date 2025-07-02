# Add this to ~/.zshrc
eval "$(starship init zsh)"

# Enable zsh-autosuggestions
source ~/.zsh/zsh-autosuggestions/zsh-autosuggestions.zsh

# Enable zsh-syntax-highlighting
source ~/.zsh/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh

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
