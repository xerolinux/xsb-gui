# Hardware Testing Status

Tracks which features have actually been run on real UEFI hardware versus
verified only through the automated test suite (bats/pytest, dry-run
previews, fixtures). Update this file whenever a feature gets exercised on
real hardware for the first time, or when a fixture-only feature's
assumptions turn out to be wrong once tried for real - several real bugs in
this project were only found this way, never by the test suite alone.

**Legend**
- ✅ Verified on real hardware
- ⚠️ Verified on real hardware, but a real bug was found there (see notes)
- 🧪 Automated tests only (bats/pytest/dry-run) - never run on real hardware
- ❓ Not exercised at all yet (code exists, no test coverage of any kind)

| Feature | Status | Notes |
|---|---|---|
| `preflight` (UEFI/GPT/ESP/bootloader/LUKS detection) | ✅ | Verified on a real Secure Boot machine: uefi/gpt/esp all correct. |
| `migrate` (GRUB → Limine) | 🧪 | Extensively dry-run/fixture tested. The full real cycle (fresh GRUB install → migrate → reboot → confirm boot) has not been run end-to-end on real hardware. |
| `enable-secureboot` (fresh enrollment + re-sign paths) | ✅ | Re-signing path run for real on a Secure Boot machine; fresh key creation/enrollment path is fixture-tested only. |
| Kernel untracking (not signing) for Limine's `protocol: linux` | ✅ | Confirmed on real hardware: an unsigned ESP kernel boots fine under Secure Boot: Limine verifies by pinned BLAKE2B hash, never checks a UEFI signature. |
| fwupd Secure Boot integration (`configure_fwupd_secureboot`) | ✅ | Run for real on a Secure Boot machine: signs `fwupdx64.efi`, sets `DisableShimForSecureBoot=true`. `sbctl verify` came back clean. |
| `revert` (GRUB restore + Limine removal) | ⚠️ | First real-world run (on a different machine than where it was built) found a real bug: `remove_limine` didn't clear the stale UEFI fallback binary, leaving an empty Limine menu with no way to reach the freshly-restored GRUB. Fixed and bats-tested, but the fix itself has not yet been re-verified on real hardware. |
| `cleanup` (orphaned kernel/UKI/backup pruning) | 🧪 | Dry-run verified against a real ESP (correctly targeted `limine.conf.old`, stale `.bak` files, unused `loader/`, never the active kernel). Real (non-dry-run) apply not yet confirmed on real hardware. |
| UKI pruning (`cleanup_orphaned_esp_ukis`) | ❓ | `ENABLE_UKI` was off on every machine used so far - this path has only ever run against synthetic fixtures, never a real UKI. |
| `doctor` (boot health check) | 🧪 | New. Bats/pytest only so far. |
| GPT hard-gate in `preflight` | 🧪 | New. Logic is simple (reuses already-verified `detect_partition_table`) but not yet exercised on a real non-GPT (or real GPT) box specifically for this gate. |
| F2/F3 fixes (kernel-file-exists verification, label-agnostic GRUB NVRAM matching) | 🧪 | New. Bats-tested (including a regression test reproducing each original bug), not yet re-verified on real hardware. |
| Revert backup staleness warning | 🧪 | New. Bats-tested only. |

## Why this matters here specifically

Several real, user-impacting bugs in this project were invisible to the
automated test suite and only surfaced on real hardware:
- `sbctl_keys_exist_locally` only checking the legacy `/usr/share/secureboot`
  key path (modern `sbctl` uses `/var/lib/sbctl`).
- The Secure Boot state detection regex not matching `sbctl`'s real
  checkmark-glyph output.
- A "UEFI OS" firmware-created fallback entry producing a chainload false
  positive.
- The revert-to-GRUB fallback-binary bug this file was created to help
  prevent from happening again.

None of these were reachable by mocking alone - they needed a machine with
the real firmware/`sbctl`/`efibootmgr` behavior the tool depends on. Treat
anything marked 🧪 or ❓ above as "believed correct, not yet proven" rather
than "done."
