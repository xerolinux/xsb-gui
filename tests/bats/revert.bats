#!/usr/bin/env bats

setup() {
  source "${BATS_TEST_DIRNAME}/../../lib/jsonevent.sh"
  source "${BATS_TEST_DIRNAME}/../../lib/preflight.sh"
  source "${BATS_TEST_DIRNAME}/../../lib/chainload.sh"
  source "${BATS_TEST_DIRNAME}/../../lib/secureboot.sh"
  source "${BATS_TEST_DIRNAME}/../../lib/migrate.sh"
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
