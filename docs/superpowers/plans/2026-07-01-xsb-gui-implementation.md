# xsb-gui Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build `xsb-gui`, a PyQt6 wizard that migrates an installed XeroLinux system from GRUB to Limine and then enables Secure Boot via `sbctl`, packaged as a pacman package.

**Architecture:** A PyQt6 GUI (runs as the normal user) drives a root-privileged Bash helper (`xsb-helper`) via `pkexec`. The helper does all real system mutation and emits JSON-lines progress events on stdout; the GUI parses these to drive a `QWizard` (Welcome → Preflight → Confirm → Migrate → SecureBoot → Done).

**Tech Stack:** Python 3 + PyQt6 (GUI), Bash (root helper), `bats-core` (Bash tests), `pytest` + `pytest-qt` (Python tests), polkit (privilege escalation), pacman/PKGBUILD (packaging).

## Global Constraints

- UEFI only — the app checks `/sys/firmware/efi` and refuses to proceed (with a clear message) on BIOS systems.
- GUI process never runs as root; only `xsb-helper` (invoked via `pkexec`) touches privileged state.
- Package name: `xsb-gui`. Binary: `/usr/bin/xsb-gui`. Helper: `/usr/lib/xsb-gui/xsb-helper` + `/usr/lib/xsb-gui/lib/*.sh`.
- Dependencies: `python-pyqt6`, `polkit`, `limine`, `limine-mkinitcpio-hook`, `sbctl`, `efibootmgr`.
- Support both plain and LUKS-encrypted root (detect existing mkinitcpio hook family, don't switch it).
- Detect other OSes (Windows Boot Manager, etc.) via `efibootmgr -v` and add them as Limine chainload entries.
- Migration order is fixed: install + configure + deploy Limine, verify its EFI boot entry exists, **then** remove GRUB. Never remove GRUB before Limine is verified present.
- Every mutating Bash function goes through a `run_cmd` wrapper honoring a `DRY_RUN` flag, so the same code path both (a) previews actions for the GUI's confirm screen and (b) is testable without touching a real system.
- Every detection function takes its system-data input as an optional parameter with a default that shells out to the real command — this is the project's standard testability pattern; tests always pass canned input directly rather than mocking the real system.
- Not in scope for this plan: adding `xsb-gui` to `XeroBuild/packages.x86_64`, full GRUB-theme-parity Limine branding (basic branding only), deleting the old `xero-secureboot` script from `XeroBuild` (separate follow-up).

---

## File Structure

```
LimineSecureBoot/
├── PKGBUILD
├── xsb-gui.install
├── LICENSE
├── README.md
├── xyz.xerolinux.xsb-gui.policy
├── xsb-gui.desktop
├── xsb-gui                    # GUI entrypoint script
├── xsb_gui/
│   ├── __init__.py
│   ├── app.py
│   ├── helper_runner.py
│   ├── parsing.py
│   └── pages/
│       ├── __init__.py
│       ├── welcome_page.py
│       ├── preflight_page.py
│       ├── confirm_page.py
│       ├── migrate_page.py
│       ├── secureboot_page.py
│       └── done_page.py
├── xsb-helper                 # root helper entrypoint
├── lib/
│   ├── jsonevent.sh
│   ├── preflight.sh
│   ├── chainload.sh
│   ├── migrate.sh
│   └── secureboot.sh
└── tests/
    ├── bats/
    │   ├── jsonevent.bats
    │   ├── preflight.bats
    │   ├── chainload.bats
    │   ├── migrate.bats
    │   ├── secureboot.bats
    │   └── xsb-helper.bats
    └── python/
        ├── test_parsing.py
        ├── test_helper_runner.py
        ├── test_welcome_page.py
        ├── test_preflight_page.py
        ├── test_confirm_page.py
        ├── test_migrate_secureboot_pages.py
        └── test_app.py
```

---

### Task 1: Repo scaffold, packaging metadata

**Files:**
- Create: `LICENSE`
- Create: `README.md`
- Create: `PKGBUILD`
- Create: `xsb-gui.install`
- Create: `xyz.xerolinux.xsb-gui.policy`
- Create: `xsb-gui.desktop`

**Interfaces:**
- Produces: package name `xsb-gui`, polkit action id `xyz.xerolinux.xsb-gui.run-helper`, desktop file `Exec=/usr/bin/xsb-gui`.

- [ ] **Step 1: Write the polkit policy file**

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE policyconfig PUBLIC "-//freedesktop//DTD PolicyKit Policy Configuration 1.0//EN"
 "http://www.freedesktop.org/standards/PolicyKit/1/policyconfig.dtd">
<policyconfig>
  <vendor>XeroLinux</vendor>
  <vendor_url>https://xerolinux.xyz</vendor_url>
  <action id="xyz.xerolinux.xsb-gui.run-helper">
    <description>Migrate bootloader to Limine and enable Secure Boot</description>
    <message>Authentication is required to modify the bootloader and Secure Boot configuration</message>
    <icon_name>xsb-gui</icon_name>
    <defaults>
      <allow_any>auth_admin</allow_any>
      <allow_inactive>auth_admin</allow_inactive>
      <allow_active>auth_admin_keep</allow_active>
    </defaults>
    <annotate key="org.freedesktop.policykit.exec.path">/usr/lib/xsb-gui/xsb-helper</annotate>
  </action>
</policyconfig>
```

- [ ] **Step 2: Validate the policy file is well-formed XML**

Run: `python3 -c "import xml.dom.minidom; xml.dom.minidom.parse('xyz.xerolinux.xsb-gui.policy')"`
Expected: no output, exit code 0.

- [ ] **Step 3: Write the desktop entry**

```ini
[Desktop Entry]
Type=Application
Name=Limine/SecureBoot Enabler
Comment=Migrate XeroLinux from GRUB to Limine and enable Secure Boot
Exec=/usr/bin/xsb-gui
Icon=xsb-gui
Categories=System;Settings;
Terminal=false
StartupNotify=true
```

- [ ] **Step 4: Validate the desktop file**

Run: `desktop-file-validate xsb-gui.desktop`
Expected: no output (valid). If `desktop-file-validate` isn't installed, `sudo pacman -S --needed desktop-file-utils` first.

- [ ] **Step 5: Write LICENSE, README.md**

`README.md`:
```markdown
# xsb-gui

XeroLinux Limine/SecureBoot Enabler. A guided GUI that migrates an installed
XeroLinux system from GRUB to Limine and enables Secure Boot via sbctl.

## Development

- Bash helper tests: `bats tests/bats/`
- Python GUI tests: `pytest tests/python/`

## Testing

Bootloader and Secure Boot changes are unsafe to iterate on with real
hardware. Develop and test in a UEFI VM (QEMU + OVMF) with snapshots.
```

(Use an MIT or GPL-3.0-or-later LICENSE file matching `calamaresx-cfg`'s license — copy its exact license text.)

- [ ] **Step 6: Write the PKGBUILD**

```bash
# Maintainer: XeroLinux <team@xerolinux.xyz>
pkgname=xsb-gui
pkgver=0.1.0
pkgrel=1
pkgdesc="XeroLinux Limine/SecureBoot Enabler"
arch=('x86_64')
url="https://github.com/xerolinux/xsb-gui"
license=('GPL-3.0-or-later')
depends=('python-pyqt6' 'polkit' 'limine' 'limine-mkinitcpio-hook' 'sbctl' 'efibootmgr')
install="${pkgname}.install"
source=()
sha256sums=()

package() {
    install -Dm755 "${srcdir}/../xsb-gui" "${pkgdir}/usr/bin/xsb-gui"
    install -Dm755 "${srcdir}/../xsb-helper" "${pkgdir}/usr/lib/xsb-gui/xsb-helper"
    install -d "${pkgdir}/usr/lib/xsb-gui/lib"
    install -Dm644 "${srcdir}/../lib/"*.sh "${pkgdir}/usr/lib/xsb-gui/lib/"
    install -d "${pkgdir}/usr/lib/python3.13/site-packages/xsb_gui"
    cp -a "${srcdir}/../xsb_gui/." "${pkgdir}/usr/lib/python3.13/site-packages/xsb_gui/"
    install -Dm644 "${srcdir}/../xsb-gui.desktop" "${pkgdir}/usr/share/applications/xsb-gui.desktop"
    install -Dm644 "${srcdir}/../xyz.xerolinux.xsb-gui.policy" \
        "${pkgdir}/usr/share/polkit-1/actions/xyz.xerolinux.xsb-gui.policy"
    install -Dm644 "${srcdir}/../xsb_gui/assets/xsb-gui.png" \
        "${pkgdir}/usr/share/icons/hicolor/256x256/apps/xsb-gui.png"
}
```

- [ ] **Step 7: Write `xsb-gui.install`**

```bash
post_install() {
    update-desktop-database -q /usr/share/applications &>/dev/null || true
    gtk-update-icon-cache -q /usr/share/icons/hicolor &>/dev/null || true
}

post_upgrade() {
    post_install
}

post_remove() {
    post_install
}
```

- [ ] **Step 8: Commit**

```bash
git add LICENSE README.md PKGBUILD xsb-gui.install xyz.xerolinux.xsb-gui.policy xsb-gui.desktop
git commit -m "chore: scaffold packaging metadata for xsb-gui"
```

---

### Task 2: `lib/jsonevent.sh` — JSON event emission + dry-run command runner

**Files:**
- Create: `lib/jsonevent.sh`
- Test: `tests/bats/jsonevent.bats`

**Interfaces:**
- Produces: `json_escape(str) -> escaped str on stdout`, `emit_event(event, level, message) -> prints one JSON line`, `run_cmd(cmd...) -> executes or previews depending on $DRY_RUN`.
- Consumes: global `DRY_RUN` (unset or `0` = execute; `1` = preview only).

- [ ] **Step 1: Install bats-core if not present**

Run: `command -v bats || sudo pacman -S --needed bats`
Expected: `bats` available on PATH.

- [ ] **Step 2: Write the failing test**

`tests/bats/jsonevent.bats`:
```bash
#!/usr/bin/env bats

setup() {
  source "${BATS_TEST_DIRNAME}/../../lib/jsonevent.sh"
}

@test "json_escape escapes backslashes and quotes" {
  result="$(json_escape 'say "hi" \ there')"
  [ "$result" = 'say \"hi\" \\ there' ]
}

@test "emit_event prints a well-formed JSON line" {
  result="$(emit_event "preflight_start" "info" "checking system")"
  [ "$result" = '{"event":"preflight_start","level":"info","message":"checking system"}' ]
}

@test "run_cmd executes the command when DRY_RUN is unset" {
  unset DRY_RUN
  result="$(run_cmd echo hello)"
  [[ "$result" == *"hello"* ]]
}

@test "run_cmd previews without executing when DRY_RUN=1" {
  DRY_RUN=1
  result="$(run_cmd rm -f /nonexistent-marker-file)"
  [[ "$result" == *'"event":"would_run"'* ]]
  [[ "$result" == *"rm -f /nonexistent-marker-file"* ]]
}
```

- [ ] **Step 3: Run tests to verify they fail**

Run: `bats tests/bats/jsonevent.bats`
Expected: FAIL — `lib/jsonevent.sh: No such file or directory`.

- [ ] **Step 4: Write `lib/jsonevent.sh`**

```bash
#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later

json_escape() {
    local s="$1"
    s="${s//\\/\\\\}"
    s="${s//\"/\\\"}"
    s="${s//$'\n'/\\n}"
    s="${s//$'\t'/\\t}"
    s="${s//$'\r'/\\r}"
    printf '%s' "$s"
}

emit_event() {
    local event="$1" level="$2" message="$3"
    printf '{"event":"%s","level":"%s","message":"%s"}\n' \
        "$(json_escape "$event")" "$(json_escape "$level")" "$(json_escape "$message")"
}

run_cmd() {
    if [[ "${DRY_RUN:-0}" == "1" ]]; then
        emit_event "would_run" "info" "$*"
    else
        emit_event "running" "info" "$*"
        local output status
        output="$("$@" 2>&1)"
        status=$?
        if [[ -n "$output" ]]; then
            while IFS= read -r line; do
                emit_event "command_output" "info" "$line"
            done <<< "$output"
        fi
        return "$status"
    fi
}
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `bats tests/bats/jsonevent.bats`
Expected: PASS (4 tests). (Amended after review: `run_cmd`'s non-dry-run branch was
reworked to emit wrapped command output as `command_output` events instead of letting
it interleave raw with the JSON protocol, and `json_escape` now also escapes tab/CR —
see the corrected code above. The bats file now has 9 tests total.)

- [ ] **Step 6: Commit**

```bash
git add lib/jsonevent.sh tests/bats/jsonevent.bats
git commit -m "feat: add JSON event emission and dry-run command runner"
```

---

### Task 3: `lib/preflight.sh` — UEFI, ESP, partition table detection

**Files:**
- Create: `lib/preflight.sh`
- Test: `tests/bats/preflight.bats`

**Interfaces:**
- Consumes: nothing from earlier tasks.
- Produces: `is_uefi(efi_dir="/sys/firmware/efi") -> bool`, `find_esp_mountpoint(root="", mounted_paths=$(findmnt -rno TARGET)) -> prints mountpoint, returns 1 if none found`, `detect_partition_table(pttype_output="") -> bool`.

- [ ] **Step 1: Write the failing test**

`tests/bats/preflight.bats`:
```bash
#!/usr/bin/env bats

setup() {
  source "${BATS_TEST_DIRNAME}/../../lib/jsonevent.sh"
  source "${BATS_TEST_DIRNAME}/../../lib/preflight.sh"
}

@test "is_uefi true when the efi dir exists" {
  run is_uefi "$BATS_TEST_TMPDIR"
  [ "$status" -eq 0 ]
}

@test "is_uefi false when the efi dir is missing" {
  run is_uefi "$BATS_TEST_TMPDIR/does-not-exist"
  [ "$status" -eq 1 ]
}

@test "find_esp_mountpoint finds /boot/efi when mounted and present" {
  mkdir -p "$BATS_TEST_TMPDIR/boot/efi/EFI"
  result="$(find_esp_mountpoint "$BATS_TEST_TMPDIR" $'/\n/boot/efi\n/home')"
  [ "$result" = "/boot/efi" ]
}

@test "find_esp_mountpoint returns failure when nothing matches" {
  run find_esp_mountpoint "$BATS_TEST_TMPDIR" $'/\n/home'
  [ "$status" -eq 1 ]
}

@test "detect_partition_table true for gpt" {
  run detect_partition_table "gpt"
  [ "$status" -eq 0 ]
}

@test "detect_partition_table false for dos" {
  run detect_partition_table "dos"
  [ "$status" -eq 1 ]
}
```

- [ ] **Step 2: Run to verify failure**

Run: `bats tests/bats/preflight.bats`
Expected: FAIL — `lib/preflight.sh: No such file or directory`.

- [ ] **Step 3: Write `lib/preflight.sh` (part 1)**

```bash
#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later

is_uefi() {
    local efi_dir="${1-/sys/firmware/efi}"
    [[ -d "$efi_dir" ]]
}

find_esp_mountpoint() {
    local root="${1-}"
    local mounted_paths="${2-$(findmnt -rno TARGET)}"
    local candidate
    for candidate in /boot/efi /efi /boot; do
        if grep -qx "$candidate" <<< "$mounted_paths" && [[ -d "${root}${candidate}/EFI" ]]; then
            printf '%s' "$candidate"
            return 0
        fi
    done
    return 1
}

detect_partition_table() {
    local pttype_output="${1-}"
    if [[ -z "$pttype_output" ]]; then
        local esp_source parent_disk
        esp_source="$(findmnt -no SOURCE /boot/efi 2>/dev/null)" || true
        if [[ -n "$esp_source" ]]; then
            parent_disk="$(lsblk -no PKNAME "$esp_source" 2>/dev/null)"
            pttype_output="$(lsblk -dno PTTYPE "/dev/$parent_disk" 2>/dev/null)"
        fi
    fi
    [[ "$pttype_output" == "gpt" ]]
}
```

- [ ] **Step 4: Run to verify pass**

Run: `bats tests/bats/preflight.bats`
Expected: PASS (6 tests).

- [ ] **Step 5: Commit**

```bash
git add lib/preflight.sh tests/bats/preflight.bats
git commit -m "feat: add UEFI/ESP/partition-table detection"
```

---

### Task 4: `lib/preflight.sh` — bootloader, LUKS, mkinitcpio hook family detection

**Files:**
- Modify: `lib/preflight.sh`
- Modify: `tests/bats/preflight.bats`

**Interfaces:**
- Consumes: nothing new.
- Produces: `detect_bootloader(pacman_query_output="") -> prints "grub"|"limine"|"none"`, `detect_luks_root(crypttab_content="") -> bool`, `detect_mkinitcpio_hook_family(conf_content="") -> prints "sd-encrypt"|"encrypt"|"none"`.

- [ ] **Step 1: Add failing tests**

Append to `tests/bats/preflight.bats`:
```bash
@test "detect_bootloader reports grub when grub is installed" {
  result="$(detect_bootloader "grub")"
  [ "$result" = "grub" ]
}

@test "detect_bootloader reports limine when limine is installed" {
  result="$(detect_bootloader "limine")"
  [ "$result" = "limine" ]
}

@test "detect_bootloader reports none when neither is installed" {
  result="$(detect_bootloader "")"
  [ "$result" = "none" ]
}

@test "detect_luks_root true when crypttab has an active entry" {
  run detect_luks_root $'# comment\ncryptroot UUID=xxx none luks\n'
  [ "$status" -eq 0 ]
}

@test "detect_luks_root false when crypttab is empty or all comments" {
  run detect_luks_root $'# comment\n\n'
  [ "$status" -eq 1 ]
}

@test "detect_mkinitcpio_hook_family reports sd-encrypt" {
  result="$(detect_mkinitcpio_hook_family 'HOOKS=(base systemd sd-encrypt filesystems)')"
  [ "$result" = "sd-encrypt" ]
}

@test "detect_mkinitcpio_hook_family reports encrypt" {
  result="$(detect_mkinitcpio_hook_family 'HOOKS=(base udev encrypt filesystems)')"
  [ "$result" = "encrypt" ]
}

@test "detect_mkinitcpio_hook_family reports none" {
  result="$(detect_mkinitcpio_hook_family 'HOOKS=(base udev filesystems)')"
  [ "$result" = "none" ]
}
```

- [ ] **Step 2: Run to verify failure**

Run: `bats tests/bats/preflight.bats`
Expected: FAIL — the 8 new tests fail (functions not defined).

- [ ] **Step 3: Add the functions to `lib/preflight.sh`**

```bash
detect_bootloader() {
    local installed="${1-$(pacman -Qq grub limine 2>/dev/null)}"
    if grep -qx grub <<< "$installed"; then
        printf 'grub'
    elif grep -qx limine <<< "$installed"; then
        printf 'limine'
    else
        printf 'none'
    fi
}

detect_luks_root() {
    local crypttab_content="${1-$(cat /etc/crypttab 2>/dev/null)}"
    grep -vE '^[[:space:]]*(#|$)' <<< "$crypttab_content" | grep -q .
}

detect_mkinitcpio_hook_family() {
    local conf_content="${1-$(cat /etc/mkinitcpio.conf 2>/dev/null)}"
    if grep -qE '(^|[[:space:]])sd-encrypt([[:space:]]|$)' <<< "$conf_content"; then
        printf 'sd-encrypt'
    elif grep -qE '(^|[[:space:]])encrypt([[:space:]]|$)' <<< "$conf_content"; then
        printf 'encrypt'
    else
        printf 'none'
    fi
}
```

- [ ] **Step 4: Run to verify pass**

Run: `bats tests/bats/preflight.bats`
Expected: PASS (14 tests).

- [ ] **Step 5: Commit**

```bash
git add lib/preflight.sh tests/bats/preflight.bats
git commit -m "feat: add bootloader, LUKS, and mkinitcpio hook detection"
```

---

### Task 5: `lib/chainload.sh` — other-OS detection

**Files:**
- Create: `lib/chainload.sh`
- Test: `tests/bats/chainload.bats`

**Interfaces:**
- Produces: `detect_other_os(efibootmgr_output="$(efibootmgr -v 2>/dev/null)") -> prints one OS label per line (excludes XeroLinux/Limine entries)`.

- [ ] **Step 1: Write the failing test**

`tests/bats/chainload.bats`:
```bash
#!/usr/bin/env bats

setup() {
  source "${BATS_TEST_DIRNAME}/../../lib/chainload.sh"
}

@test "detect_other_os finds Windows Boot Manager and excludes XeroLinux" {
  sample=$'BootCurrent: 0001\nBootOrder: 0000,0001\nBoot0000* XeroLinux\tHD(1,GPT,...)\nBoot0001* Windows Boot Manager\tHD(1,GPT,...)'
  result="$(detect_other_os "$sample")"
  [ "$result" = "Windows Boot Manager" ]
}

@test "detect_other_os returns nothing when only XeroLinux is present" {
  sample=$'BootCurrent: 0000\nBootOrder: 0000\nBoot0000* XeroLinux\tHD(1,GPT,...)'
  result="$(detect_other_os "$sample")"
  [ -z "$result" ]
}
```

- [ ] **Step 2: Run to verify failure**

Run: `bats tests/bats/chainload.bats`
Expected: FAIL — `lib/chainload.sh: No such file or directory`.

- [ ] **Step 3: Write `lib/chainload.sh`**

```bash
#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later

detect_other_os() {
    local efibootmgr_output="${1-$(efibootmgr -v 2>/dev/null)}"
    grep -E '^Boot[0-9A-Fa-f]{4}\*?[[:space:]]' <<< "$efibootmgr_output" \
        | grep -viE 'xerolinux|limine' \
        | sed -E 's/^Boot[0-9A-Fa-f]{4}\*?[[:space:]]+//' \
        | sed -E 's/[[:space:]]+HD\(.*$//'
}
```

- [ ] **Step 4: Run to verify pass**

Run: `bats tests/bats/chainload.bats`
Expected: PASS (2 tests).

- [ ] **Step 5: Commit**

```bash
git add lib/chainload.sh tests/bats/chainload.bats
git commit -m "feat: add other-OS detection for Limine chainload entries"
```

---

### Task 6: `lib/secureboot.sh` — Secure Boot firmware state detection

**Files:**
- Create: `lib/secureboot.sh`
- Test: `tests/bats/secureboot.bats`

**Interfaces:**
- Produces: `detect_secureboot_state(sbctl_status_output="") -> prints "enabled"|"setup_mode"|"disabled"|"unsupported"`.

- [ ] **Step 1: Write the failing test**

`tests/bats/secureboot.bats`:
```bash
#!/usr/bin/env bats

setup() {
  source "${BATS_TEST_DIRNAME}/../../lib/secureboot.sh"
}

@test "detect_secureboot_state reports enabled" {
  result="$(detect_secureboot_state $'Installed: ✓\nSetup Mode: Disabled\nSecure Boot: Enabled')"
  [ "$result" = "enabled" ]
}

@test "detect_secureboot_state reports setup_mode" {
  result="$(detect_secureboot_state $'Installed: ✓\nSetup Mode: Enabled\nSecure Boot: Disabled')"
  [ "$result" = "setup_mode" ]
}

@test "detect_secureboot_state reports disabled" {
  result="$(detect_secureboot_state $'Installed: ✓\nSetup Mode: Disabled\nSecure Boot: Disabled')"
  [ "$result" = "disabled" ]
}

@test "detect_secureboot_state reports unsupported when sbctl gives no output" {
  result="$(detect_secureboot_state "")"
  [ "$result" = "unsupported" ]
}
```

- [ ] **Step 2: Run to verify failure**

Run: `bats tests/bats/secureboot.bats`
Expected: FAIL — `lib/secureboot.sh: No such file or directory`.

- [ ] **Step 3: Write `lib/secureboot.sh` (part 1)**

```bash
#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later

detect_secureboot_state() {
    local sbctl_status_output="${1-$(sbctl status 2>/dev/null)}"
    if [[ -z "$sbctl_status_output" ]]; then
        printf 'unsupported'
    elif grep -qE 'Secure Boot:[[:space:]]*Enabled' <<< "$sbctl_status_output"; then
        printf 'enabled'
    elif grep -qE 'Setup Mode:[[:space:]]*Enabled' <<< "$sbctl_status_output"; then
        printf 'setup_mode'
    else
        printf 'disabled'
    fi
}
```

- [ ] **Step 4: Run to verify pass**

Run: `bats tests/bats/secureboot.bats`
Expected: PASS (4 tests).

- [ ] **Step 5: Commit**

```bash
git add lib/secureboot.sh tests/bats/secureboot.bats
git commit -m "feat: add Secure Boot firmware state detection"
```

---

### Task 7: `lib/preflight.sh` — result assembly + `cmd_preflight`/`cmd_status` orchestrators

**Files:**
- Modify: `lib/preflight.sh`
- Modify: `tests/bats/preflight.bats`

**Interfaces:**
- Consumes: `is_uefi`, `find_esp_mountpoint`, `detect_partition_table`, `detect_bootloader`, `detect_luks_root`, `detect_mkinitcpio_hook_family` (Tasks 3-4), `detect_other_os` (Task 5), `detect_secureboot_state` (Task 6), `emit_event` (Task 2).
- Produces: `build_json_string_array(items="") -> prints a JSON array string`, `emit_preflight_result(uefi, gpt, esp_mountpoint, bootloader, luks, mkinitcpio_hook, other_os_json, secureboot_state) -> prints one preflight_result JSON line`, `cmd_preflight()`, `cmd_status()`.

- [ ] **Step 1: Write the failing tests**

Append to `tests/bats/preflight.bats`:
```bash
@test "build_json_string_array handles empty input" {
  result="$(build_json_string_array "")"
  [ "$result" = "[]" ]
}

@test "build_json_string_array handles one item" {
  result="$(build_json_string_array "Windows Boot Manager")"
  [ "$result" = '["Windows Boot Manager"]' ]
}

@test "build_json_string_array handles multiple items" {
  result="$(build_json_string_array $'Windows Boot Manager\nsystemd-boot')"
  [ "$result" = '["Windows Boot Manager","systemd-boot"]' ]
}

@test "emit_preflight_result produces valid, well-formed JSON" {
  result="$(emit_preflight_result true true "/boot/efi" "grub" false "none" '[]' "disabled")"
  echo "$result" | python3 -c "import json,sys; d=json.load(sys.stdin); assert d['event']=='preflight_result'; assert d['data']['bootloader']=='grub'"
}

@test "cmd_preflight (not UEFI) emits an error and exits non-zero" {
  is_uefi() { return 1; }
  run cmd_preflight
  [ "$status" -ne 0 ]
  [[ "$output" == *'"event":"error"'* ]]
  [[ "$output" == *"UEFI"* ]]
}

@test "cmd_preflight (UEFI) emits preflight_result" {
  is_uefi() { return 0; }
  find_esp_mountpoint() { echo "/boot/efi"; return 0; }
  detect_partition_table() { return 0; }
  detect_bootloader() { echo "grub"; }
  detect_luks_root() { return 1; }
  detect_mkinitcpio_hook_family() { echo "none"; }
  detect_other_os() { echo ""; }
  detect_secureboot_state() { echo "disabled"; }
  run cmd_preflight
  [ "$status" -eq 0 ]
  [[ "$output" == *'"event":"preflight_result"'* ]]
  [[ "$output" == *'"bootloader":"grub"'* ]]
}
```

- [ ] **Step 2: Run to verify failure**

Run: `bats tests/bats/preflight.bats`
Expected: FAIL — new functions not defined.

- [ ] **Step 3: Add the functions to `lib/preflight.sh`**

```bash
build_json_string_array() {
    local items="$1"
    local out="[" first=1 item
    while IFS= read -r item; do
        [[ -z "$item" ]] && continue
        [[ $first -eq 0 ]] && out+=","
        out+="\"$(json_escape "$item")\""
        first=0
    done <<< "$items"
    out+="]"
    printf '%s' "$out"
}

emit_preflight_result() {
    local uefi="$1" gpt="$2" esp_mountpoint="$3" bootloader="$4" luks="$5" \
          mkinitcpio_hook="$6" other_os_json="$7" secureboot_state="$8"
    printf '{"event":"preflight_result","level":"info","data":{"uefi":%s,"gpt":%s,"esp_mountpoint":"%s","bootloader":"%s","luks":%s,"mkinitcpio_hook":"%s","other_os":%s,"secureboot_state":"%s"}}\n' \
        "$uefi" "$gpt" "$(json_escape "$esp_mountpoint")" "$(json_escape "$bootloader")" \
        "$luks" "$(json_escape "$mkinitcpio_hook")" "$other_os_json" "$(json_escape "$secureboot_state")"
}

cmd_preflight() {
    if ! is_uefi; then
        emit_event "error" "error" "This system is not booted in UEFI mode. Secure Boot and this migration are unavailable."
        return 1
    fi
    emit_event "preflight_step" "info" "Checking EFI system partition"
    local esp_mountpoint
    esp_mountpoint="$(find_esp_mountpoint)" || esp_mountpoint=""
    emit_event "preflight_step" "info" "Checking partition table type"
    local gpt="false"
    detect_partition_table && gpt="true"
    emit_event "preflight_step" "info" "Checking current bootloader"
    local bootloader
    bootloader="$(detect_bootloader)"
    emit_event "preflight_step" "info" "Checking for LUKS-encrypted root"
    local luks="false"
    detect_luks_root && luks="true"
    local mkinitcpio_hook
    mkinitcpio_hook="$(detect_mkinitcpio_hook_family)"
    emit_event "preflight_step" "info" "Checking for other operating systems"
    local other_os_json
    other_os_json="$(build_json_string_array "$(detect_other_os)")"
    emit_event "preflight_step" "info" "Checking Secure Boot firmware state"
    local secureboot_state
    secureboot_state="$(detect_secureboot_state)"
    emit_preflight_result "true" "$gpt" "$esp_mountpoint" "$bootloader" "$luks" \
        "$mkinitcpio_hook" "$other_os_json" "$secureboot_state"
}

cmd_status() {
    local bootloader secureboot_state
    bootloader="$(detect_bootloader)"
    secureboot_state="$(detect_secureboot_state)"
    printf '{"event":"status_result","level":"info","data":{"bootloader":"%s","secureboot_state":"%s"}}\n' \
        "$(json_escape "$bootloader")" "$(json_escape "$secureboot_state")"
}
```

- [ ] **Step 4: Run to verify pass**

Run: `bats tests/bats/preflight.bats`
Expected: PASS (20 tests).

- [ ] **Step 5: Commit**

```bash
git add lib/preflight.sh tests/bats/preflight.bats
git commit -m "feat: assemble preflight result and add cmd_preflight/cmd_status"
```

---

### Task 8: `xsb-helper` entrypoint + end-to-end preflight integration test

**Files:**
- Create: `xsb-helper`
- Test: `tests/bats/xsb-helper.bats`

**Interfaces:**
- Consumes: `cmd_preflight`, `cmd_status` (Task 7).
- Produces: executable `xsb-helper <preflight|migrate|enable-secureboot|status> [--dry-run]`.

- [ ] **Step 1: Write the failing test**

`tests/bats/xsb-helper.bats`:
```bash
#!/usr/bin/env bats

setup() {
  STUB_BIN="$BATS_TEST_TMPDIR/bin"
  mkdir -p "$STUB_BIN"
  cat > "$STUB_BIN/findmnt" <<'EOF'
#!/usr/bin/env bash
if [[ "$*" == *"-no SOURCE /boot/efi"* ]]; then echo "/dev/vda1"; exit 0; fi
echo "/boot/efi"
EOF
  cat > "$STUB_BIN/lsblk" <<'EOF'
#!/usr/bin/env bash
if [[ "$*" == *"PKNAME"* ]]; then echo "vda"; exit 0; fi
echo "gpt"
EOF
  cat > "$STUB_BIN/pacman" <<'EOF'
#!/usr/bin/env bash
echo "grub"
EOF
  cat > "$STUB_BIN/efibootmgr" <<'EOF'
#!/usr/bin/env bash
echo "Boot0000* XeroLinux"
EOF
  cat > "$STUB_BIN/sbctl" <<'EOF'
#!/usr/bin/env bash
echo "Setup Mode: Disabled"
echo "Secure Boot: Disabled"
EOF
  chmod +x "$STUB_BIN"/*
  mkdir -p "$BATS_TEST_TMPDIR/efi/EFI"
  export PATH="$STUB_BIN:$PATH"
}

@test "xsb-helper preflight emits a preflight_result line" {
  mkdir -p /tmp/xsb-fake-efi 2>/dev/null || true
  run "${BATS_TEST_DIRNAME}/../../xsb-helper" preflight
  [ "$status" -eq 0 ]
  [[ "$output" == *'"event":"preflight_result"'* ]]
}

@test "xsb-helper with an unknown subcommand fails clearly" {
  run "${BATS_TEST_DIRNAME}/../../xsb-helper" bogus
  [ "$status" -ne 0 ]
  [[ "$output" == *"Unknown subcommand"* ]]
}
```

- [ ] **Step 2: Run to verify failure**

Run: `bats tests/bats/xsb-helper.bats`
Expected: FAIL — `xsb-helper: No such file or directory`.

- [ ] **Step 3: Write `xsb-helper`**

```bash
#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
set -euo pipefail

HELPER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="$HELPER_DIR/lib"
[[ -d "$LIB_DIR" ]] || LIB_DIR="/usr/lib/xsb-gui/lib"

# shellcheck source=lib/jsonevent.sh
source "$LIB_DIR/jsonevent.sh"
source "$LIB_DIR/preflight.sh"
source "$LIB_DIR/chainload.sh"
source "$LIB_DIR/migrate.sh"
source "$LIB_DIR/secureboot.sh"

DRY_RUN=0
subcommand="${1-}"
shift || true
for arg in "$@"; do
    [[ "$arg" == "--dry-run" ]] && DRY_RUN=1
done
export DRY_RUN

case "$subcommand" in
    preflight) cmd_preflight ;;
    migrate) cmd_migrate ;;
    enable-secureboot) cmd_enable_secureboot ;;
    status) cmd_status ;;
    *)
        emit_event "error" "error" "Unknown subcommand: $subcommand"
        exit 1
        ;;
esac
```

Note: this sources `cmd_migrate` and `cmd_enable_secureboot`, which don't exist until Tasks 9-12. Add temporary stubs to `lib/migrate.sh` and `lib/secureboot.sh` so this task's tests can run in isolation:

`lib/migrate.sh` (new file, stub for now):
```bash
#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later

cmd_migrate() {
    emit_event "error" "error" "migrate not yet implemented"
    return 1
}
```

Append to `lib/secureboot.sh`:
```bash
cmd_enable_secureboot() {
    emit_event "error" "error" "enable-secureboot not yet implemented"
    return 1
}
```

- [ ] **Step 4: Make it executable and run to verify pass**

Run: `chmod +x xsb-helper && bats tests/bats/xsb-helper.bats`
Expected: PASS (2 tests).

- [ ] **Step 5: Commit**

```bash
git add xsb-helper lib/migrate.sh lib/secureboot.sh tests/bats/xsb-helper.bats
git commit -m "feat: add xsb-helper entrypoint with preflight wired end-to-end"
```

---

### Task 9: `lib/migrate.sh` — `build_limine_conf`

**Files:**
- Modify: `lib/migrate.sh`
- Create: `tests/bats/migrate.bats`

**Interfaces:**
- Produces: `build_limine_conf(other_os_list="") -> prints limine.conf text`.

- [ ] **Step 1: Write the failing test**

`tests/bats/migrate.bats`:
```bash
#!/usr/bin/env bats

setup() {
  source "${BATS_TEST_DIRNAME}/../../lib/jsonevent.sh"
  source "${BATS_TEST_DIRNAME}/../../lib/migrate.sh"
}

@test "build_limine_conf includes the XeroLinux entry" {
  result="$(build_limine_conf "")"
  [[ "$result" == *"/XeroLinux"* ]]
  [[ "$result" == *"protocol: linux"* ]]
}

@test "build_limine_conf adds a chainload stanza per other OS" {
  result="$(build_limine_conf "Windows Boot Manager")"
  [[ "$result" == *"/Windows Boot Manager"* ]]
  [[ "$result" == *"protocol: efi_chainload"* ]]
}

@test "build_limine_conf handles multiple other OSes" {
  result="$(build_limine_conf $'Windows Boot Manager\nsystemd-boot')"
  count="$(grep -c 'protocol: efi_chainload' <<< "$result")"
  [ "$count" -eq 2 ]
}
```

- [ ] **Step 2: Run to verify failure**

Run: `bats tests/bats/migrate.bats`
Expected: FAIL — `build_limine_conf` not defined.

- [ ] **Step 3: Add `build_limine_conf` to `lib/migrate.sh`** (replacing the Task 8 stub file contents, keeping `cmd_migrate` further down)

```bash
#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later

build_limine_conf() {
    local other_os_list="${1-}"
    local -a lines=(
        "timeout: 5"
        "default_entry: 1"
        ""
        "/XeroLinux"
        "    protocol: linux"
        "    path: boot():/vmlinuz-linux"
        "    cmdline: quiet nowatchdog loglevel=3"
        "    module_path: boot():/initramfs-linux.img"
    )
    if [[ -n "$other_os_list" ]]; then
        local os_label
        while IFS= read -r os_label; do
            [[ -z "$os_label" ]] && continue
            lines+=("" "/$os_label" "    protocol: efi_chainload" "    path: boot():/EFI/Boot/bootx64.efi")
        done <<< "$other_os_list"
    fi
    printf '%s\n' "${lines[@]}"
}

cmd_migrate() {
    emit_event "error" "error" "migrate not yet implemented"
    return 1
}
```

- [ ] **Step 4: Run to verify pass**

Run: `bats tests/bats/migrate.bats`
Expected: PASS (3 tests).

- [ ] **Step 5: Commit**

```bash
git add lib/migrate.sh tests/bats/migrate.bats
git commit -m "feat: generate limine.conf content with chainload entries"
```

---

### Task 10: `lib/migrate.sh` — package install, EFI registration, verification, GRUB removal

**Files:**
- Modify: `lib/migrate.sh`
- Modify: `tests/bats/migrate.bats`

**Interfaces:**
- Consumes: `run_cmd`, `emit_event` (Task 2).
- Produces: `install_limine_packages()`, `register_efi_boot_entry(esp_disk, esp_part_num)`, `verify_limine_entry(efibootmgr_output="")`, `remove_grub()`.

- [ ] **Step 1: Write the failing tests**

Append to `tests/bats/migrate.bats`:
```bash
@test "install_limine_packages runs pacman with the right package list" {
  DRY_RUN=1
  result="$(install_limine_packages)"
  [[ "$result" == *"pacman -S --noconfirm --needed limine limine-mkinitcpio-hook"* ]]
}

@test "register_efi_boot_entry builds the correct efibootmgr invocation" {
  DRY_RUN=1
  result="$(register_efi_boot_entry "/dev/vda" "1")"
  [[ "$result" == *"efibootmgr --create --disk /dev/vda --part 1 --label XeroLinux --loader"* ]]
}

@test "verify_limine_entry true when XeroLinux is present" {
  run verify_limine_entry "Boot0000* XeroLinux"
  [ "$status" -eq 0 ]
}

@test "verify_limine_entry false when XeroLinux is absent" {
  run verify_limine_entry "Boot0000* Windows Boot Manager"
  [ "$status" -eq 1 ]
}

@test "remove_grub previews the expected commands under DRY_RUN" {
  DRY_RUN=1
  result="$(remove_grub)"
  [[ "$result" == *"pacman -Rns --noconfirm grub grub-hooks update-grub os-prober"* ]]
  [[ "$result" == *"rm -rf /boot/grub"* ]]
  [[ "$result" == *"rm -f /etc/default/grub"* ]]
}
```

- [ ] **Step 2: Run to verify failure**

Run: `bats tests/bats/migrate.bats`
Expected: FAIL — new functions not defined.

- [ ] **Step 3: Add the functions to `lib/migrate.sh`** (insert above `cmd_migrate`)

```bash
install_limine_packages() {
    run_cmd pacman -S --noconfirm --needed limine limine-mkinitcpio-hook
}

register_efi_boot_entry() {
    local esp_disk="$1" esp_part_num="$2"
    run_cmd efibootmgr --create --disk "$esp_disk" --part "$esp_part_num" \
        --label "XeroLinux" --loader '\EFI\XeroLinux\BOOTX64.EFI'
}

verify_limine_entry() {
    local efibootmgr_output="${1-$(efibootmgr -v 2>/dev/null)}"
    grep -qi 'XeroLinux' <<< "$efibootmgr_output"
}

remove_grub() {
    run_cmd pacman -Rns --noconfirm grub grub-hooks update-grub os-prober
    run_cmd rm -rf /boot/grub
    run_cmd rm -f /etc/default/grub
}
```

- [ ] **Step 4: Run to verify pass**

Run: `bats tests/bats/migrate.bats`
Expected: PASS (8 tests).

- [ ] **Step 5: Commit**

```bash
git add lib/migrate.sh tests/bats/migrate.bats
git commit -m "feat: add Limine package install, EFI registration, verification, GRUB removal"
```

---

### Task 11: `lib/migrate.sh` — `write_limine_conf` + `cmd_migrate` orchestrator (safety ordering)

**Files:**
- Modify: `lib/migrate.sh`
- Modify: `tests/bats/migrate.bats`

**Interfaces:**
- Consumes: `build_limine_conf`, `install_limine_packages`, `register_efi_boot_entry`, `verify_limine_entry`, `remove_grub` (Tasks 9-10); `find_esp_mountpoint`, `detect_other_os` (Tasks 3, 5).
- Produces: `write_limine_conf(path="/boot/limine.conf", other_os_list="")`, `cmd_migrate()`.

- [ ] **Step 1: Write the failing tests**

Append to `tests/bats/migrate.bats`:
```bash
@test "write_limine_conf writes build_limine_conf output to the given path" {
  target="$BATS_TEST_TMPDIR/limine.conf"
  write_limine_conf "$target" ""
  grep -q "/XeroLinux" "$target"
}

@test "cmd_migrate removes GRUB after a successful verify" {
  find_esp_mountpoint() { echo "/boot/efi"; return 0; }
  detect_other_os() { echo ""; }
  write_limine_conf() { :; }
  install_limine_packages() { emit_event "would_run" "info" "install limine"; }
  register_efi_boot_entry() { emit_event "would_run" "info" "efibootmgr create"; }
  verify_limine_entry() { return 0; }
  remove_grub() { emit_event "would_run" "info" "pacman -Rns grub"; }
  DRY_RUN=1
  run cmd_migrate
  [ "$status" -eq 0 ]
  [[ "$output" == *"pacman -Rns grub"* ]]
  [[ "$output" == *"migrate_done"* ]]
}

@test "cmd_migrate does NOT remove GRUB when verify fails" {
  find_esp_mountpoint() { echo "/boot/efi"; return 0; }
  detect_other_os() { echo ""; }
  write_limine_conf() { :; }
  install_limine_packages() { emit_event "would_run" "info" "install limine"; }
  register_efi_boot_entry() { emit_event "would_run" "info" "efibootmgr create"; }
  verify_limine_entry() { return 1; }
  remove_grub() { emit_event "would_run" "info" "pacman -Rns grub"; }
  DRY_RUN=1
  run cmd_migrate
  [ "$status" -ne 0 ]
  [[ "$output" != *"pacman -Rns grub"* ]]
  [[ "$output" == *'"event":"error"'* ]]
}
```

- [ ] **Step 2: Run to verify failure**

Run: `bats tests/bats/migrate.bats`
Expected: FAIL — `write_limine_conf` and real `cmd_migrate` orchestration not present yet.

- [ ] **Step 3: Add `write_limine_conf`, replace `cmd_migrate` in `lib/migrate.sh`**

```bash
write_limine_conf() {
    local path="${1-/boot/limine.conf}" other_os_list="${2-}"
    build_limine_conf "$other_os_list" > "$path"
}

cmd_migrate() {
    local esp_mountpoint
    esp_mountpoint="$(find_esp_mountpoint)" || {
        emit_event "error" "error" "No EFI system partition found. Aborting before any changes."
        return 1
    }

    emit_event "migrate_step" "info" "Installing Limine and limine-mkinitcpio-hook"
    install_limine_packages

    emit_event "migrate_step" "info" "Writing /boot/limine.conf"
    local other_os
    other_os="$(detect_other_os)"
    write_limine_conf "/boot/limine.conf" "$other_os"

    emit_event "migrate_step" "info" "Registering Limine EFI boot entry"
    local esp_disk="/dev/vda"
    register_efi_boot_entry "$esp_disk" "1"

    emit_event "migrate_step" "info" "Regenerating initramfs"
    run_cmd mkinitcpio -P

    emit_event "migrate_step" "info" "Verifying Limine EFI boot entry"
    if ! verify_limine_entry; then
        emit_event "error" "error" "Limine's EFI boot entry could not be verified. GRUB has NOT been removed; your system is still bootable via GRUB."
        return 1
    fi

    emit_event "migrate_step" "info" "Removing GRUB"
    remove_grub

    emit_event "migrate_done" "info" "Migration to Limine complete."
}
```

Note: `esp_disk`/`esp_part_num` derivation from the real mounted ESP device (via `findmnt`/`lsblk`, same technique as `detect_partition_table`) is a known simplification here — the literal `/dev/vda`/`"1"` above is a placeholder for the orchestrator wiring exercised by this task's mocked tests. Before this is used against a real system, replace it with:
```bash
    local esp_source parent_disk esp_part_num
    esp_source="$(findmnt -no SOURCE /boot/efi 2>/dev/null)"
    parent_disk="$(lsblk -no PKNAME "$esp_source" 2>/dev/null)"
    esp_part_num="$(lsblk -no PARTN "$esp_source" 2>/dev/null)"
    register_efi_boot_entry "/dev/$parent_disk" "$esp_part_num"
```
Add this as a follow-up task before real-hardware testing (tracked, not deferred silently): **Task 11a** below.

- [ ] **Step 4: Run to verify pass**

Run: `bats tests/bats/migrate.bats`
Expected: PASS (11 tests).

- [ ] **Step 5: Commit**

```bash
git add lib/migrate.sh tests/bats/migrate.bats
git commit -m "feat: wire cmd_migrate with GRUB-removed-only-after-verify ordering"
```

---

### Task 11a: `lib/migrate.sh` — derive real ESP disk/partition instead of the Task 11 placeholder

**Files:**
- Modify: `lib/migrate.sh`
- Modify: `tests/bats/migrate.bats`

**Interfaces:**
- Produces: `resolve_esp_disk_and_part(esp_source="") -> prints "disk part_num"` (two space-separated fields).

- [ ] **Step 1: Write the failing test**

Append to `tests/bats/migrate.bats`:
```bash
@test "resolve_esp_disk_and_part splits disk and partition number" {
  lsblk() {
    if [[ "$*" == *"PKNAME"* ]]; then echo "vda"; else echo "1"; fi
  }
  result="$(resolve_esp_disk_and_part "/dev/vda1")"
  [ "$result" = "/dev/vda 1" ]
}
```

- [ ] **Step 2: Run to verify failure**

Run: `bats tests/bats/migrate.bats`
Expected: FAIL — function not defined.

- [ ] **Step 3: Add the function and use it in `cmd_migrate`**

```bash
resolve_esp_disk_and_part() {
    local esp_source="${1-$(findmnt -no SOURCE /boot/efi 2>/dev/null)}"
    local parent_disk part_num
    parent_disk="$(lsblk -no PKNAME "$esp_source" 2>/dev/null)"
    part_num="$(lsblk -no PARTN "$esp_source" 2>/dev/null)"
    printf '/dev/%s %s' "$parent_disk" "$part_num"
}
```

Replace the placeholder lines in `cmd_migrate`:
```bash
    emit_event "migrate_step" "info" "Registering Limine EFI boot entry"
    local esp_disk esp_part_num
    read -r esp_disk esp_part_num <<< "$(resolve_esp_disk_and_part)"
    register_efi_boot_entry "$esp_disk" "$esp_part_num"
```

- [ ] **Step 4: Run to verify pass**

Run: `bats tests/bats/migrate.bats`
Expected: PASS (12 tests). Also re-run the whole suite to confirm no regressions: `bats tests/bats/`.

- [ ] **Step 5: Commit**

```bash
git add lib/migrate.sh tests/bats/migrate.bats
git commit -m "fix: resolve real ESP disk/partition instead of hardcoded placeholder"
```

---

### Task 12: `lib/secureboot.sh` — key enrollment, signing, `cmd_enable_secureboot`

**Files:**
- Modify: `lib/secureboot.sh`
- Modify: `tests/bats/secureboot.bats`

**Interfaces:**
- Consumes: `run_cmd`, `emit_event` (Task 2), `detect_secureboot_state` (Task 6), `find_esp_mountpoint` (Task 3).
- Produces: `in_setup_mode(sbctl_status_output="")`, `keys_enrolled(sbctl_status_output="")`, `choose_enroll_cmd(board_vendor="", db_default_exists="0")`, `sign_efi_and_kernels(esp_dir)`, `cmd_enable_secureboot()`.

- [ ] **Step 1: Write the failing tests**

Append to `tests/bats/secureboot.bats`:
```bash
@test "in_setup_mode true when Setup Mode is Enabled" {
  run in_setup_mode "Setup Mode: Enabled"
  [ "$status" -eq 0 ]
}

@test "in_setup_mode false otherwise" {
  run in_setup_mode "Setup Mode: Disabled"
  [ "$status" -eq 1 ]
}

@test "keys_enrolled true when Setup Mode is Disabled" {
  run keys_enrolled "Setup Mode: Disabled"
  [ "$status" -eq 0 ]
}

@test "choose_enroll_cmd avoids --firmware-builtin on ASUS boards" {
  result="$(choose_enroll_cmd "ASUSTeK COMPUTER INC." "1")"
  [ "$result" = "sbctl enroll-keys --microsoft" ]
}

@test "choose_enroll_cmd avoids --firmware-builtin when dbDefault is missing" {
  result="$(choose_enroll_cmd "Dell Inc." "0")"
  [ "$result" = "sbctl enroll-keys --microsoft" ]
}

@test "choose_enroll_cmd uses --firmware-builtin otherwise" {
  result="$(choose_enroll_cmd "Dell Inc." "1")"
  [ "$result" = "sbctl enroll-keys --microsoft --firmware-builtin" ]
}

@test "sign_efi_and_kernels signs efi files and kernels under DRY_RUN" {
  esp="$BATS_TEST_TMPDIR/efi"
  mkdir -p "$esp/EFI/XeroLinux"
  touch "$esp/EFI/XeroLinux/BOOTX64.EFI"
  DRY_RUN=1
  result="$(sign_efi_and_kernels "$esp")"
  [[ "$result" == *"sbctl sign -s $esp/EFI/XeroLinux/BOOTX64.EFI"* ]]
}

@test "cmd_enable_secureboot refuses when not in setup mode and keys not enrolled" {
  detect_secureboot_state() { echo "disabled"; }
  run cmd_enable_secureboot
  [ "$status" -ne 0 ]
  [[ "$output" == *"Setup Mode"* ]]
}

@test "cmd_enable_secureboot signs and finishes when already enrolled" {
  detect_secureboot_state() { echo "setup_mode"; }
  in_setup_mode() { return 0; }
  choose_enroll_cmd() { echo "sbctl enroll-keys --microsoft"; }
  find_esp_mountpoint() { echo "/boot/efi"; }
  sign_efi_and_kernels() { emit_event "would_run" "info" "sbctl sign-all"; }
  DRY_RUN=1
  run cmd_enable_secureboot
  [ "$status" -eq 0 ]
  [[ "$output" == *"secureboot_done"* ]]
}
```

- [ ] **Step 2: Run to verify failure**

Run: `bats tests/bats/secureboot.bats`
Expected: FAIL — new functions not defined.

- [ ] **Step 3: Replace the Task 8 stub in `lib/secureboot.sh` with the full implementation**

```bash
#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later

detect_secureboot_state() {
    local sbctl_status_output="${1-$(sbctl status 2>/dev/null)}"
    if [[ -z "$sbctl_status_output" ]]; then
        printf 'unsupported'
    elif grep -qE 'Secure Boot:[[:space:]]*Enabled' <<< "$sbctl_status_output"; then
        printf 'enabled'
    elif grep -qE 'Setup Mode:[[:space:]]*Enabled' <<< "$sbctl_status_output"; then
        printf 'setup_mode'
    else
        printf 'disabled'
    fi
}

in_setup_mode() {
    local sbctl_status_output="${1-$(sbctl status 2>/dev/null)}"
    grep -q "Setup Mode:.*Enabled" <<< "$sbctl_status_output"
}

keys_enrolled() {
    local sbctl_status_output="${1-$(sbctl status 2>/dev/null)}"
    grep -q "Setup Mode:.*Disabled" <<< "$sbctl_status_output"
}

choose_enroll_cmd() {
    local board_vendor="${1-$(cat /sys/class/dmi/id/board_vendor 2>/dev/null)}"
    local db_default_exists="${2-0}"
    if [[ "$board_vendor" == *ASUS* ]]; then
        printf 'sbctl enroll-keys --microsoft'
    elif [[ "$db_default_exists" != "1" ]]; then
        printf 'sbctl enroll-keys --microsoft'
    else
        printf 'sbctl enroll-keys --microsoft --firmware-builtin'
    fi
}

sign_efi_and_kernels() {
    local esp_dir="$1"
    local efi_file kernel_file
    while IFS= read -r efi_file; do
        [[ -z "$efi_file" ]] && continue
        run_cmd sbctl sign -s "$efi_file"
    done < <(find "$esp_dir" -name '*.efi' -o -iname '*.EFI' 2>/dev/null)
    for kernel_file in /boot/vmlinuz-*; do
        [[ -f "$kernel_file" ]] || continue
        run_cmd sbctl sign -s "$kernel_file"
    done
}

cmd_enable_secureboot() {
    local state
    state="$(detect_secureboot_state)"

    if [[ "$state" == "enabled" ]]; then
        emit_event "secureboot_step" "info" "Secure Boot already active. Re-signing EFI binaries."
        local esp_dir
        esp_dir="$(find_esp_mountpoint)" || esp_dir="/boot/efi"
        sign_efi_and_kernels "$esp_dir"
        emit_event "secureboot_done" "info" "Secure Boot re-signing complete."
        return 0
    fi

    if keys_enrolled; then
        emit_event "secureboot_step" "info" "Keys already enrolled. Re-signing EFI binaries."
        local esp_dir
        esp_dir="$(find_esp_mountpoint)" || esp_dir="/boot/efi"
        sign_efi_and_kernels "$esp_dir"
        emit_event "secureboot_done" "info" "Reboot into firmware setup and enable Secure Boot."
        return 0
    fi

    if ! in_setup_mode; then
        emit_event "error" "error" "Setup Mode is not active. Reboot into UEFI firmware settings and clear all Secure Boot keys (PK, KEK, db, dbx) before running this again."
        return 1
    fi

    emit_event "secureboot_step" "info" "Creating Secure Boot keys"
    run_cmd sbctl create-keys

    local board_vendor db_default enroll_cmd
    board_vendor="$(cat /sys/class/dmi/id/board_vendor 2>/dev/null)"
    if [[ -f "/sys/firmware/efi/efivars/dbDefault-8be4df61-93ca-11d2-aa0d-00e098032b8c" ]]; then
        db_default="1"
    else
        db_default="0"
    fi
    enroll_cmd="$(choose_enroll_cmd "$board_vendor" "$db_default")"
    emit_event "secureboot_step" "info" "Enrolling keys: $enroll_cmd"
    run_cmd $enroll_cmd

    local esp_dir
    esp_dir="$(find_esp_mountpoint)" || esp_dir="/boot/efi"
    emit_event "secureboot_step" "info" "Signing EFI binaries and kernels"
    sign_efi_and_kernels "$esp_dir"

    emit_event "secureboot_done" "info" "Secure Boot setup complete. Reboot into firmware settings and enable Secure Boot."
}
```

- [ ] **Step 4: Run to verify pass**

Run: `bats tests/bats/secureboot.bats`
Expected: PASS (13 tests).

- [ ] **Step 5: Commit**

```bash
git add lib/secureboot.sh tests/bats/secureboot.bats
git commit -m "feat: port Secure Boot key enrollment and signing flow to Limine"
```

---

### Task 13: `xsb-helper` — full DRY_RUN integration coverage for migrate + enable-secureboot

**Files:**
- Modify: `tests/bats/xsb-helper.bats`

**Interfaces:**
- Consumes: `cmd_migrate` (Task 11), `cmd_enable_secureboot` (Task 12).

- [ ] **Step 1: Write the failing tests**

Append to `tests/bats/xsb-helper.bats`:
```bash
@test "xsb-helper migrate --dry-run previews without mutating anything" {
  run "${BATS_TEST_DIRNAME}/../../xsb-helper" migrate --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *"migrate_done"* ]]
  [[ "$output" != *'"event":"running"'* ]]
}

@test "xsb-helper enable-secureboot --dry-run previews without mutating anything" {
  run "${BATS_TEST_DIRNAME}/../../xsb-helper" enable-secureboot --dry-run
  [ "$status" -ne 0 ]
  [[ "$output" == *"Setup Mode"* ]]
}
```

- [ ] **Step 2: Run to verify failure**

Run: `bats tests/bats/xsb-helper.bats`
Expected: FAIL — the stub `sbctl`/`efibootmgr`/etc. in `setup()` don't yet produce output matching a real Setup-Mode-disabled machine, and `cmd_migrate`/`cmd_enable_secureboot` weren't exercised via the entrypoint before. Confirm the actual failure output before proceeding (per systematic-debugging: read the real error, don't guess).

- [ ] **Step 3: Fix the stub commands used by `setup()` so the scenario is realistic**

The existing `setup()` stubs already return `"Setup Mode: Disabled"` from `sbctl`, so `enable-secureboot --dry-run` correctly refuses (not in Setup Mode) — this is the expected real-world default state, not a bug to fix in `xsb-helper` itself. No production code changes are needed for this task; add a `grub-install`/`mkinitcpio` no-op stub only if `cmd_migrate`'s `run_cmd mkinitcpio -P` line causes the test to hang or error under `--dry-run` (it should not, since `DRY_RUN=1` makes `run_cmd` skip execution entirely) — verify this is the case rather than assuming.

- [ ] **Step 4: Run to verify pass**

Run: `bats tests/bats/xsb-helper.bats`
Expected: PASS (4 tests). Then run the full Bash suite: `bats tests/bats/` — expect all tests across all files passing.

- [ ] **Step 5: Commit**

```bash
git add tests/bats/xsb-helper.bats
git commit -m "test: cover migrate and enable-secureboot through the xsb-helper entrypoint"
```

---

### Task 14: Python project scaffold + `xsb_gui/parsing.py`

**Files:**
- Create: `xsb_gui/__init__.py`
- Create: `xsb_gui/parsing.py`
- Test: `tests/python/test_parsing.py`

**Interfaces:**
- Produces: `PreflightResult` dataclass (`uefi: bool, gpt: bool, esp_mountpoint: str, bootloader: str, luks: bool, mkinitcpio_hook: str, other_os: list[str], secureboot_state: str`), `parse_preflight_result(event: dict) -> PreflightResult`, `build_summary_text(result: PreflightResult) -> str`, `format_event_line(event: dict) -> str`.

- [ ] **Step 1: Set up the Python test environment**

Run: `python3 -m venv .venv && source .venv/bin/activate && pip install pytest pytest-qt PyQt6`

- [ ] **Step 2: Write the failing test**

`tests/python/test_parsing.py`:
```python
from xsb_gui.parsing import parse_preflight_result, build_summary_text, format_event_line, PreflightResult


def test_parse_preflight_result_reads_all_fields():
    event = {
        "event": "preflight_result",
        "level": "info",
        "data": {
            "uefi": True,
            "gpt": True,
            "esp_mountpoint": "/boot/efi",
            "bootloader": "grub",
            "luks": False,
            "mkinitcpio_hook": "none",
            "other_os": ["Windows Boot Manager"],
            "secureboot_state": "disabled",
        },
    }
    result = parse_preflight_result(event)
    assert result == PreflightResult(
        uefi=True, gpt=True, esp_mountpoint="/boot/efi", bootloader="grub",
        luks=False, mkinitcpio_hook="none", other_os=["Windows Boot Manager"],
        secureboot_state="disabled",
    )


def test_build_summary_text_lists_detected_other_os():
    result = PreflightResult(
        uefi=True, gpt=True, esp_mountpoint="/boot/efi", bootloader="grub",
        luks=True, mkinitcpio_hook="sd-encrypt", other_os=["Windows Boot Manager"],
        secureboot_state="setup_mode",
    )
    text = build_summary_text(result)
    assert "Windows Boot Manager" in text
    assert "Encrypted root (LUKS): yes" in text
    assert "grub" in text


def test_build_summary_text_omits_other_os_line_when_none_found():
    result = PreflightResult(
        uefi=True, gpt=True, esp_mountpoint="/boot/efi", bootloader="grub",
        luks=False, mkinitcpio_hook="none", other_os=[], secureboot_state="disabled",
    )
    text = build_summary_text(result)
    assert "chainload" not in text


def test_format_event_line_uppercases_level():
    line = format_event_line({"event": "migrate_step", "level": "info", "message": "Installing Limine"})
    assert line == "[INFO] Installing Limine"
```

- [ ] **Step 3: Run to verify failure**

Run: `pytest tests/python/test_parsing.py -v`
Expected: FAIL — `ModuleNotFoundError: No module named 'xsb_gui'`.

- [ ] **Step 4: Write `xsb_gui/__init__.py` (empty) and `xsb_gui/parsing.py`**

`xsb_gui/__init__.py`: empty file.

`xsb_gui/parsing.py`:
```python
from dataclasses import dataclass


@dataclass
class PreflightResult:
    uefi: bool
    gpt: bool
    esp_mountpoint: str
    bootloader: str
    luks: bool
    mkinitcpio_hook: str
    other_os: list
    secureboot_state: str


def parse_preflight_result(event: dict) -> PreflightResult:
    data = event["data"]
    return PreflightResult(
        uefi=data["uefi"],
        gpt=data["gpt"],
        esp_mountpoint=data["esp_mountpoint"],
        bootloader=data["bootloader"],
        luks=data["luks"],
        mkinitcpio_hook=data["mkinitcpio_hook"],
        other_os=list(data["other_os"]),
        secureboot_state=data["secureboot_state"],
    )


def build_summary_text(result: PreflightResult) -> str:
    lines = [
        f"EFI system partition: {result.esp_mountpoint}",
        f"Current bootloader: {result.bootloader}",
        f"Encrypted root (LUKS): {'yes' if result.luks else 'no'}",
    ]
    if result.other_os:
        lines.append("Other OS detected, chainload entries will be added: " + ", ".join(result.other_os))
    lines.append(f"Secure Boot firmware state: {result.secureboot_state}")
    return "\n".join(lines)


def format_event_line(event: dict) -> str:
    level = event.get("level", "info").upper()
    message = event.get("message", "")
    return f"[{level}] {message}"
```

- [ ] **Step 5: Run to verify pass**

Run: `pytest tests/python/test_parsing.py -v`
Expected: PASS (4 tests).

- [ ] **Step 6: Commit**

```bash
git add xsb_gui/__init__.py xsb_gui/parsing.py tests/python/test_parsing.py
git commit -m "feat: add pure-Python event parsing and summary formatting"
```

---

### Task 15: `xsb_gui/helper_runner.py` — QProcess wrapper around `xsb-helper`

**Files:**
- Create: `xsb_gui/helper_runner.py`
- Test: `tests/python/test_helper_runner.py`
- Create (test fixture): `tests/python/fixtures/fake_helper.sh`

**Interfaces:**
- Consumes: nothing new.
- Produces: `HelperRunner(helper_path="/usr/lib/xsb-gui/xsb-helper", use_pkexec=True)` with `.start(*args)`, signals `event_received(dict)`, `finished(int)`.

- [ ] **Step 1: Write the fake helper fixture**

`tests/python/fixtures/fake_helper.sh`:
```bash
#!/usr/bin/env bash
echo '{"event":"preflight_step","level":"info","message":"checking"}'
echo '{"event":"preflight_result","level":"info","data":{"uefi":true,"gpt":true,"esp_mountpoint":"/boot/efi","bootloader":"grub","luks":false,"mkinitcpio_hook":"none","other_os":[],"secureboot_state":"disabled"}}'
exit 0
```

Run: `chmod +x tests/python/fixtures/fake_helper.sh`

- [ ] **Step 2: Write the failing test**

`tests/python/test_helper_runner.py`:
```python
import os
from xsb_gui.helper_runner import HelperRunner

FIXTURE = os.path.join(os.path.dirname(__file__), "fixtures", "fake_helper.sh")


def test_helper_runner_emits_parsed_events_and_finishes(qtbot):
    runner = HelperRunner(helper_path=FIXTURE, use_pkexec=False)
    events = []
    runner.event_received.connect(events.append)

    with qtbot.waitSignal(runner.finished, timeout=2000) as blocker:
        runner.start("preflight")

    assert blocker.args == [0]
    assert [e["event"] for e in events] == ["preflight_step", "preflight_result"]
    assert events[1]["data"]["bootloader"] == "grub"


def test_helper_runner_uses_pkexec_when_enabled():
    runner = HelperRunner(helper_path="/usr/lib/xsb-gui/xsb-helper", use_pkexec=True)
    program, args = runner._build_command(("migrate",))
    assert program == "pkexec"
    assert args == ["/usr/lib/xsb-gui/xsb-helper", "migrate"]
```

- [ ] **Step 3: Run to verify failure**

Run: `pytest tests/python/test_helper_runner.py -v`
Expected: FAIL — `ModuleNotFoundError: No module named 'xsb_gui.helper_runner'`.

- [ ] **Step 4: Write `xsb_gui/helper_runner.py`**

```python
import json

from PyQt6.QtCore import QObject, QProcess, pyqtSignal


class HelperRunner(QObject):
    event_received = pyqtSignal(dict)
    finished = pyqtSignal(int)

    def __init__(self, helper_path="/usr/lib/xsb-gui/xsb-helper", use_pkexec=True, parent=None):
        super().__init__(parent)
        self._helper_path = helper_path
        self._use_pkexec = use_pkexec
        self._buffer = ""
        self._process = QProcess(self)
        self._process.readyReadStandardOutput.connect(self._on_ready_read)
        self._process.finished.connect(self._on_finished)

    def start(self, *args):
        program, prog_args = self._build_command(args)
        self._process.start(program, prog_args)

    def _build_command(self, args):
        if self._use_pkexec:
            return "pkexec", [self._helper_path, *args]
        return self._helper_path, list(args)

    def _on_ready_read(self):
        data = bytes(self._process.readAllStandardOutput()).decode("utf-8", "replace")
        self._buffer += data
        while "\n" in self._buffer:
            line, self._buffer = self._buffer.split("\n", 1)
            line = line.strip()
            if not line:
                continue
            try:
                event = json.loads(line)
            except json.JSONDecodeError:
                continue
            self.event_received.emit(event)

    def _on_finished(self, exit_code, _exit_status):
        self.finished.emit(exit_code)
```

- [ ] **Step 5: Run to verify pass**

Run: `QT_QPA_PLATFORM=offscreen pytest tests/python/test_helper_runner.py -v`
Expected: PASS (2 tests).

- [ ] **Step 6: Commit**

```bash
git add xsb_gui/helper_runner.py tests/python/test_helper_runner.py tests/python/fixtures/fake_helper.sh
git commit -m "feat: add QProcess-based helper runner with JSON-lines parsing"
```

---

### Task 16: `xsb_gui/pages/welcome_page.py`

**Files:**
- Create: `xsb_gui/pages/__init__.py`
- Create: `xsb_gui/pages/welcome_page.py`
- Test: `tests/python/test_welcome_page.py`

**Interfaces:**
- Produces: `WelcomePage` (`QWizardPage` subclass) with an "I understand" `QCheckBox`; `isComplete()` returns the checkbox's checked state.

- [ ] **Step 1: Write the failing test**

`tests/python/test_welcome_page.py`:
```python
from PyQt6.QtCore import Qt

from xsb_gui.pages.welcome_page import WelcomePage


def test_welcome_page_blocks_next_until_checkbox_is_checked(qtbot):
    page = WelcomePage()
    qtbot.addWidget(page)
    page.show()
    qtbot.waitExposed(page)
    assert page.isComplete() is False

    qtbot.mouseClick(page.understand_checkbox, Qt.MouseButton.LeftButton)

    assert page.isComplete() is True
```

(A widget must actually be shown and exposed before `qtbot.mouseClick` will deliver
synthetic input events to it — verified empirically in this environment with
PyQt6 6.11.0 + pytest-qt 4.5.0; without `.show()`/`waitExposed`, the click is a
no-op and `isChecked()` never flips. This applies to any future test that
simulates mouse/keyboard input on a widget, not just this one.)

- [ ] **Step 2: Run to verify failure**

Run: `QT_QPA_PLATFORM=offscreen pytest tests/python/test_welcome_page.py -v`
Expected: FAIL — module not found.

- [ ] **Step 3: Write `xsb_gui/pages/__init__.py` (empty) and `xsb_gui/pages/welcome_page.py`**

```python
from PyQt6.QtWidgets import QCheckBox, QLabel, QSizePolicy, QVBoxLayout, QWizardPage

WARNING_TEXT = (
    "This will permanently remove GRUB and related packages (grub, grub-hooks, "
    "update-grub, os-prober) and their files from this system, install Limine and "
    "limine-mkinitcpio-hook, and set Limine up as the bootloader. If your firmware's "
    "Secure Boot Setup Mode is active, Secure Boot keys will also be created and "
    "enrolled. This cannot be undone without manual recovery."
)


class WelcomePage(QWizardPage):
    def __init__(self, parent=None):
        super().__init__(parent)
        self.setTitle("XeroLinux Limine/SecureBoot Enabler")
        layout = QVBoxLayout(self)
        label = QLabel(WARNING_TEXT)
        label.setWordWrap(True)
        layout.addWidget(label)
        self.understand_checkbox = QCheckBox("I understand, and want to proceed")
        self.understand_checkbox.setSizePolicy(QSizePolicy.Policy.Fixed, QSizePolicy.Policy.Fixed)
        self.understand_checkbox.toggled.connect(self.completeChanged)
        layout.addWidget(self.understand_checkbox)

    def isComplete(self):
        return self.understand_checkbox.isChecked()
```

(`setWordWrap(True)` and the checkbox's `setSizePolicy(Fixed, Fixed)` were added after
discovering, via isolated single-variable scripts, that an unwrapped long-text `QLabel`
stretches the whole page width, which in turn stretches the checkbox's widget bounding
box far beyond its actual clickable region (`SE_CheckBoxClickRect` stays left-aligned).
`qtbot.mouseClick`'s default click point is the widget's bounding-box center, which then
lands in dead space and never registers. Fixing the checkbox's size policy keeps its
clickable region matched to its bounding box regardless of layout stretching.)

- [ ] **Step 4: Run to verify pass**

Run: `QT_QPA_PLATFORM=offscreen pytest tests/python/test_welcome_page.py -v`
Expected: PASS (1 test).

- [ ] **Step 5: Commit**

```bash
git add xsb_gui/pages/__init__.py xsb_gui/pages/welcome_page.py tests/python/test_welcome_page.py
git commit -m "feat: add welcome/warning wizard page"
```

---

### Task 17: `xsb_gui/pages/preflight_page.py`

**Files:**
- Create: `xsb_gui/pages/preflight_page.py`
- Test: `tests/python/test_preflight_page.py`

**Interfaces:**
- Consumes: `HelperRunner` (Task 15), `parse_preflight_result` (Task 14).
- Produces: `PreflightPage` with `initializePage()` starting `HelperRunner("preflight")`, `isComplete()` gated on a successful `preflight_result`, `result` attribute holding the parsed `PreflightResult` once available.

- [ ] **Step 1: Write the failing test**

`tests/python/test_preflight_page.py`:
```python
import os
from xsb_gui.pages.preflight_page import PreflightPage

FIXTURE = os.path.join(os.path.dirname(__file__), "fixtures", "fake_helper.sh")


def test_preflight_page_becomes_complete_after_preflight_result(qtbot):
    page = PreflightPage(helper_path=FIXTURE, use_pkexec=False)
    qtbot.addWidget(page)
    assert page.isComplete() is False

    page.initializePage()

    with qtbot.waitSignal(page.runner.finished, timeout=2000):
        pass

    assert page.isComplete() is True
    assert page.result.bootloader == "grub"
```

- [ ] **Step 2: Run to verify failure**

Run: `QT_QPA_PLATFORM=offscreen pytest tests/python/test_preflight_page.py -v`
Expected: FAIL — module not found.

- [ ] **Step 3: Write `xsb_gui/pages/preflight_page.py`**

```python
from PyQt6.QtWidgets import QLabel, QVBoxLayout, QWizardPage

from xsb_gui.helper_runner import HelperRunner
from xsb_gui.parsing import parse_preflight_result


class PreflightPage(QWizardPage):
    def __init__(self, helper_path="/usr/lib/xsb-gui/xsb-helper", use_pkexec=True, parent=None):
        super().__init__(parent)
        self.setTitle("Checking your system")
        self._status_label = QLabel("Running checks...")
        layout = QVBoxLayout(self)
        layout.addWidget(self._status_label)

        self.result = None
        self._helper_path = helper_path
        self._use_pkexec = use_pkexec
        self.runner = None

    def initializePage(self):
        self.result = None
        self.runner = HelperRunner(helper_path=self._helper_path, use_pkexec=self._use_pkexec)
        self.runner.event_received.connect(self._on_event)
        self.runner.finished.connect(self._on_finished)
        self.runner.start("preflight")

    def _on_event(self, event):
        if event["event"] == "preflight_result":
            self.result = parse_preflight_result(event)
            self._status_label.setText("Checks complete.")
            self.completeChanged.emit()
        elif event["event"] == "error":
            self._status_label.setText(event["message"])
            self.completeChanged.emit()

    def _on_finished(self, _exit_code):
        if self.result is None and self._status_label.text() == "Running checks...":
            self._status_label.setText("Preflight checks did not complete.")
            self.completeChanged.emit()

    def isComplete(self):
        return self.result is not None
```

- [ ] **Step 4: Run to verify pass**

Run: `QT_QPA_PLATFORM=offscreen pytest tests/python/test_preflight_page.py -v`
Expected: PASS (1 test).

- [ ] **Step 5: Commit**

```bash
git add xsb_gui/pages/preflight_page.py tests/python/test_preflight_page.py
git commit -m "feat: add preflight wizard page driven by xsb-helper"
```

---

### Task 18: `xsb_gui/pages/confirm_page.py`

**Files:**
- Create: `xsb_gui/pages/confirm_page.py`
- Test: `tests/python/test_confirm_page.py`

**Interfaces:**
- Consumes: `build_summary_text`, `PreflightResult` (Task 14); reads `PreflightPage.result` from the wizard (via `self.wizard().page(PREFLIGHT_PAGE_ID)`).
- Produces: `ConfirmPage`, module constants `WELCOME_PAGE_ID = 0`, `PREFLIGHT_PAGE_ID = 1`, `CONFIRM_PAGE_ID = 2`, `MIGRATE_PAGE_ID = 3`, `SECUREBOOT_PAGE_ID = 4`, `DONE_PAGE_ID = 5` (shared page-id constants used by all remaining pages and `app.py`).

- [ ] **Step 1: Write the failing test**

`tests/python/test_confirm_page.py`:
```python
from xsb_gui.pages.confirm_page import ConfirmPage
from xsb_gui.parsing import PreflightResult


class FakePreflightPage:
    def __init__(self, result):
        self.result = result


class FakeWizard:
    def __init__(self, preflight_page):
        self._preflight_page = preflight_page

    def page(self, _page_id):
        return self._preflight_page


def test_confirm_page_shows_summary_from_preflight_result(qtbot):
    result = PreflightResult(
        uefi=True, gpt=True, esp_mountpoint="/boot/efi", bootloader="grub",
        luks=False, mkinitcpio_hook="none", other_os=["Windows Boot Manager"],
        secureboot_state="disabled",
    )
    page = ConfirmPage()
    qtbot.addWidget(page)
    page.wizard = lambda: FakeWizard(FakePreflightPage(result))

    page.initializePage()

    assert "Windows Boot Manager" in page.summary_label.text()
    assert page.isComplete() is True
```

- [ ] **Step 2: Run to verify failure**

Run: `QT_QPA_PLATFORM=offscreen pytest tests/python/test_confirm_page.py -v`
Expected: FAIL — module not found.

- [ ] **Step 3: Write `xsb_gui/pages/confirm_page.py`**

```python
from PyQt6.QtWidgets import QLabel, QVBoxLayout, QWizardPage

from xsb_gui.parsing import build_summary_text

WELCOME_PAGE_ID = 0
PREFLIGHT_PAGE_ID = 1
CONFIRM_PAGE_ID = 2
MIGRATE_PAGE_ID = 3
SECUREBOOT_PAGE_ID = 4
DONE_PAGE_ID = 5


class ConfirmPage(QWizardPage):
    def __init__(self, parent=None):
        super().__init__(parent)
        self.setTitle("Confirm migration")
        self.summary_label = QLabel("")
        self.summary_label.setWordWrap(True)
        layout = QVBoxLayout(self)
        layout.addWidget(self.summary_label)

    def initializePage(self):
        preflight_page = self.wizard().page(PREFLIGHT_PAGE_ID)
        self.summary_label.setText(build_summary_text(preflight_page.result))

    def isComplete(self):
        return True
```

- [ ] **Step 4: Run to verify pass**

Run: `QT_QPA_PLATFORM=offscreen pytest tests/python/test_confirm_page.py -v`
Expected: PASS (1 test).

- [ ] **Step 5: Commit**

```bash
git add xsb_gui/pages/confirm_page.py tests/python/test_confirm_page.py
git commit -m "feat: add confirm wizard page with system-specific summary"
```

---

### Task 19: `xsb_gui/pages/migrate_page.py` + `xsb_gui/pages/secureboot_page.py`

**Files:**
- Create: `xsb_gui/pages/migrate_page.py`
- Create: `xsb_gui/pages/secureboot_page.py`
- Test: `tests/python/test_migrate_secureboot_pages.py`
- Create (test fixture): `tests/python/fixtures/fake_helper_migrate_ok.sh`
- Create (test fixture): `tests/python/fixtures/fake_helper_migrate_fail.sh`

**Interfaces:**
- Consumes: `HelperRunner` (Task 15), `format_event_line` (Task 14).
- Produces: `MigratePage(helper_path=..., use_pkexec=...)`, `SecureBootPage(helper_path=..., use_pkexec=...)` — both log every event via `format_event_line` into a `QPlainTextEdit`, set `isComplete()` True only on their terminal success event (`migrate_done` / `secureboot_done`), stay incomplete (with the log showing the error) on an `error` event, and expose a `retry()` method that re-runs the same subcommand.

- [ ] **Step 1: Write the fixtures**

`tests/python/fixtures/fake_helper_migrate_ok.sh`:
```bash
#!/usr/bin/env bash
echo '{"event":"migrate_step","level":"info","message":"Installing Limine"}'
echo '{"event":"migrate_done","level":"info","message":"Migration to Limine complete."}'
exit 0
```

`tests/python/fixtures/fake_helper_migrate_fail.sh`:
```bash
#!/usr/bin/env bash
echo '{"event":"migrate_step","level":"info","message":"Installing Limine"}'
echo '{"event":"error","level":"error","message":"Limine EFI boot entry could not be verified."}'
exit 1
```

Run: `chmod +x tests/python/fixtures/fake_helper_migrate_ok.sh tests/python/fixtures/fake_helper_migrate_fail.sh`

- [ ] **Step 2: Write the failing test**

`tests/python/test_migrate_secureboot_pages.py`:
```python
import os
from xsb_gui.pages.migrate_page import MigratePage
from xsb_gui.pages.secureboot_page import SecureBootPage

FIXTURE_DIR = os.path.join(os.path.dirname(__file__), "fixtures")
OK = os.path.join(FIXTURE_DIR, "fake_helper_migrate_ok.sh")
FAIL = os.path.join(FIXTURE_DIR, "fake_helper_migrate_fail.sh")


def test_migrate_page_completes_on_migrate_done(qtbot):
    page = MigratePage(helper_path=OK, use_pkexec=False)
    qtbot.addWidget(page)
    page.initializePage()

    with qtbot.waitSignal(page.runner.finished, timeout=2000):
        pass

    assert page.isComplete() is True
    assert "Migration to Limine complete." in page.log.toPlainText()


def test_migrate_page_stays_incomplete_and_shows_error_on_failure(qtbot):
    page = MigratePage(helper_path=FAIL, use_pkexec=False)
    qtbot.addWidget(page)
    page.initializePage()

    with qtbot.waitSignal(page.runner.finished, timeout=2000):
        pass

    assert page.isComplete() is False
    assert "could not be verified" in page.log.toPlainText()


def test_secureboot_page_completes_on_secureboot_done(qtbot):
    page = SecureBootPage(helper_path=OK.replace("migrate", "secureboot"), use_pkexec=False)


def test_secureboot_page_uses_enable_secureboot_subcommand(qtbot):
    page = SecureBootPage(helper_path=OK, use_pkexec=False)
    qtbot.addWidget(page)
    page.initializePage()
    assert page._subcommand == "enable-secureboot"
```

(The `test_secureboot_page_completes_on_secureboot_done` stub above is intentionally replaced in Step 3 below with a real fixture-backed test — see the corrected version.)

- [ ] **Step 3: Replace the placeholder secureboot fixture/test with a real one**

Add `tests/python/fixtures/fake_helper_secureboot_ok.sh`:
```bash
#!/usr/bin/env bash
echo '{"event":"secureboot_step","level":"info","message":"Signing EFI binaries and kernels"}'
echo '{"event":"secureboot_done","level":"info","message":"Secure Boot setup complete."}'
exit 0
```
Run: `chmod +x tests/python/fixtures/fake_helper_secureboot_ok.sh`

Replace the two secureboot tests in `tests/python/test_migrate_secureboot_pages.py` with:
```python
SECUREBOOT_OK = os.path.join(FIXTURE_DIR, "fake_helper_secureboot_ok.sh")


def test_secureboot_page_completes_on_secureboot_done(qtbot):
    page = SecureBootPage(helper_path=SECUREBOOT_OK, use_pkexec=False)
    qtbot.addWidget(page)
    page.initializePage()

    with qtbot.waitSignal(page.runner.finished, timeout=2000):
        pass

    assert page.isComplete() is True


def test_secureboot_page_uses_enable_secureboot_subcommand(qtbot):
    page = SecureBootPage(helper_path=SECUREBOOT_OK, use_pkexec=False)
    qtbot.addWidget(page)
    assert page._subcommand == "enable-secureboot"
```

- [ ] **Step 4: Run to verify failure**

Run: `QT_QPA_PLATFORM=offscreen pytest tests/python/test_migrate_secureboot_pages.py -v`
Expected: FAIL — modules not found.

- [ ] **Step 5: Write `xsb_gui/pages/migrate_page.py`**

```python
from PyQt6.QtWidgets import QPlainTextEdit, QPushButton, QVBoxLayout, QWizardPage

from xsb_gui.helper_runner import HelperRunner
from xsb_gui.parsing import format_event_line


class _RunnerPage(QWizardPage):
    _subcommand = None
    _done_event = None

    def __init__(self, helper_path="/usr/lib/xsb-gui/xsb-helper", use_pkexec=True, parent=None):
        super().__init__(parent)
        self._helper_path = helper_path
        self._use_pkexec = use_pkexec
        self._complete = False
        self.log = QPlainTextEdit()
        self.log.setReadOnly(True)
        self.retry_button = QPushButton("Retry")
        self.retry_button.setVisible(False)
        self.retry_button.clicked.connect(self.retry)
        layout = QVBoxLayout(self)
        layout.addWidget(self.log)
        layout.addWidget(self.retry_button)
        self.runner = None

    def initializePage(self):
        self._complete = False
        self.retry_button.setVisible(False)
        self.log.clear()
        self.runner = HelperRunner(helper_path=self._helper_path, use_pkexec=self._use_pkexec)
        self.runner.event_received.connect(self._on_event)
        self.runner.finished.connect(self._on_finished)
        self.runner.start(self._subcommand)

    def retry(self):
        self.initializePage()

    def _on_event(self, event):
        self.log.appendPlainText(format_event_line(event))
        if event["event"] == self._done_event:
            self._complete = True
            self.completeChanged.emit()

    def _on_finished(self, exit_code):
        if exit_code != 0 and not self._complete:
            self.retry_button.setVisible(True)
        self.completeChanged.emit()

    def isComplete(self):
        return self._complete


class MigratePage(_RunnerPage):
    _subcommand = "migrate"
    _done_event = "migrate_done"

    def __init__(self, *args, **kwargs):
        super().__init__(*args, **kwargs)
        self.setTitle("Migrating to Limine")
```

- [ ] **Step 6: Write `xsb_gui/pages/secureboot_page.py`**

```python
from xsb_gui.pages.migrate_page import _RunnerPage


class SecureBootPage(_RunnerPage):
    _subcommand = "enable-secureboot"
    _done_event = "secureboot_done"

    def __init__(self, *args, **kwargs):
        super().__init__(*args, **kwargs)
        self.setTitle("Enabling Secure Boot")
```

- [ ] **Step 7: Run to verify pass**

Run: `QT_QPA_PLATFORM=offscreen pytest tests/python/test_migrate_secureboot_pages.py -v`
Expected: PASS (4 tests).

- [ ] **Step 8: Commit**

```bash
git add xsb_gui/pages/migrate_page.py xsb_gui/pages/secureboot_page.py \
        tests/python/test_migrate_secureboot_pages.py \
        tests/python/fixtures/fake_helper_migrate_ok.sh \
        tests/python/fixtures/fake_helper_migrate_fail.sh \
        tests/python/fixtures/fake_helper_secureboot_ok.sh
git commit -m "feat: add migrate and secure-boot execution wizard pages"
```

---

### Task 20: `xsb_gui/pages/done_page.py`, `xsb_gui/app.py`, `xsb-gui` entrypoint

**Files:**
- Create: `xsb_gui/pages/done_page.py`
- Create: `xsb_gui/app.py`
- Create: `xsb-gui`
- Test: `tests/python/test_app.py`

**Interfaces:**
- Consumes: `WelcomePage` (16), `PreflightPage` (17), `ConfirmPage` + page-id constants (18), `MigratePage`/`SecureBootPage` (19).
- Produces: `build_wizard() -> QWizard`, `main()`.

- [ ] **Step 1: Write the failing test**

`tests/python/test_app.py`:
```python
from PyQt6.QtWidgets import QApplication

from xsb_gui.app import build_wizard
from xsb_gui.pages.confirm_page import (
    WELCOME_PAGE_ID, PREFLIGHT_PAGE_ID, CONFIRM_PAGE_ID, MIGRATE_PAGE_ID,
    SECUREBOOT_PAGE_ID, DONE_PAGE_ID,
)


def test_build_wizard_registers_all_pages_in_order(qapp):
    wizard = build_wizard()
    assert wizard.page(WELCOME_PAGE_ID) is not None
    assert wizard.page(PREFLIGHT_PAGE_ID) is not None
    assert wizard.page(CONFIRM_PAGE_ID) is not None
    assert wizard.page(MIGRATE_PAGE_ID) is not None
    assert wizard.page(SECUREBOOT_PAGE_ID) is not None
    assert wizard.page(DONE_PAGE_ID) is not None
```

`pytest-qt` provides the `qapp`/`qtbot` fixtures automatically; no conftest needed.

- [ ] **Step 2: Run to verify failure**

Run: `QT_QPA_PLATFORM=offscreen pytest tests/python/test_app.py -v`
Expected: FAIL — `xsb_gui.app` not found.

- [ ] **Step 3: Write `xsb_gui/pages/done_page.py`**

```python
from PyQt6.QtWidgets import QLabel, QVBoxLayout, QWizardPage

DONE_TEXT = (
    "Done. Reboot your system now.\n\n"
    "If your firmware was in Setup Mode, enter UEFI firmware settings after "
    "rebooting and enable Secure Boot, then save and boot normally.\n\n"
    "Tip: systemctl reboot --firmware-setup"
)


class DonePage(QWizardPage):
    def __init__(self, parent=None):
        super().__init__(parent)
        self.setTitle("All done")
        layout = QVBoxLayout(self)
        label = QLabel(DONE_TEXT)
        label.setWordWrap(True)
        layout.addWidget(label)
```

- [ ] **Step 4: Write `xsb_gui/app.py`**

```python
import sys

from PyQt6.QtWidgets import QApplication, QWizard

from xsb_gui.pages.welcome_page import WelcomePage
from xsb_gui.pages.preflight_page import PreflightPage
from xsb_gui.pages.confirm_page import (
    ConfirmPage, WELCOME_PAGE_ID, PREFLIGHT_PAGE_ID, CONFIRM_PAGE_ID,
    MIGRATE_PAGE_ID, SECUREBOOT_PAGE_ID, DONE_PAGE_ID,
)
from xsb_gui.pages.migrate_page import MigratePage
from xsb_gui.pages.secureboot_page import SecureBootPage
from xsb_gui.pages.done_page import DonePage

HELPER_PATH = "/usr/lib/xsb-gui/xsb-helper"


def build_wizard(helper_path=HELPER_PATH, use_pkexec=True):
    wizard = QWizard()
    wizard.setWindowTitle("XeroLinux Limine/SecureBoot Enabler")
    wizard.setPage(WELCOME_PAGE_ID, WelcomePage())
    wizard.setPage(PREFLIGHT_PAGE_ID, PreflightPage(helper_path=helper_path, use_pkexec=use_pkexec))
    wizard.setPage(CONFIRM_PAGE_ID, ConfirmPage())
    wizard.setPage(MIGRATE_PAGE_ID, MigratePage(helper_path=helper_path, use_pkexec=use_pkexec))
    wizard.setPage(SECUREBOOT_PAGE_ID, SecureBootPage(helper_path=helper_path, use_pkexec=use_pkexec))
    wizard.setPage(DONE_PAGE_ID, DonePage())
    return wizard


def main():
    app = QApplication(sys.argv)
    wizard = build_wizard()
    wizard.show()
    sys.exit(app.exec())


if __name__ == "__main__":
    main()
```

- [ ] **Step 5: Write the `xsb-gui` entrypoint**

```python
#!/usr/bin/env python3
from xsb_gui.app import main

if __name__ == "__main__":
    main()
```

Run: `chmod +x xsb-gui`

- [ ] **Step 6: Run to verify pass**

Run: `QT_QPA_PLATFORM=offscreen pytest tests/python/test_app.py -v`
Expected: PASS (1 test). Then run the full Python suite: `QT_QPA_PLATFORM=offscreen pytest tests/python/ -v` — expect all tests across all files passing.

- [ ] **Step 7: Commit**

```bash
git add xsb_gui/pages/done_page.py xsb_gui/app.py xsb-gui tests/python/test_app.py
git commit -m "feat: assemble the full wizard and add the xsb-gui entrypoint"
```

---

### Task 21: Packaging validation

**Files:**
- Modify: `PKGBUILD` (only if validation surfaces an issue)

**Interfaces:**
- None — this task validates artifacts from Task 1 against the files now present from Tasks 2-20.

- [ ] **Step 1: Generate and inspect `.SRCINFO`**

Run: `makepkg --printsrcinfo > .SRCINFO && cat .SRCINFO`
Expected: valid srcinfo output listing `pkgname = xsb-gui` and all `depends` entries from Task 1.

- [ ] **Step 2: Lint the PKGBUILD**

Run: `command -v namcap && namcap PKGBUILD || echo "namcap not installed, skipping"`
Expected: no errors (warnings about the empty `source=()`/`sha256sums=()` array are expected and fine until this is published to a repo with real source tarballs).

- [ ] **Step 3: Re-validate the desktop file and polkit policy now that real paths exist**

Run:
```bash
desktop-file-validate xsb-gui.desktop
python3 -c "import xml.dom.minidom; xml.dom.minidom.parse('xyz.xerolinux.xsb-gui.policy')"
```
Expected: no output from either command.

- [ ] **Step 4: Run the full test suite one final time**

Run:
```bash
bats tests/bats/
QT_QPA_PLATFORM=offscreen pytest tests/python/ -v
```
Expected: all Bash and Python tests passing.

- [ ] **Step 5: Commit**

```bash
git add .SRCINFO
git commit -m "chore: generate .SRCINFO and validate packaging metadata"
```

---

## Self-Review Notes

- **Spec coverage:** welcome/warning (Task 16), pre-flight incl. UEFI/GPT/ESP/bootloader/LUKS/mkinitcpio/dual-OS/Secure-Boot-state (Tasks 3-8, 17), confirm/summary (Task 18), migrate execution with install-then-verify-then-remove-GRUB ordering (Tasks 9-11a, 19), Secure Boot enrollment/signing ported from `xero-secureboot` (Tasks 6, 12, 19), done screen (Task 20), pkexec/polkit privilege escalation (Tasks 1, 15), PKGBUILD packaging (Tasks 1, 21). All design sections have a corresponding task.
- **Placeholder scan:** the one placeholder called out explicitly (Task 11's hardcoded `/dev/vda`/`"1"`) is resolved by Task 11a in the same plan, not left dangling — the plan is self-contained.
- **Type consistency:** `PreflightResult` fields (`uefi, gpt, esp_mountpoint, bootloader, luks, mkinitcpio_hook, other_os, secureboot_state`) are identical across `lib/preflight.sh`'s `emit_preflight_result`, `xsb_gui/parsing.py`, and every test that constructs one. Page-id constants (`WELCOME_PAGE_ID` ... `DONE_PAGE_ID`) are defined once in `confirm_page.py` and imported everywhere else that needs them (`app.py`, `test_app.py`).
