<h1 align="center">🌌 Lnx Dotfiles</h1>

<p align="center">
  <b>⚡ Clean, minimal, and stow-powered dotfiles for instant Linux setup ⚡</b><br>
  <i>Effortlessly manage your dev environment across systems using symlinks</i>
</p>

---

## 📦 What's Included?

```

.
├── kitty       # Kitty terminal configuration
├── starship    # Starship prompt configuration
├── zsh         # Zsh shell configuration
└── setup.sh    # One script to stow them all!

````

All files are structured for use with [`GNU Stow`](https://www.gnu.org/software/stow/) to cleanly symlink into your home directory.

---

## 🚀 Quick Start

```bash
git clone https://github.com/parthkapoor-dev/dotfiles.git
cd dotfiles
chmod +x setup.sh
./setup.sh
````

You'll be prompted to confirm before symlinks are created into your home directory.

> 💡 Use this every time you reinstall your OS or switch machines.

---

## ⚙️ Requirements

* [GNU Stow](https://www.gnu.org/software/stow/) (`sudo pacman -S stow`, `sudo apt install stow`, etc.)
* `git` (of course)
* Unix-like OS (tested on Arch Linux + Hyprland)

---

## 🎯 Why Use Stow?

Stow creates symlinks from your dotfiles repo into your `$HOME` cleanly and reversibly:

> Instead of maintaining a messy `.config/` folder, you keep everything modular and manageable.

No more custom install scripts. Just plug and stow.

---

## 🖼️ Preview

<p align="center">
  <img src="https://media.giphy.com/media/IThjAlJnD9WNO/giphy.gif" height="200" />
</p>

---

## 💡 Pro Tip

Use this as a base to manage more configs:

```
.
├── nvim/
├── tmux/
├── hypr/
├── lazygit/
└── ...
```

Everything will get neatly symlinked with `stow -t ~ package-name`.

---

## 🙋‍♂️ Who’s This For?

* Developers who distro-hop a lot 🌀
* Tinkerers who love terminal productivity
* People who want clean, version-controlled dotfiles

---

## 📥 Fork & Customize

This repo is designed to be forked and extended. Clone, edit, push, profit.

---

## 🧠 Credits

* Inspired by [@dotbot](https://github.com/anishathalye/dotbot), [@mathiasbynens](https://github.com/mathiasbynens/dotfiles)
* Cool terminal vibes via `kitty + starship + zsh`

