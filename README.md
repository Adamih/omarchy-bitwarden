# Bitwarden for Omarchy

Use your Bitwarden vault from Omarchy without the Bitwarden desktop app.
Bitwarden stays the source of truth; [rbw](https://github.com/doy/rbw), a
lightweight unofficial client, does the work.

This is an unofficial community plugin, not affiliated with or endorsed by
Bitwarden, Inc.

## Install

```bash
omarchy plugin add https://github.com/Adamih/omarchy-bitwarden.git --enable
```

A lock icon appears in the bar. Click it and follow the setup steps:

1. **Install rbw.** Installs whatever is missing of `rbw`, `jq`, `wl-clipboard`,
   `pinentry` (for `pinentry-qt`) and `glib2` (for `gdbus`) from the Arch
   repositories. Approve the authentication prompt.
2. **Bitwarden account.** Your email, and bitwarden.com, bitwarden.eu or a self-hosted URL.
3. **Register this device** (Bitwarden's own servers only). One time, with your
   personal API key. rbw uses the key once and doesn't store it.
4. **Log in.** Master password, then 2FA, in rbw's prompt window.
5. **Keyboard shortcut.** `SUPER + ALT + P` opens a searchable vault menu. It's
   added to `~/.config/hypr/bindings.lua` in a marked block, and refused if
   `SUPER + ALT + P` is already taken.

Passwords and API keys are only ever typed into rbw's own pinentry window,
never into the panel: shell plugins share one QML scene, so the panel holds no
secrets.

### rbw settings

Saving the account sets three rbw options, but only those still at rbw's
defaults, so an existing rbw setup keeps its own choices:

| Option | Set to | rbw default |
|---|---|---|
| `pinentry` | `pinentry-qt` | `pinentry` |
| `lock_timeout` | `900` (15 min) | `3600` |
| `sync_interval` | `900` (15 min) | `3600` |

## Use

- `SUPER + ALT + P`: pick an item, copy its password, username, TOTP code or notes.
- Bar icon: red when setup is needed, dimmed when locked, normal when unlocked.
  Right-click to lock or unlock. The panel has Search (`S`), Lock/Unlock (`L`),
  Sync (`Y`) and Log out.
- Copies are marked sensitive, so Omarchy's clipboard history ignores them, and
  they're cleared after 30s unless you copied something else meanwhile. Set
  `BW_CLEAR_SECONDS` to change that.

### When the vault locks

- **Before suspend.** The plugin holds a logind delay inhibitor, so the system
  waits for the vault to lock before sleeping (up to logind's
  `InhibitDelayMaxSec`).
- **When the screen locks.** Omarchy doesn't let plugins subscribe to the lock
  screen, so the plugin checks every 2 seconds while rbw's agent is running.
  The vault can stay unlocked for up to 2 seconds after the screen locks.
- **After `lock_timeout`** of not using the vault (15 minutes by default, see above).

## Requirements

- Omarchy 4 with the Lua Hyprland config (`~/.config/hypr/bindings.lua`).
- rbw 1.15. While the vault is locked, the plugin reads rbw's cache file to
  tell whether you're logged in, because rbw has no command for that. If a
  future rbw changes that file, a locked vault shows as logged out; the
  panel's Log in button still unlocks it.
- Two-factor: authenticator app, email and YubiKey OTP work. WebAuthn/passkeys
  and Duo don't, because rbw doesn't support them.

## Remove

1. Remove the shortcut from the panel's setup section, or run
   `~/.config/omarchy/plugins/adami.bitwarden/bin/bw-setup keybind-remove`.
   If you skip this, the shortcut stays in `bindings.lua` but does nothing.
2. `omarchy plugin remove adami.bitwarden`
3. Optionally, `rbw purge` removes the local vault copy and
   `sudo pacman -Rs rbw` removes rbw.

## Not included

Autotype, the SSH agent, biometric unlock, browser-extension integration, and
creating or editing items (use the web vault or browser extension for those).

## Layout

| Path | Purpose |
|---|---|
| `manifest.json` | Plugin manifest: a bar widget plus a service |
| `Panel.qml` | Bar icon and popup: setup steps, then vault controls |
| `Service.qml` | Runs `bw-guard` and answers the shortcut (one per shell) |
| `bin/bw-status` | Read-only status as JSON for the panel |
| `bin/bw-setup` | The actions behind the panel's buttons |
| `bin/bw-menu` | The vault picker the shortcut opens |
| `bin/bw-guard` | Locks the vault on screen lock and before suspend |
| `bin/bw-common` | Helpers shared by the scripts |

## Development

Clone the repo and symlink it into `~/.config/omarchy/plugins/adami.bitwarden`.
The shell doesn't hot-reload a symlinked plugin; run `omarchy restart shell`
after changing it.

## License

[MIT](LICENSE)
