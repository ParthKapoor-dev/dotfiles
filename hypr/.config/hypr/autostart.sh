#!/bin/bash

hyprctl dispatch workspace 1
firefox --new-window &
sleep 1
hyprctl dispatch workspace 2
firefox --new-window &
sleep 1
hyprctl dispatch workspace 3
zed &
sleep 1
hyprctl dispatch workspace 4
obsidian &
sleep 1
hyprctl dispatch togglespecialworkspace
kitty --class special-term &
