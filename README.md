# My Tailscale (Omarchy widget)

Native Omarchy bar widget for Tailscale, forked from the first-party
`omarchy.tailscale` and extended.

## Features

- Shows Tailscale connection state in the bar
- Left click opens a keyboard-friendly panel
- Right click toggles Tailscale on/off
- Switch between available Tailscale connections when multiple are available
- Exit nodes: tailnet peers plus Mullvad regions, with recents
- Settings: the `tailscale set` switches (Tailscale DNS, subnet routes, LAN
  access, shields up, Tailscale SSH, web management, offer as exit node,
  update notifications, automatic updates, device posture), read back from
  `tailscale debug prefs` on every refresh
- Headscale / alternate control server via the `loginServer` setting
- Browse machines from `tailscale status --json`
- Copy a machine's Tailscale IP, host name, or DNS name
- Send files to a machine with Taildrop, when the tailnet allows file sharing

## Keyboard shortcuts

Inside the panel the cursor walks the sections top to bottom:
header switch → operator / login-server rows → connections → exit nodes →
settings → machines.

| Key | Action |
| --- | --- |
| `j` / `k`, `↓` / `↑` | move the cursor (into the next section at either end of a list) |
| `Enter` / `Space` | activate the row: toggle, switch connection, pick exit node, flip a setting, open the copy menu |
| `c` | copy the selected machine's IPv4 (machines section only) |
| `n` | copy the selected machine's name (machines section only) |
| `d` | copy the selected machine's DNS name (machines section only) |
| `s` | send files to the selected machine with Taildrop (machines section only) |
| `t` | toggle Tailscale on/off (no confirmation, as before) |
| `r` | refresh status, prefs and connections now |
| `Esc` | disarm a pending login-server change, otherwise close the panel |
| `Tab` / `Shift+Tab` | switch to the neighbouring panel |

Machine keys pressed with the cursor elsewhere do nothing except say so in the
status line.

## Login server (Headscale)

`loginServer` (plugin setting, "Login server URL") names the control server for
**fresh logins**: empty means official Tailscale. It must be an `http://` or
`https://` URL with a plain hostname, dotted IPv4, or bracketed IPv6, an
optional port and path — no username, query or fragment, and the scheme is not
guessed. An invalid value is shown in the panel and nothing runs.

Turning Tailscale on is always a plain `tailscale up` and never changes
servers. When the configured server differs from the one this profile is bound
to (the panel hero shows the current `ControlURL`), a *Log in to …* row appears
under Connections. Activating it once arms it — the row states that it will
log out of the current server and remove that profile — and activating it again
runs, in order:

1. `tailscale logout` (deletes the current profile)
2. `pkexec tailscale set --operator=$USER` (logout leaves the new empty profile
   without an operator, so the desktop user would otherwise be read-only)
3. `tailscale up --login-server=<url>`

The URL `tailscale up` prints is opened with `xdg-open` only if it is a whole
`http(s)://` URL; anything else is shown in the panel as text to copy. A
dismissed polkit prompt stops the sequence and the panel spells out the two
commands left to run by hand. A switch to a connection that is logged out
(`tailscale switch` says `Logged out.`) starts a fresh login against the
configured server after the next refresh, instead of retrying the switch.

## Exit nodes

The exit node shown as in use is derived on every refresh from the persisted
preference (`ExitNodeID` / `ExitNodeIP` in `tailscale debug prefs`) and the
peer flags in `tailscale status --json` — never from a selection the panel
remembers. A node the CLI cleared shows as *None*; a selected node that went
offline shows *name (offline)*; a selected node the status no longer lists
shows *Selected exit node (unavailable)*.

## Requirements

- `tailscale` CLI on `PATH` (flag names verified against 1.102.3)
- `wl-copy` for clipboard copy actions (value passed on stdin)
- `xdg-open` for login links
- `pkexec` for operator authorization
- Taildrop enabled for the tailnet, to send files

## Receiving files

Incoming Taildrop files are saved to `~/Downloads` by the
`omarchy-tailscale-receive` service, which announces each one with a
notification (an image preview when the file is an image, and a click to open
it). The Tailscale service install enables it; `omarchy tailscale receive`
runs the same loop by hand.

## Icon

Renders the Tailscale mark natively as a theme-colored 3×3 dot grid, matching the official SVG silhouette while avoiding tiny-SVG rendering quirks in the bar.

## Tests

```
node tests/model.test.js     # pure Model.js: validators, argv builders, plans, derivations
node tests/service.test.js   # Service.qml state machine through a PATH shim (nothing real runs)
```

## Credits

- Forked from Omarchy's first-party `omarchy.tailscale` (MIT).
- Preference switches, alternate login server, exit-node discipline and the
  test harness technique are ported from
  [hehh2001/omarchy-tailscale-plus](https://github.com/hehh2001/omarchy-tailscale-plus)
  v1.5.2 (`426b3cc`), MIT License, Copyright (c) David Heinemeier Hansson,
  Copyright (c) 2026 hehh2001. Each ported
  block is marked `Ported from hehh2001/omarchy-tailscale-plus @426b3cc (MIT)`
  in the source. Its per-tailnet exit-node DNS helper was deliberately not
  ported.

MIT License — Permission is hereby granted, free of charge, to any person
obtaining a copy of this software and associated documentation files (the
"Software"), to deal in the Software without restriction, including without
limitation the rights to use, copy, modify, merge, publish, distribute,
sublicense, and/or sell copies of the Software, and to permit persons to whom
the Software is furnished to do so, subject to the following conditions: The
above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software. THE SOFTWARE IS PROVIDED "AS
IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT
LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE
AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE
LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF
CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE
SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
