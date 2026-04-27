# Contributing to Qubentoo

Thank you for contributing. This document covers how to write new ebuilds,
add OpenRC init scripts, and get your changes tested before opening a PR.

---

## 1. Overlay conventions

### EAPI and eclass

All ebuilds **must** use EAPI=8:

```bash
EAPI=8
```

For Qubes OS components, inherit the `qubes` eclass:

```bash
inherit qubes
```

For Python packages, add `python-single-r1` before `qubes`:

```bash
PYTHON_COMPAT=( python3_{10,11,12} )
inherit python-single-r1 qubes
```

### PYTHON_COMPAT

Every Python ebuild in the overlay must list exactly:
```bash
PYTHON_COMPAT=( python3_{10,11,12} )
```

This is validated by `scripts/test-bootstrap.sh`. Do not deviate without
updating the active `PYTHON_SINGLE_TARGET` in `profiles/base/make.defaults`.

### SRC_URI pattern

Use the `qubes_src_uri` helper from `qubes.eclass` for all QubesOS GitHub
packages:

```bash
QUBES_REPO="qubes-my-package"     # GitHub repo name (set if different from ${PN})
SRC_URI="$(qubes_src_uri)"        # expands to github.com/QubesOS/<repo>/archive/v${PV}.tar.gz
```

For non-QubesOS sources, write the SRC_URI manually.

### No systemd units

Never install systemd units. The `qubes_src_install` function in `qubes.eclass`
removes `/lib/systemd` and `/usr/lib/systemd` from `${D}` automatically.
Any ebuild that calls `emake install` directly (not via the eclass) must also
remove these directories:

```bash
rm -rf "${D}/lib/systemd" "${D}/usr/lib/systemd" || true
```

---

## 2. OpenRC init script template

Every daemon package must ship an OpenRC init script in
`files/openrc/<service-name>` and install it with `newinitd`.

Copy and fill in this template:

```bash
#!/sbin/openrc-run
# <service-name> — one-line description

description="<Human-readable description>"
pidfile="/run/qubes/<service-name>.pid"
command="/usr/sbin/<daemon-binary>"
command_args="--pidfile=${pidfile}"
command_background="yes"
start_stop_daemon_args="--background --make-pidfile --pidfile ${pidfile}"

depend() {
	# List hard runtime dependencies (services that must be running first)
	need <dep1> <dep2>

	# List services that should start AFTER this one (optional)
	before <svc1>

	# Prevent starting inside containers where Xen is absent
	keyword -lxc -openvz -prefix
}

start_pre() {
	# Create runtime directories, validate config, etc.
	checkpath -d -m 0755 /run/qubes
}

# Only override start()/stop() if start-stop-daemon defaults are not sufficient.
# For most daemons, the variables above (command, pidfile, etc.) are enough.
```

**Rules:**
- Always use `keyword -lxc -openvz -prefix` to avoid breaking containers
- Always call `checkpath -d /run/qubes` in `start_pre()` for consistency
- Do not `need` a display manager by name — use `QUBES_GUI_DM` from conf.d
  (see [docs/display-manager.md](docs/display-manager.md))

---

## 3. conf.d file template

Every tunable must live in a conf.d file, not hardcoded in the init script:

```bash
# /etc/conf.d/<service-name> — <Human-readable description>

# Socket path
SERVICE_SOCKET="/run/qubes/<service-name>.sock"

# Log level: DEBUG | INFO | WARNING | ERROR
SERVICE_LOG_LEVEL="INFO"
```

Install it with `newconfd`:

```bash
newconfd "${FILESDIR}/confd/<service-name>" <service-name>
```

---

## 4. Writing a new ebuild — step by step

1. **Create the category/package directory:**
   ```bash
   mkdir -p sys-apps/my-qubes-package/files/openrc
   mkdir -p sys-apps/my-qubes-package/files/confd
   ```

2. **Write the ebuild** at `sys-apps/my-qubes-package/my-qubes-package-X.Y.Z.ebuild`
   using the patterns above.

3. **Write the OpenRC init script** at `files/openrc/my-qubes-package`.

4. **Write the conf.d file** at `files/confd/my-qubes-package`.

5. **Run the test suite locally:**
   ```bash
   make dry-run     # emerge --pretend validation
   make verify      # repoman QA scan
   ```

6. **Generate the Manifest** (requires a live Portage host):
   ```bash
   ebuild sys-apps/my-qubes-package/my-qubes-package-X.Y.Z.ebuild manifest
   # or
   make manifests
   ```

7. **Open a PR** — the GitHub Actions workflow will run `make verify` automatically.

---

## 5. Pre-PR checklist

Before opening a pull request, confirm every item:

**Ebuild quality:**
- [ ] EAPI=8 declared
- [ ] PYTHON_COMPAT uses `python3_{10,11,12}` exactly (if Python package)
- [ ] No hardcoded `/usr/lib/systemd` paths; systemd removal is handled
- [ ] `KEYWORDS="~amd64"` (testing keyword; we do not stable-keyword yet)
- [ ] All RDEPEND entries exist in the overlay or upstream Gentoo tree
- [ ] `src_install` does not install to `/usr/local`
- [ ] `LICENSE` is correct

**OpenRC service:**
- [ ] `depend()` function present with at least one `need`
- [ ] `keyword -lxc -openvz -prefix` in `depend()`
- [ ] `checkpath -d /run/qubes` in `start_pre()`
- [ ] Service is registered with `rc-update` in `pkg_postinst` instructions
- [ ] No display manager hardcoded — uses `QUBES_GUI_DM` from conf.d

**Testing:**
- [ ] `make dry-run` exits 0
- [ ] `make verify` exits 0 (no errors)
- [ ] If a new daemon: manually tested that `rc-service start/stop` work
- [ ] Init script passes bash syntax check: `bash -n files/openrc/<name>`

**Docs:**
- [ ] `docs/dependency-graph.md` updated if the new package has new deps
- [ ] `README.md` status table updated if a major component is now complete

---

## 6. Commit message format

```
sys-apps/qubes-foo: add version 4.2.1 ebuild

Brief description of what changed and why. Reference upstream issue or
QubesOS GitHub PR if applicable.
```

Use the standard Gentoo commit prefix `<cat>/<pkg>:` for package changes,
and `scripts:` / `docs:` / `eclass:` for non-package changes.

---

## 7. Reporting issues

- **Emerge failures:** include the full output of `emerge -pv <pkg>` and
  `emerge <pkg>` up to the first error
- **OpenRC service failures:** include `rc-service <name> start` output
  and `/var/log/rc.log`
- **Xen boot failures:** include Xen hypervisor boot log from serial console
  (add `loglvl=all guest_loglvl=all` to Xen cmdline in GRUB)
