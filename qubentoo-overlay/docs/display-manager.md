# Display Manager Configuration for Qubes GUI Daemon

Both the dom0 `qubes-gui-daemon` and the domU `qubes-gui-agent` need to
know the OpenRC service name of the display manager they should start after.
This is configurable so that Qubentoo is not locked to a single DM.

## How it works

The OpenRC `depend()` function is evaluated once, when the service is loaded.
The init script reads `QUBES_GUI_DM` from its conf.d file at source time so
that OpenRC sees the correct dependency at evaluation:

```sh
# /etc/init.d/qubes-gui-daemon  (excerpt)
: ${QUBES_GUI_DM:=xdm}

depend() {
    need qubesd qubes-db qubes-rpc-proxy
    need "${QUBES_GUI_DM}"
}
```

The variable is set in `/etc/conf.d/qubes-gui-daemon` (dom0) and
`/etc/conf.d/qubes-gui-agent` (domU).

## Supported display managers

| DM | OpenRC service name | Gentoo package | USE flags |
|----|--------------------|--------------------|-----------|
| xdm | `xdm` | `x11-apps/xdm` | *(none required)* |
| LightDM | `lightdm` | `x11-misc/lightdm` | `gtk` for greeter |
| SDDM | `sddm` | `x11-misc/sddm` | `qt5` or `qt6` |
| GDM | `gdm` | `gnome-base/gdm` | `gnome` (heavy) |

> **Recommendation for Qubentoo dom0:** use `lightdm` with the GTK greeter
> or `xdm` for a minimal footprint. GDM pulls in half of GNOME and conflicts
> with the `-gnome` USE flag in the base profile.

## Switching display managers

### 1. Install the new DM

```sh
# Example: switch to LightDM
emerge --quiet x11-misc/lightdm x11-misc/lightdm-gtk-greeter
```

### 2. Update conf.d (dom0)

```sh
# /etc/conf.d/qubes-gui-daemon
QUBES_GUI_DM="lightdm"
```

### 3. Update conf.d (domU template — if using qubes-gui-agent)

```sh
# /etc/conf.d/qubes-gui-agent  (inside the template)
QUBES_GUI_DM="lightdm"
```

### 4. Swap runlevel entries

```sh
rc-update del xdm default
rc-update add lightdm default
```

### 5. Restart services

```sh
rc-service xdm stop
rc-service lightdm start
rc-service qubes-gui-daemon restart
```

## USE flags for dom0 make.conf

Add the appropriate USE flag depending on your chosen DM.
The base profile sets `-gnome -kde -pulseaudio`; override only what you need:

```sh
# /etc/portage/package.use/display-manager

# LightDM with GTK greeter
x11-misc/lightdm gtk
x11-misc/lightdm-gtk-greeter -gnome

# SDDM with Qt5
x11-misc/sddm qt5
```

## Non-interactive bootstrap

If you run `bootstrap-dom0.sh` non-interactively (e.g. from a script or
CI), set `DM_CHOICE` in the environment before running:

```sh
DM_CHOICE=lightdm bash scripts/bootstrap-dom0.sh
```

This skips the interactive prompt and writes `QUBES_GUI_DM="lightdm"` to
`/etc/conf.d/qubes-gui-daemon` directly.

## Troubleshooting

**qubes-gui-daemon fails to start with "service not running" warning**

The init script checks that `${QUBES_GUI_DM}` is running before starting.
Verify the DM is up:

```sh
rc-service "${QUBES_GUI_DM}" status
```

If it shows stopped, start it:

```sh
rc-service "${QUBES_GUI_DM}" start
```

**Wrong QUBES_GUI_DM value persists after editing conf.d**

OpenRC caches service dependencies. After changing conf.d, restart the service
rather than reloading:

```sh
rc-service qubes-gui-daemon restart
```
