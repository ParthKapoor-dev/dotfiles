#!/usr/bin/env python3
import curses
import os

THEMES_DIR = "themes"
CONFIG_FILE = "kitty.conf"
TEMPLATE_FILE = "kitty.conf.template"

def apply_theme(theme_name):
    theme_path = os.path.join(THEMES_DIR, theme_name)
    if not os.path.exists(theme_path):
        return False
    
    # Read base template
    template_content = ""
    if os.path.exists(TEMPLATE_FILE):
        with open(TEMPLATE_FILE, 'r') as f:
            template_content = f.read()
    
    # Read theme colors
    with open(theme_path, 'r') as f:
        theme_content = f.read()

    # Combine: Template settings + Theme colors
    # We append theme content at the end so it overrides any colors in template if they exist
    with open(CONFIG_FILE, 'w') as f:
        f.write("# --- BASE SETTINGS ---\n")
        f.write(template_content)
        f.write("\n# --- THEME COLORS ---\n")
        f.write(theme_content)
    return True

def main(stdscr):
    # Setup curses
    curses.curs_set(0)
    stdscr.nodelay(False)
    stdscr.keypad(True)
    
    # Get themes
    if not os.path.exists(THEMES_DIR):
        return f"Error: {THEMES_DIR} directory not found."
    
    all_themes = sorted([f for f in os.listdir(THEMES_DIR) if f.endswith(".conf")])
    
    # Ensure custom_1.conf shows up as 'default.conf' or similar in the UI if you want, 
    # but the user asked to see it as 'default'.
    # Let's map the filenames to display names for the UI
    theme_map = {t: t for t in all_themes}
    if "custom_1.conf" in theme_map:
        theme_map["custom_1.conf"] = "default.conf (Current)"

    filtered_themes = all_themes
    current_row = 0
    search_query = ""
    searching = False

    while True:
        stdscr.erase()
        h, w = stdscr.getmaxyx()

        # Header
        header = " Kitty Theme Selector (j/k: move, l/Enter: apply, /: search, q: quit) "
        stdscr.addstr(0, 0, header[:w], curses.A_REVERSE)

        # Draw list
        display_themes = filtered_themes
        list_height = h - 2
        
        if len(display_themes) > 0:
            current_row = max(0, min(current_row, len(display_themes) - 1))
        else:
            current_row = 0

        for i, theme in enumerate(display_themes[:list_height]):
            display_name = theme_map.get(theme, theme)
            if i == current_row:
                stdscr.attron(curses.A_REVERSE)
                stdscr.addstr(i + 1, 0, f"> {display_name[:w-3]}")
                stdscr.attroff(curses.A_REVERSE)
            else:
                stdscr.addstr(i + 1, 0, f"  {display_name[:w-3]}")

        # Footer / Search Bar
        if searching:
            footer = f"Search: {search_query}"
            stdscr.addstr(h - 1, 0, footer[:w], curses.A_BOLD)
            curses.curs_set(1)
        else:
            footer = f" Selection: {theme_map.get(display_themes[current_row]) if display_themes else 'None'} "
            stdscr.addstr(h - 1, 0, footer[:w], curses.A_DIM)
            curses.curs_set(0)

        stdscr.refresh()

        # Handle input
        key = stdscr.getch()

        if searching:
            if key == 27: # ESC
                searching = False
                search_query = ""
                filtered_themes = all_themes
            elif key in (curses.KEY_BACKSPACE, 127, 8):
                search_query = search_query[:-1]
                filtered_themes = [t for t in all_themes if search_query.lower() in t.lower()]
            elif key == 10: # Enter
                searching = False
            elif 32 <= key <= 126:
                search_query += chr(key)
                filtered_themes = [t for t in all_themes if search_query.lower() in t.lower()]
        else:
            if key == ord('q'):
                break
            elif key in (ord('j'), curses.KEY_DOWN):
                current_row = min(current_row + 1, len(display_themes) - 1)
            elif key in (ord('k'), curses.KEY_UP):
                current_row = max(current_row - 1, 0)
            elif key in (ord('l'), 10): # l or Enter
                if display_themes:
                    theme_to_apply = display_themes[current_row]
                    if apply_theme(theme_to_apply):
                        break
            elif key == ord('h'):
                pass
            elif key == ord('/'):
                searching = True
                search_query = ""
            elif key == curses.KEY_RESIZE:
                continue

if __name__ == "__main__":
    curses.wrapper(main)