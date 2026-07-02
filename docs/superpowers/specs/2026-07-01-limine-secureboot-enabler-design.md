# XeroLinux Limine/SecureBoot Enabler (`xsb-gui`) — Design

## Purpose

A guided GUI tool for XeroLinux that migrates an installed system's bootloader
from GRUB to Limine and then enables Secure Boot via `sbctl`. It replaces the
older `xero-secureboot` script (GRUB + sbctl), which is being retired since
GRUB's Secure Boot lockdown mode (no on-disk module loading) is fragile. The
tool is a brand-new, standalone package: `xsb-gui`.

## Context (from existing XeroLinux tooling)

- XeroLinux is Arch-based, KDE Plasma / Qt6 (`python-pyqt6` already shipped).
- Calamares config (`~/xwork/CalaBackup/calamaresx-cfg`) shows the installed
  system today: GRUB (`grub`, `grub-hooks`, `update-grub`, `os-prober`), ESP
  mounted at `/boot/efi` (2048M, GPT), XFS default root fs, LUKS2 supported,
  EFI bootloader id `XeroLinux`, `GRUB_DEFAULT=saved`,
  `GRUB_DISABLE_RECOVERY=true`, custom `XeroLayan` GRUB theme.
- `limine` and `limine-mkinitcpio-hook` resolve from the already-enabled
  `extra`/`chaotic-aur` repos — no AUR helper needed.
- The old `xero-secureboot` script (`~/XeroBuild/FOSS/airootfs/usr/local/bin/xero-secureboot`)
  already solves several hard Secure Boot edge cases for GRUB: Setup Mode vs.
  Enabled detection, ASUS `--firmware-builtin` key-enrollment conflicts, VM/OVMF
  missing `dbDefault`, and pacman-hook auto-resigning. This logic is ported,
  re-targeted at Limine's EFI binary and kernel images.

## Scope

- **UEFI only.** Secure Boot doesn't exist on BIOS; the app checks for
  `/sys/firmware/efi` and shows an info-only message + exits on BIOS systems.
- **LUKS-encrypted root is supported**, detected via `/etc/crypttab` +
  `lsblk`, alongside plain unencrypted root.
- **Dual-boot (Windows / other OS) is detected and preserved** as Limine
  chainload entries, matching current `GRUB_DISABLE_OS_PROBER=false` behavior.
- Single-session wizard: no cross-reboot state tracking. GRUB is removed only
  after Limine is installed, deployed to the ESP, and its EFI boot entry is
  verified present — all within the same run, before any reboot happens.
- Basic XeroLinux branding for the Limine menu (background/accent + label),
  not a full port of the GRUB `XeroLayan` theme.
- Packaging as a pacman package (PKGBUILD), not added to
  `XeroBuild/packages.x86_64` as part of this work — that's a follow-up once
  built and tested.

## Architecture

- **GUI**: PyQt6, runs as the normal user. Never runs as root itself.
- **Privilege escalation**: `pkexec` + a polkit `.policy` file
  (`xyz.xerolinux.xsb-gui.policy`), matching how other Plasma system tools
  (e.g. Discover) do privileged actions.
- **Root helper**: `/usr/lib/xsb-gui/xsb-helper`, a single Bash entrypoint with
  subcommands `preflight`, `migrate`, `enable-secureboot`, `status`, backed by
  sub-scripts under `lib/` (`preflight.sh`, `migrate.sh`, `secureboot.sh`,
  `chainload.sh`). All actual system mutation logic lives here, not in
  Python/Qt — the helper is independently runnable/debuggable from a shell.
  It emits JSON-lines progress events on stdout that the GUI parses to drive
  live progress screens.

## Wizard flow (single linear wizard)

1. **Welcome/warning** — explicit plain-English statement of what will
   happen (GRUB and related packages/files permanently removed, Limine
   becomes the bootloader, Secure Boot keys enrolled if firmware Setup Mode
   is available), states this is irreversible without manual recovery,
   requires an "I understand" checkbox to proceed.
2. **Pre-flight checks** (read-only) — UEFI mode (abort with a clear message
   if BIOS), GPT partition table, ESP detected/mounted at `/boot/efi`,
   current bootloader is GRUB (else "GRUB not detected, nothing to migrate"
   and stop), root fs type (LUKS or plain, and which mkinitcpio hook family
   is in use), other-OS detection for chainload entries, Secure Boot
   firmware state (Setup Mode / Enabled / Disabled / unsupported).
3. **Summary/confirm** — shows exactly what pre-flight found and exactly
   what actions will run in order, tailored to this machine. Confirm button
   disabled until the checkbox from step 1 is ticked.
4. **Migration execution** — live progress log driven by helper JSON events,
   run in this order:
   1. install `limine`, `limine-mkinitcpio-hook` (+ LUKS support if needed)
   2. write `/boot/limine.conf` (XeroLinux branding, kernel entries via the
      mkinitcpio hook, LUKS crypto params if applicable, chainload entries
      for other detected OSes)
   3. deploy Limine to the ESP, register its EFI boot entry via
      `efibootmgr` (label `XeroLinux`, matching the current
      `efiBootloaderId`)
   4. regenerate initramfs
   5. **verify** Limine's EFI entry exists (`efibootmgr -v`) and
      `limine.conf` is syntactically valid
   6. only then remove `grub`, `grub-hooks`, `update-grub`, `os-prober`
      packages, delete `/boot/grub`, `/etc/default/grub`, and GRUB's EFI
      boot entry
5. **Secure Boot** (skipped/greyed with explanation if not UEFI-capable) —
   Setup Mode detection, `sbctl create-keys`/`enroll-keys` (ASUS/VM edge
   cases preserved from `xero-secureboot`), sign Limine's EFI binary +
   kernel(s), install the pacman hook so future kernel/Limine updates
   auto-resign.
6. **Done** — explicit next steps: reboot, and (if Setup Mode was used)
   enable Secure Boot in firmware afterward, with the same board-specific
   tips ported from `xero-secureboot`.

## Repo layout

```
LimineSecureBoot/
├── PKGBUILD
├── xsb-gui.install
├── LICENSE
├── README.md
├── xyz.xerolinux.xsb-gui.policy       # polkit policy
├── xsb-gui.desktop                    # app launcher entry
├── xsb-gui                            # PyQt6 GUI entrypoint (python)
├── xsb_gui/                           # Python package: wizard pages, helper wrapper, models
│   ├── __init__.py
│   ├── app.py
│   ├── pages/                         # one file per wizard screen
│   └── assets/                        # icon, wallpaper reused from XeroLayan/xero.png
├── xsb-helper                         # root-side bash helper entrypoint
└── lib/                               # sub-scripts sourced by xsb-helper
    ├── preflight.sh
    ├── migrate.sh
    ├── secureboot.sh
    └── chainload.sh
```

- `PKGBUILD` follows the `calamaresx-cfg` pattern (SPDX headers, simple
  `package()` copying files into place): `xsb-gui` → `/usr/bin`,
  `xsb-helper` + `lib/` → `/usr/lib/xsb-gui/`, `.desktop` →
  `/usr/share/applications`, `.policy` →
  `/usr/share/polkit-1/actions`, icon reused from
  `/usr/share/logos/xero.png` → `/usr/share/icons/hicolor/...`.
- Depends: `python-pyqt6`, `polkit`, `limine`, `limine-mkinitcpio-hook`,
  `sbctl`, `efibootmgr`.

## Error handling & edge cases

- Every helper subcommand checks its own preconditions and is safe to
  re-run; `migrate` refuses without GRUB present or a mounted ESP,
  `enable-secureboot` refuses without UEFI.
- Every destructive step logs a plain-English line surfaced verbatim in the
  GUI — no swallowed errors.
- If any step from Limine-install through EFI-registration fails, the
  helper aborts **before** touching GRUB — GRUB stays the active bootloader
  and the system stays bootable. Only a failure **during** GRUB removal
  itself leaves a partially-migrated state, which gets an explicit "Limine
  is installed and bootable, GRUB removal partially failed, rerun to finish
  cleanup" message rather than silent partial success.
- LUKS: mkinitcpio hook family already in use (`encrypt` vs `sd-encrypt`) is
  detected and preserved, not silently switched.
- Dual-boot: other loaders found via `efibootmgr -v` + scanning ESP
  `/EFI/*` become Limine chainload stanzas, not auto-booted by default.
- Secure Boot: `xero-secureboot`'s edge cases (ASUS `--firmware-builtin`
  conflict, VM/OVMF missing `dbDefault`, Setup-Mode-vs-Enabled distinction,
  re-run-safe signing) are ported verbatim, re-targeted at Limine/kernel
  files instead of GRUB's.

## Testing

Bootloader swap + Secure Boot key enrollment is unsafe to iterate on with
real hardware/disk. Primary development/testing target: a UEFI VM
(QEMU + OVMF, `qemu-system-x86_64 -bios OVMF.fd`) with snapshots, covering:

- plain UEFI/GPT/unencrypted
- LUKS2 root
- dual-boot with a Windows Boot Manager ESP entry present (a fake entry is
  sufficient)
- Setup-Mode vs. not, for the Secure Boot path

Real-hardware validation only after VM coverage is solid, and only on a
disposable/test machine.
