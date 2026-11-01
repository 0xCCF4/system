# Custom kitty tab bar: default "fade" tabs, plus the SSH host of the
# active window right-aligned at the end of the bar.
import os

from kitty.fast_data_types import Screen, get_boss
from kitty.tab_bar import DrawData, ExtraData, TabBarData, as_rgb, draw_tab_with_fade
from kitty.utils import color_as_int

# ssh options that consume the following argument
SSH_ARG_OPTS = set("BbcDEeFIiJLlmOoPpQRSWw")


def ssh_host(cmdline: list[str]) -> str:
    exe = os.path.basename(cmdline[0]).lower() if cmdline else ""
    if exe == "kitten" and cmdline[1:2] == ["ssh"]:
        args = cmdline[2:]
    elif exe == "ssh":
        args = cmdline[1:]
    else:
        return ""
    user = ""
    i = 0
    while i < len(args):
        a = args[i]
        if a == "--":
            i += 1
            break
        if a.startswith("--"):  # kitten ssh long options, e.g. --kitten=...
            i += 1
            continue
        if a.startswith("-") and len(a) > 1:
            opt = a[1:]
            # options may be bundled (-tv) and the last may take a value (-p22 / -p 22)
            for j, c in enumerate(opt):
                if c in SSH_ARG_OPTS:
                    val = opt[j + 1:]
                    if not val:
                        i += 1
                        val = args[i] if i < len(args) else ""
                    if c == "l":
                        user = val
                    break
            i += 1
            continue
        break
    if i >= len(args):
        return ""
    host = args[i].removeprefix("ssh://")
    if user and "@" not in host:
        host = f"{user}@{host}"
    return host


def active_ssh_host(os_window_id: int) -> str:
    tm = get_boss().os_window_map.get(os_window_id)
    w = tm.active_window if tm else None
    if w is None:
        return ""
    for p in w.child.foreground_processes:
        host = ssh_host(list(p["cmdline"] or ()))
        if host:
            return host
    return ""


def draw_tab(
    draw_data: DrawData, screen: Screen, tab: TabBarData, before: int, max_tab_length: int, index: int, is_last: bool, extra_data: ExtraData
) -> int:
    end = draw_tab_with_fade(draw_data, screen, tab, before, max_tab_length, index, is_last, extra_data)
    if not is_last:
        return end
    try:
        host = active_ssh_host(tab.os_window_id)
    except Exception:
        host = ""
    if host:
        status = f" 󰣀 {host} "
        x = screen.columns - len(status)
        if x > screen.cursor.x:
            screen.cursor.x = x
            screen.cursor.fg = as_rgb(color_as_int(draw_data.active_fg))
            screen.cursor.bg = as_rgb(color_as_int(draw_data.active_bg))
            screen.cursor.bold = True
            screen.draw(status)
            screen.cursor.bold = False
            screen.cursor.bg = 0
    return end
