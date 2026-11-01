# Vertical tab bar (tab_bar_style custom): fade-style tabs, title word-wrapped over 2 rows, no index.
# One blank row between tabs; overflow scrolls to keep the active tab visible, with ↑/↓ markers.
import kitty.tab_bar as kitty_tab_bar
from kitty.fast_data_types import wcswidth
from kitty.rgb import alpha_blend, color_from_int
from kitty.tab_bar import CellRange, TabExtent, as_rgb
from kitty.utils import color_as_int

MAX_TITLE_LINES = 2
GAP_LINES = 1


def _take(text, width):
    """Longest prefix of text that fits in width cells."""
    out = ''
    for char in text:
        if wcswidth(out + char) > width:
            break
        out += char
    return out


def _wrap(text, width, max_lines):
    lines, current, words = [], '', text.split()
    while words and len(lines) < max_lines:
        word = words.pop(0)
        candidate = f'{current} {word}' if current else word
        if wcswidth(candidate) <= width:
            current = candidate
        elif current:
            lines.append(current)
            current = ''
            words.insert(0, word)
        else:  # single word wider than a line: hard-split it
            head = _take(word, width)
            lines.append(head)
            words.insert(0, word[len(head):])
    if current and len(lines) < max_lines:
        lines.append(current)
        current = ''
    rest = ' '.join([current, *words]).strip()
    if rest and lines:  # out of rows: ellipsize the last one
        lines[-1] = _take(f'{lines[-1]} {rest}', width - 1) + '…'
    return lines or ['']


def _tab_lines(draw_data, tab, width):
    prefix = ''
    if tab.needs_attention:
        prefix += draw_data.bell_on_tab
    if tab.has_activity_since_last_focus:
        prefix += draw_data.tab_activity_symbol
    return _wrap(prefix + tab.title, width, MAX_TITLE_LINES)


def _draw_tab(self, screen, tab, lines, top):
    """Each row looks like kitty's fade style; rows share one width so the tab reads as a block."""
    draw_data = self.draw_data
    tab_bg = as_rgb(draw_data.tab_bg(tab))
    fades = [
        as_rgb(color_as_int(alpha_blend(color_from_int(tab_bg >> 8), draw_data.default_bg, alpha)))
        for alpha in draw_data.alpha
    ]
    block = max(wcswidth(line) for line in lines)
    screen.cursor.fg = as_rgb(draw_data.tab_fg(tab))
    screen.cursor.bold, screen.cursor.italic = (
        self.active_font_style if tab.is_active else self.inactive_font_style
    )
    for offset, line in enumerate(lines):
        screen.cursor.x, screen.cursor.y = 0, top + offset
        for bg in fades:
            screen.cursor.bg = bg
            screen.draw(' ')
        screen.cursor.bg = tab_bg
        screen.draw(line + ' ' * (block - wcswidth(line)))
        for bg in reversed(fades):
            screen.cursor.bg = bg
            screen.draw(' ')
    screen.cursor.bold = screen.cursor.italic = False
    screen.cursor.bg = screen.cursor.fg = 0


def _first_visible(previous, heights, active, total_rows):
    def span(start, end):  # rows used by tabs[start..end], no gap after the last one
        return sum(heights[start:end + 1]) - GAP_LINES

    first = min(previous, active)
    while first < active and span(first, active) > total_rows:
        first += 1
    # Scroll back up when tabs above fit, e.g. after tabs were closed.
    while first > 0 and span(first - 1, len(heights) - 1) <= total_rows:
        first -= 1
    return first


def _update_vertical(self, data):
    screen = self.screen
    self.last_laid_out_tabs = data
    self.tab_extents = ()
    screen.cursor.x = screen.cursor.y = 0
    screen.erase_in_display(2, False)
    if not data:
        return self._update_edge_defaults(True)
    width = max(1, screen.columns - 2 * len(self.draw_data.alpha))
    all_lines = [_tab_lines(self.draw_data, tab, width) for tab in data]
    heights = [len(lines) + GAP_LINES for lines in all_lines]
    active = next((idx for idx, tab in enumerate(data) if tab.is_active), 0)
    first = _first_visible(getattr(self, '_scroll_first', 0), heights, active, screen.lines)
    self._scroll_first = first
    extents, row, last_drawn = [], 0, first - 1
    for idx in range(first, len(data)):
        lines = all_lines[idx][:max(0, screen.lines - row)]
        if len(lines) < len(all_lines[idx]) and idx != active:
            break
        _draw_tab(self, screen, data[idx], lines, row)
        # Extent includes the gap row below: kitty's tab drag treats an uncovered row as the last tab.
        extents.append(TabExtent(
            tab_id=data[idx].tab_id,
            x=CellRange(0, screen.columns - 1),
            y=CellRange(row, min(screen.lines - 1, row + heights[idx] - 1)),
        ))
        last_drawn = idx
        row += heights[idx]
        if row >= screen.lines:
            break
    screen.cursor.fg = as_rgb(color_as_int(self.draw_data.inactive_fg))
    if first > 0:
        screen.cursor.x, screen.cursor.y = screen.columns - 1, 0
        screen.draw('↑')
    if last_drawn < len(data) - 1:
        screen.cursor.x, screen.cursor.y = screen.columns - 1, screen.lines - 1
        screen.draw('↓')
    screen.cursor.fg = 0
    self.tab_extents = tuple(extents)
    return self._update_edge_defaults(True)


# kitty runs this file inside its own process, so the layout override applies to every tab bar.
# No draw_tab is defined, so horizontal bars keep kitty's fade style.
kitty_tab_bar.TabBar.update_vertical = _update_vertical
