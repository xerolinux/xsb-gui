#!/usr/bin/env bats

setup() {
  source "${BATS_TEST_DIRNAME}/../../lib/jsonevent.sh"
  source "${BATS_TEST_DIRNAME}/../../lib/preflight.sh"
  source "${BATS_TEST_DIRNAME}/../../lib/chainload.sh"
  source "${BATS_TEST_DIRNAME}/../../lib/migrate.sh"
  source "${BATS_TEST_DIRNAME}/../../lib/secureboot.sh"
  source "${BATS_TEST_DIRNAME}/../../lib/doctor.sh"
}

@test "doctor_check_uefi ok/error" {
  is_uefi() { return 0; }
  result="$(doctor_check_uefi)"
  [[ "$result" == ok\|* ]]

  is_uefi() { return 1; }
  result="$(doctor_check_uefi)"
  [[ "$result" == error\|* ]]
}

@test "doctor_check_gpt ok/error" {
  detect_partition_table() { return 0; }
  result="$(doctor_check_gpt)"
  [[ "$result" == ok\|* ]]

  detect_partition_table() { return 1; }
  result="$(doctor_check_gpt)"
  [[ "$result" == error\|* ]]
}

@test "doctor_check_esp_present ok/error" {
  result="$(doctor_check_esp_present "/boot/efi")"
  [[ "$result" == ok\|* ]]
  result="$(doctor_check_esp_present "")"
  [[ "$result" == error\|* ]]
}

@test "doctor_check_nvram_entry: limine ok when registered, error when not, grub is always ok, unknown is a warning" {
  verify_limine_entry() { return 0; }
  result="$(doctor_check_nvram_entry "limine" "")"
  [[ "$result" == ok\|* ]]

  verify_limine_entry() { return 1; }
  result="$(doctor_check_nvram_entry "limine" "")"
  [[ "$result" == error\|* ]]

  result="$(doctor_check_nvram_entry "grub" "")"
  [[ "$result" == ok\|* ]]

  result="$(doctor_check_nvram_entry "none" "")"
  [[ "$result" == warning\|* ]]
}

@test "doctor_check_limine_deployed: not applicable for grub, ok/error for limine" {
  result="$(doctor_check_limine_deployed "$BATS_TEST_TMPDIR" "grub")"
  [[ "$result" == ok\|"Not applicable"* ]]

  mkdir -p "$BATS_TEST_TMPDIR/EFI/XeroLinux"
  : > "$BATS_TEST_TMPDIR/EFI/XeroLinux/BOOTX64.EFI"
  result="$(doctor_check_limine_deployed "$BATS_TEST_TMPDIR" "limine")"
  [[ "$result" == ok\|* ]]

  rm "$BATS_TEST_TMPDIR/EFI/XeroLinux/BOOTX64.EFI"
  result="$(doctor_check_limine_deployed "$BATS_TEST_TMPDIR" "limine")"
  [[ "$result" == error\|* ]]
}

@test "doctor_check_kernel_entry: not applicable for grub, ok/error for limine" {
  result="$(doctor_check_kernel_entry "$BATS_TEST_TMPDIR" "grub")"
  [[ "$result" == ok\|"Not applicable"* ]]

  printf '/XeroLinux\n    protocol: linux\n    path: boot():/vmlinuz-linux\n' > "$BATS_TEST_TMPDIR/limine.conf"
  result="$(doctor_check_kernel_entry "$BATS_TEST_TMPDIR" "limine")"
  [[ "$result" == error\|* ]]

  : > "$BATS_TEST_TMPDIR/vmlinuz-linux"
  result="$(doctor_check_kernel_entry "$BATS_TEST_TMPDIR" "limine")"
  [[ "$result" == ok\|* ]]
}

@test "doctor_check_fallback_path: warns when missing, ok when it matches the active bootloader, warns on mismatch" {
  result="$(doctor_check_fallback_path "$BATS_TEST_TMPDIR" "limine")"
  [[ "$result" == warning\|"No generic UEFI fallback"* ]]

  mkdir -p "$BATS_TEST_TMPDIR/EFI/Boot" "$BATS_TEST_TMPDIR/EFI/XeroLinux"
  printf 'limine-bytes' > "$BATS_TEST_TMPDIR/EFI/XeroLinux/BOOTX64.EFI"
  printf 'limine-bytes' > "$BATS_TEST_TMPDIR/EFI/Boot/BOOTX64.EFI"
  result="$(doctor_check_fallback_path "$BATS_TEST_TMPDIR" "limine")"
  [[ "$result" == ok\|* ]]

  printf 'stale-bytes' > "$BATS_TEST_TMPDIR/EFI/Boot/BOOTX64.EFI"
  result="$(doctor_check_fallback_path "$BATS_TEST_TMPDIR" "limine")"
  [[ "$result" == warning\|"UEFI fallback binary"*"does not match the active Limine"* ]]
}

@test "doctor_check_fallback_path: regression - stale Limine fallback while GRUB is active is flagged, matching the real revert incident" {
  mkdir -p "$BATS_TEST_TMPDIR/EFI/Boot" "$BATS_TEST_TMPDIR/EFI/opensuse"
  printf 'grub-bytes' > "$BATS_TEST_TMPDIR/EFI/opensuse/grubx64.efi"
  printf 'stale-limine-bytes' > "$BATS_TEST_TMPDIR/EFI/Boot/BOOTX64.EFI"
  result="$(doctor_check_fallback_path "$BATS_TEST_TMPDIR" "grub")"
  [[ "$result" == warning\|* ]]

  printf 'grub-bytes' > "$BATS_TEST_TMPDIR/EFI/Boot/BOOTX64.EFI"
  result="$(doctor_check_fallback_path "$BATS_TEST_TMPDIR" "grub")"
  [[ "$result" == ok\|* ]]
}

@test "doctor_check_fwupd_secureboot: not applicable when SB is off or fwupd absent" {
  result="$(doctor_check_fwupd_secureboot "disabled" "$BATS_TEST_TMPDIR/does-not-exist.efi" "$BATS_TEST_TMPDIR/fwupd.conf")"
  [[ "$result" == ok\|"Not applicable"* ]]
}

@test "doctor_check_fwupd_secureboot: warns when not yet signed, warns when signed but shim not disabled, ok when both" {
  : > "$BATS_TEST_TMPDIR/fwupdx64.efi"
  result="$(doctor_check_fwupd_secureboot "enabled" "$BATS_TEST_TMPDIR/fwupdx64.efi" "$BATS_TEST_TMPDIR/fwupd.conf")"
  [[ "$result" == warning\|*".signed does not exist"* ]]

  : > "$BATS_TEST_TMPDIR/fwupdx64.efi.signed"
  result="$(doctor_check_fwupd_secureboot "enabled" "$BATS_TEST_TMPDIR/fwupdx64.efi" "$BATS_TEST_TMPDIR/fwupd.conf")"
  [[ "$result" == warning\|*"DisableShimForSecureBoot is not set"* ]]

  printf '[uefi_capsule]\nDisableShimForSecureBoot=true\n' > "$BATS_TEST_TMPDIR/fwupd.conf"
  result="$(doctor_check_fwupd_secureboot "enabled" "$BATS_TEST_TMPDIR/fwupdx64.efi" "$BATS_TEST_TMPDIR/fwupd.conf")"
  [[ "$result" == ok\|* ]]
}

@test "run_boot_doctor_checks stops early and fails on non-UEFI" {
  is_uefi() { return 1; }
  run run_boot_doctor_checks
  [ "$status" -ne 0 ]
  [[ "$output" == *'"event":"doctor_done"'* ]]
  [[ "$output" == *'"level":"error"'* ]]
  [[ "$output" != *"Partition table"* ]]
}

@test "run_boot_doctor_checks stops early and fails when no ESP is found" {
  is_uefi() { return 0; }
  detect_partition_table() { return 0; }
  find_esp_mountpoint() { return 1; }
  run run_boot_doctor_checks
  [ "$status" -ne 0 ]
  [[ "$output" == *"no EFI system partition found"* ]]
  [[ "$output" != *"Firmware boot entry"* ]]
}

@test "run_boot_doctor_checks reports ok overall on a healthy Limine system" {
  is_uefi() { return 0; }
  detect_partition_table() { return 0; }
  find_esp_mountpoint() { echo "$BATS_TEST_TMPDIR"; }
  detect_bootloader() { echo "limine"; }
  efibootmgr() { printf 'Boot0000* XeroLinux\tHD(1,GPT,aaaa,0x800,0x100000)/File(\\EFI\\XeroLinux\\BOOTX64.EFI)\n'; }
  export -f efibootmgr
  detect_secureboot_state() { echo "disabled"; }
  mkdir -p "$BATS_TEST_TMPDIR/EFI/XeroLinux" "$BATS_TEST_TMPDIR/EFI/Boot"
  printf 'limine-bytes' > "$BATS_TEST_TMPDIR/EFI/XeroLinux/BOOTX64.EFI"
  printf 'limine-bytes' > "$BATS_TEST_TMPDIR/EFI/Boot/BOOTX64.EFI"
  printf '/XeroLinux\n    protocol: linux\n    path: boot():/vmlinuz-linux\n' > "$BATS_TEST_TMPDIR/limine.conf"
  : > "$BATS_TEST_TMPDIR/vmlinuz-linux"
  run run_boot_doctor_checks
  [ "$status" -eq 0 ]
  [[ "$output" == *'"event":"doctor_done"'*'"level":"ok"'* ]]
}

@test "run_boot_doctor_checks returns failure and reports error when the referenced kernel is missing" {
  is_uefi() { return 0; }
  detect_partition_table() { return 0; }
  find_esp_mountpoint() { echo "$BATS_TEST_TMPDIR"; }
  detect_bootloader() { echo "limine"; }
  efibootmgr() { printf 'Boot0000* XeroLinux\tHD(1,GPT,aaaa,0x800,0x100000)/File(\\EFI\\XeroLinux\\BOOTX64.EFI)\n'; }
  export -f efibootmgr
  detect_secureboot_state() { echo "disabled"; }
  mkdir -p "$BATS_TEST_TMPDIR/EFI/XeroLinux"
  : > "$BATS_TEST_TMPDIR/EFI/XeroLinux/BOOTX64.EFI"
  printf '/XeroLinux\n    protocol: linux\n    path: boot():/vmlinuz-linux\n' > "$BATS_TEST_TMPDIR/limine.conf"
  run run_boot_doctor_checks
  [ "$status" -ne 0 ]
  [[ "$output" == *'"event":"doctor_done"'*'"level":"error"'* ]]
}

@test "cmd_doctor runs the full check sequence" {
  is_uefi() { return 1; }
  run cmd_doctor
  [[ "$output" == *"doctor_check"* ]]
  [[ "$output" == *"doctor_done"* ]]
}
