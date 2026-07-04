#!/usr/bin/env bats

setup() {
  source "${BATS_TEST_DIRNAME}/../../lib/jsonevent.sh"
  source "${BATS_TEST_DIRNAME}/../../lib/preflight.sh"
  source "${BATS_TEST_DIRNAME}/../../lib/chainload.sh"
  source "${BATS_TEST_DIRNAME}/../../lib/secureboot.sh"
  source "${BATS_TEST_DIRNAME}/../../lib/migrate.sh"
  source "${BATS_TEST_DIRNAME}/../../lib/doctor.sh"
  source "${BATS_TEST_DIRNAME}/../../lib/revert.sh"
}

@test "grub_backup_is_complete true only when MANIFEST exists" {
  d="$BATS_TEST_TMPDIR/bk"
  mkdir -p "$d"
  run grub_backup_is_complete "$d"
  [ "$status" -ne 0 ]
  : > "$d/MANIFEST"
  run grub_backup_is_complete "$d"
  [ "$status" -eq 0 ]
}

@test "grub_bootloader_id_from_backup parses the label and defaults to GRUB" {
  d="$BATS_TEST_TMPDIR/bk"
  mkdir -p "$d"
  printf 'Boot0003* XeroLinux\tHD(1,GPT,x)/File(\\EFI\\XeroLinux\\grubx64.efi)\n' > "$d/nvram-grub.txt"
  [ "$(grub_bootloader_id_from_backup "$d")" = "XeroLinux" ]
  rm -f "$d/nvram-grub.txt"
  [ "$(grub_bootloader_id_from_backup "$d")" = "GRUB" ]
}

@test "backup_grub_state previews under DRY_RUN without writing anything" {
  d="$BATS_TEST_TMPDIR/bk"
  DRY_RUN=1
  run backup_grub_state /boot/efi "$d"
  [ "$status" -eq 0 ]
  [[ "$output" == *"would_run"* ]]
  [ ! -e "$d/MANIFEST" ]
}

@test "snapshot_kernel_state_for_backup records a timestamp and the currently-installed kernel packages" {
  d="$BATS_TEST_TMPDIR/bk"
  mkdir -p "$d"
  pacman() {
    if [[ "$1" == "-Q" ]]; then printf 'linux 6.10.1-1\nvim 9.0-1\n'; fi
  }
  export -f pacman
  snapshot_kernel_state_for_backup "$d"
  [[ "$(cat "$d/timestamp.txt")" =~ ^[0-9]+$ ]]
  [[ "$(cat "$d/kernel-packages.txt")" == "linux 6.10.1-1" ]]
}

@test "backup_grub_state_staleness_warning: nothing to warn about when recent and kernel packages match" {
  d="$BATS_TEST_TMPDIR/bk"
  mkdir -p "$d"
  now=1700000000
  printf '%s' "$now" > "$d/timestamp.txt"
  printf 'linux 6.10.1-1\n' > "$d/kernel-packages.txt"
  run backup_grub_state_staleness_warning "$d" "$now" 30 "linux 6.10.1-1"
  [ "$status" -ne 0 ]
  [ -z "$output" ]
}

@test "backup_grub_state_staleness_warning: warns when the backup is older than the age threshold" {
  d="$BATS_TEST_TMPDIR/bk"
  mkdir -p "$d"
  printf '%s' "1000000000" > "$d/timestamp.txt"
  now=$((1000000000 + 40 * 86400))
  run backup_grub_state_staleness_warning "$d" "$now" 30
  [ "$status" -eq 0 ]
  [[ "$output" == *"40 days old"* ]]
}

@test "backup_grub_state_staleness_warning: warns when kernel packages differ from backup time, even if recent" {
  d="$BATS_TEST_TMPDIR/bk"
  mkdir -p "$d"
  now=1700000000
  printf '%s' "$now" > "$d/timestamp.txt"
  printf 'linux 6.10.1-1\n' > "$d/kernel-packages.txt"
  run backup_grub_state_staleness_warning "$d" "$now" 30 $'linux 6.11.0-1\n'
  [ "$status" -eq 0 ]
  [[ "$output" == *"Kernel packages have changed"* ]]
}

@test "backup_grub_state_staleness_warning: nothing to warn about when there is no recorded timestamp (older backup format)" {
  d="$BATS_TEST_TMPDIR/bk"
  mkdir -p "$d"
  run backup_grub_state_staleness_warning "$d" "1700000000" 30 ""
  [ "$status" -ne 0 ]
  [ -z "$output" ]
}

@test "cmd_revert emits a staleness warning event when the backup is stale, without blocking the revert" {
  export XSB_BACKUP_DIR="$BATS_TEST_TMPDIR/bk"
  mkdir -p "$XSB_BACKUP_DIR"
  printf 'grub\n' > "$XSB_BACKUP_DIR/packages.txt"
  printf '%s' "1000000000" > "$XSB_BACKUP_DIR/timestamp.txt"
  grub_backup_is_complete() { return 0; }
  detect_bootloader() { echo "limine"; }
  detect_secureboot_state() { echo "disabled"; }
  find_esp_mountpoint() { echo "$BATS_TEST_TMPDIR/esp"; }
  mkdir -p "$BATS_TEST_TMPDIR/esp"
  backup_grub_state_staleness_warning() { printf 'simulated staleness warning'; return 0; }
  DRY_RUN=1
  run cmd_revert
  [ "$status" -eq 0 ]
  [[ "$output" == *'"level":"warning"'*"simulated staleness warning"* ]]
  [[ "$output" == *"revert_done"* ]]
}

@test "verify_grub_restored requires binary, config, AND firmware entry" {
  esp="$BATS_TEST_TMPDIR/esp"
  mkdir -p "$esp/EFI/GRUB"
  : > "$esp/EFI/GRUB/grubx64.efi"
  cfg="$BATS_TEST_TMPDIR/grub.cfg"
  : > "$cfg"
  ebm="Boot0003* GRUB	HD(1,GPT,x)/File(\\EFI\\GRUB\\grubx64.efi)"
  run verify_grub_restored "$esp" "$ebm" "$cfg"
  [ "$status" -eq 0 ]
  # missing NVRAM entry
  run verify_grub_restored "$esp" "no grub here" "$cfg"
  [ "$status" -ne 0 ]
  # missing config
  run verify_grub_restored "$esp" "$ebm" "$BATS_TEST_TMPDIR/nope.cfg"
  [ "$status" -ne 0 ]
  # missing binary
  run verify_grub_restored "$BATS_TEST_TMPDIR/empty-esp" "$ebm" "$cfg"
  [ "$status" -ne 0 ]
}

@test "remove_limine previews packages, ESP files, and orphaned kernels under DRY_RUN" {
  esp="$BATS_TEST_TMPDIR/esp"
  mid=b7c2a46f0a084a7d89b7f96a4784b975
  mkdir -p "$esp/EFI/XeroLinux" "$esp/$mid/linux"
  : > "$esp/$mid/linux/vmlinuz-linux"
  DRY_RUN=1
  run remove_limine "$esp"
  [ "$status" -eq 0 ]
  [[ "$output" == *"pacman -Rns"* ]]
  [[ "$output" == *"rm -rf $esp/EFI/XeroLinux"* ]]
  [[ "$output" == *"rm -rf $esp/$mid"* ]]
}

@test "cmd_revert refuses when no backup exists" {
  grub_backup_is_complete() { return 1; }
  run cmd_revert
  [ "$status" -ne 0 ]
  [[ "$output" == *"No pre-migration GRUB backup"* ]]
}

@test "cmd_revert refuses when Limine is not the active bootloader" {
  grub_backup_is_complete() { return 0; }
  detect_bootloader() { echo "grub"; }
  run cmd_revert
  [ "$status" -ne 0 ]
  [[ "$output" == *"Limine is not the active bootloader"* ]]
}

@test "cmd_revert refuses when Secure Boot is enabled (would leave unsigned GRUB)" {
  grub_backup_is_complete() { return 0; }
  detect_bootloader() { echo "limine"; }
  detect_secureboot_state() { echo "enabled"; }
  run cmd_revert
  [ "$status" -ne 0 ]
  [[ "$output" == *"Secure Boot is enabled"* ]]
}

@test "cmd_revert does NOT remove Limine when GRUB verification fails" {
  grub_backup_is_complete() { return 0; }
  detect_bootloader() { echo "limine"; }
  detect_secureboot_state() { echo "disabled"; }
  find_esp_mountpoint() { echo "$BATS_TEST_TMPDIR/esp"; }
  mkdir -p "$BATS_TEST_TMPDIR/esp"
  reinstall_grub_packages() { return 0; }
  restore_grub_files() { return 0; }
  verify_grub_restored() { return 1; }
  remove_limine() { echo "SHOULD_NOT_BE_CALLED"; }
  run_cmd() { emit_event "would_run" "info" "$*"; }
  DRY_RUN=0
  run cmd_revert
  [ "$status" -ne 0 ]
  [[ "$output" == *"could not be verified"* ]]
  [[ "$output" != *"SHOULD_NOT_BE_CALLED"* ]]
}

@test "cmd_revert runs the full ordered flow (packages -> grub-install -> restore -> remove Limine) and finishes" {
  export XSB_BACKUP_DIR="$BATS_TEST_TMPDIR/bk"
  mkdir -p "$XSB_BACKUP_DIR"
  printf 'grub\n' > "$XSB_BACKUP_DIR/packages.txt"
  grub_backup_is_complete() { return 0; }
  detect_bootloader() { echo "limine"; }
  detect_secureboot_state() { echo "disabled"; }
  find_esp_mountpoint() { echo "$BATS_TEST_TMPDIR/esp"; }
  mkdir -p "$BATS_TEST_TMPDIR/esp"
  DRY_RUN=1
  run cmd_revert
  [ "$status" -eq 0 ]
  [[ "$output" == *"Reinstalling GRUB packages"* ]]
  [[ "$output" == *"grub-install"* ]]
  [[ "$output" == *"Restoring your original GRUB configuration"* ]]
  [[ "$output" == *"Removing Limine"* ]]
  [[ "$output" == *"revert_done"* ]]
}

@test "cmd_revert runs a post-revert boot doctor check and includes it in the output" {
  export XSB_BACKUP_DIR="$BATS_TEST_TMPDIR/bk"
  mkdir -p "$XSB_BACKUP_DIR"
  printf 'grub\n' > "$XSB_BACKUP_DIR/packages.txt"
  grub_backup_is_complete() { return 0; }
  detect_bootloader() { echo "limine"; }
  detect_secureboot_state() { echo "disabled"; }
  find_esp_mountpoint() { echo "$BATS_TEST_TMPDIR/esp"; }
  mkdir -p "$BATS_TEST_TMPDIR/esp"
  is_uefi() { return 0; }
  detect_partition_table() { return 0; }
  efibootmgr() { printf 'Boot0000* XeroLinux\tHD(1,GPT,aaaa,0x800,0x100000)/File(\\EFI\\XeroLinux\\BOOTX64.EFI)\n'; }
  export -f efibootmgr
  DRY_RUN=1
  run cmd_revert
  [ "$status" -eq 0 ]
  [[ "$output" == *"doctor_check"* ]]
  [[ "$output" == *"doctor_done"* ]]
  [[ "$output" == *"revert_done"* ]]
}

@test "cmd_revert still reports success even when the post-revert doctor check finds a problem" {
  export XSB_BACKUP_DIR="$BATS_TEST_TMPDIR/bk"
  mkdir -p "$XSB_BACKUP_DIR"
  printf 'grub\n' > "$XSB_BACKUP_DIR/packages.txt"
  grub_backup_is_complete() { return 0; }
  detect_bootloader() { echo "limine"; }
  detect_secureboot_state() { echo "disabled"; }
  find_esp_mountpoint() { echo "$BATS_TEST_TMPDIR/esp"; }
  mkdir -p "$BATS_TEST_TMPDIR/esp"
  run_boot_doctor_checks() { emit_event "doctor_done" "error" "simulated doctor failure"; return 1; }
  DRY_RUN=1
  run cmd_revert
  [ "$status" -eq 0 ]
  [[ "$output" == *"simulated doctor failure"* ]]
  [[ "$output" == *"revert_done"* ]]
}

@test "cmd_revert clears Limine's leftover UEFI fallback binary, not just the bootloader-id path" {
  # Regression test: migration also writes Limine's binary to the generic
  # EFI/Boot/BOOTX64.EFI fallback path (deploy_limine_to_esp in migrate.sh),
  # and remove_limine never cleans that path up. Without clearing it here
  # too, firmware falling back to that path after Limine's NVRAM entry is
  # removed loads Limine's now configless binary: an empty Limine menu, no
  # way to reach GRUB, even though GRUB's own NVRAM entry is present.
  export XSB_BACKUP_DIR="$BATS_TEST_TMPDIR/bk"
  mkdir -p "$XSB_BACKUP_DIR"
  printf 'grub\n' > "$XSB_BACKUP_DIR/packages.txt"
  grub_backup_is_complete() { return 0; }
  detect_bootloader() { echo "limine"; }
  detect_secureboot_state() { echo "disabled"; }
  find_esp_mountpoint() { echo "$BATS_TEST_TMPDIR/esp"; }
  mkdir -p "$BATS_TEST_TMPDIR/esp/EFI/Boot"
  : > "$BATS_TEST_TMPDIR/esp/EFI/Boot/BOOTX64.EFI"
  detect_other_os() { echo ""; }
  DRY_RUN=1
  run cmd_revert
  [ "$status" -eq 0 ]
  [[ "$output" == *"Clearing Limine's leftover UEFI fallback binary"* ]]
  [[ "$output" == *"rm -f $BATS_TEST_TMPDIR/esp/EFI/Boot/BOOTX64.EFI"* ]]
}

@test "cmd_revert does not touch the fallback path when nothing is there or a real non-Windows OS owns it" {
  export XSB_BACKUP_DIR="$BATS_TEST_TMPDIR/bk"
  mkdir -p "$XSB_BACKUP_DIR"
  printf 'grub\n' > "$XSB_BACKUP_DIR/packages.txt"
  grub_backup_is_complete() { return 0; }
  detect_bootloader() { echo "limine"; }
  detect_secureboot_state() { echo "disabled"; }
  find_esp_mountpoint() { echo "$BATS_TEST_TMPDIR/esp"; }
  mkdir -p "$BATS_TEST_TMPDIR/esp/EFI/Boot"
  : > "$BATS_TEST_TMPDIR/esp/EFI/Boot/BOOTX64.EFI"
  detect_other_os() { echo "openSUSE Tumbleweed"; }
  DRY_RUN=1
  run cmd_revert
  [ "$status" -eq 0 ]
  [[ "$output" != *"Clearing Limine's leftover UEFI fallback binary"* ]]
  [ -e "$BATS_TEST_TMPDIR/esp/EFI/Boot/BOOTX64.EFI" ]

  detect_other_os() { echo ""; }
  rm "$BATS_TEST_TMPDIR/esp/EFI/Boot/BOOTX64.EFI"
  run cmd_revert
  [ "$status" -eq 0 ]
  [[ "$output" != *"Clearing Limine's leftover UEFI fallback binary"* ]]
}

@test "cmd_revert aborts without touching Limine when clearing the fallback binary fails" {
  export XSB_BACKUP_DIR="$BATS_TEST_TMPDIR/bk"
  mkdir -p "$XSB_BACKUP_DIR"
  printf 'grub\n' > "$XSB_BACKUP_DIR/packages.txt"
  grub_backup_is_complete() { return 0; }
  detect_bootloader() { echo "limine"; }
  detect_secureboot_state() { echo "disabled"; }
  find_esp_mountpoint() { echo "$BATS_TEST_TMPDIR/esp"; }
  mkdir -p "$BATS_TEST_TMPDIR/esp/EFI/Boot"
  : > "$BATS_TEST_TMPDIR/esp/EFI/Boot/BOOTX64.EFI"
  detect_other_os() { echo ""; }
  remove_limine() { echo "SHOULD_NOT_BE_CALLED"; }
  run_cmd() {
    if [[ "$*" == *"rm -f"*"BOOTX64.EFI"* ]]; then
      return 1
    fi
    emit_event "would_run" "info" "$*"
  }
  DRY_RUN=0
  run cmd_revert
  [ "$status" -ne 0 ]
  [[ "$output" == *"Failed to clear Limine's leftover fallback binary"* ]]
  [[ "$output" != *"SHOULD_NOT_BE_CALLED"* ]]
}
