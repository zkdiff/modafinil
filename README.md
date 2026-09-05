# Modafinil

A macOS menu bar app that prevents your MacBook from falling asleep, both when the lid is open and when the lid is closed.

When the lid is closed, it lets the display turn off like normal to preserve battery and reduce heat.

Motivated by the need to let coding agents stay running while you carry your MacBook around.

<p>
  <img width="516" height="254" alt="demo" src="https://github.com/user-attachments/assets/b6e27ae7-46af-4497-ab59-fe7f5642cc41" />
</p>

## Installation & Usage

Install through the latest `.dmg` in Releases. Supports both Apple Silicon and Intel Macs (universal binary).

Requires App Background Activity permission (`System Settings -> General -> Login Items & Extensions`). Should pop up automatically on first activation.

Left click to activate/deactivate. Right click for menu, where you can optionally set a time limit, quit the app, and also uninstall it.

Requires macOS 13+.

---

# Vigil (permanent never-sleep)

Sibling utility in this repo for a different goal: **the Mac must not sleep, period** — battery, MagSafe, USB-C, or any other power source — including after reboot.

| | **Modafinil** | **Vigil** |
|--|---------------|-----------------|
| Intent | Temporary session (“on modafinil”) | Permanent system policy |
| Toggle | Left-click on/off, optional timer | No off-toggle; only uninstall disables |
| Quit app | Restores normal sleep | Leaves never-sleep running |
| Reboot | Starts off | Daemon re-applies policy at boot |
| Lid closed | System awake, display off | Same |

### Behavior

- Privileged LaunchDaemon (`KeepAlive` + `RunAtLoad`) applies `pmset -a` settings so sleep is disabled on **all** power sources.
- Re-asserts the policy about once a minute so nothing silently undoes it.
- Display may still turn off when the lid closes (heat/battery); the machine stays awake.
- Menu bar app installs the daemon, registers itself as a login item, shows status, and offers **Disable & Uninstall**.
- **Quit Menu (keep never-sleep)** only hides the menu bar icon; the daemon keeps the policy.

### Build

```sh
# Universal signed app bundle → dist/Vigil.app
./build/build-vigil.sh

# Local signing identity override
SIGN_IDENTITY="Apple Development: Your Name (TEAMID)" ./build/build-vigil.sh
```

Move `Vigil.app` to `/Applications`, open it, and allow **Login Items & Extensions** when prompted.

### Uninstall

Use **Disable & Uninstall Vigil…** in the menu. That restores normal sleep settings, unregisters the daemon and login item, and removes the app.

### Conflict with Modafinil

Do not run both at once. Modafinil’s helper restores sleep when its session ends, which fights Vigil’s permanent policy. Prefer one tool for a given machine.
