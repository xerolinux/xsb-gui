#!/usr/bin/env bats

setup() {
  source "${BATS_TEST_DIRNAME}/../../lib/jsonevent.sh"
  source "${BATS_TEST_DIRNAME}/../../lib/preflight.sh"
  source "${BATS_TEST_DIRNAME}/../../lib/chainload.sh"
  source "${BATS_TEST_DIRNAME}/../../lib/secureboot.sh"
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
  result="$(emit_preflight_result true true "/boot/efi" "grub" false "none" '[]' "disabled" "1073741824")"
  echo "$result" | python3 -c "import json,sys; d=json.load(sys.stdin); assert d['event']=='preflight_result'; assert d['data']['bootloader']=='grub'; assert d['data']['esp_size_bytes']==1073741824"
}

@test "emit_preflight_result defaults esp_size_bytes to 0 when omitted" {
  result="$(emit_preflight_result true true "/boot/efi" "grub" false "none" '[]' "disabled")"
  echo "$result" | python3 -c "import json,sys; d=json.load(sys.stdin); assert d['data']['esp_size_bytes']==0"
}

@test "emit_preflight_result includes esp_free_bytes when provided" {
  result="$(emit_preflight_result true true "/boot/efi" "limine" false "none" '[]' "enabled" "2147483648" "1073741824")"
  echo "$result" | python3 -c "import json,sys; d=json.load(sys.stdin); assert d['data']['esp_free_bytes']==1073741824; assert d['data']['esp_size_bytes']==2147483648"
}

@test "emit_preflight_result defaults esp_free_bytes to 0 when omitted" {
  result="$(emit_preflight_result true true "/boot/efi" "grub" false "none" '[]' "disabled" "1073741824")"
  echo "$result" | python3 -c "import json,sys; d=json.load(sys.stdin); assert d['data']['esp_free_bytes']==0"
}

@test "detect_esp_free_bytes returns failure when no mountpoint given" {
  run detect_esp_free_bytes ""
  [ "$status" -eq 1 ]
}

@test "detect_esp_free_bytes returns a positive integer for a real path" {
  result="$(detect_esp_free_bytes "$BATS_TEST_TMPDIR")"
  [[ "$result" =~ ^[0-9]+$ ]]
  [ "$result" -gt 0 ]
}

@test "detect_esp_size_bytes returns failure when no mountpoint given" {
  run detect_esp_size_bytes ""
  [ "$status" -eq 1 ]
}

@test "detect_esp_size_bytes reads size via findmnt and lsblk" {
  findmnt() { echo "/dev/sda1"; }
  lsblk() { echo "1073741824"; }
  export -f findmnt lsblk
  result="$(detect_esp_size_bytes "/boot/efi")"
  [ "$result" = "1073741824" ]
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
  detect_esp_size_bytes() { echo "1073741824"; }
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
  [[ "$output" == *'"esp_size_bytes":1073741824'* ]]
}
