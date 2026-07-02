#!/usr/bin/env bats

setup() {
  source "${BATS_TEST_DIRNAME}/../../lib/jsonevent.sh"
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
  [ "$result" = "/usr/bin/sbctl enroll-keys --microsoft" ]
}

@test "choose_enroll_cmd avoids --firmware-builtin when dbDefault is missing" {
  result="$(choose_enroll_cmd "Dell Inc." "0")"
  [ "$result" = "/usr/bin/sbctl enroll-keys --microsoft" ]
}

@test "choose_enroll_cmd uses --firmware-builtin otherwise" {
  result="$(choose_enroll_cmd "Dell Inc." "1")"
  [ "$result" = "/usr/bin/sbctl enroll-keys --microsoft --firmware-builtin" ]
}

@test "sign_efi_and_kernels signs efi files and kernels under DRY_RUN" {
  esp="$BATS_TEST_TMPDIR/efi"
  mkdir -p "$esp/EFI/XeroLinux"
  touch "$esp/EFI/XeroLinux/BOOTX64.EFI"
  DRY_RUN=1
  result="$(sign_efi_and_kernels "$esp")"
  [[ "$result" == *"/usr/bin/sbctl sign -s $esp/EFI/XeroLinux/BOOTX64.EFI"* ]]
}

@test "cmd_enable_secureboot refuses when not in setup mode and keys not enrolled" {
  detect_secureboot_state() { echo "disabled"; }
  run cmd_enable_secureboot
  [ "$status" -ne 0 ]
  [[ "$output" == *"Setup Mode"* ]]
}

@test "cmd_enable_secureboot signs and finishes when already enrolled" {
  detect_secureboot_state() { echo "setup_mode"; }
  keys_enrolled() { return 0; }
  in_setup_mode() { return 0; }
  choose_enroll_cmd() { echo "sbctl enroll-keys --microsoft"; }
  find_esp_mountpoint() { echo "/boot/efi"; }
  sign_efi_and_kernels() { emit_event "would_run" "info" "sbctl sign-all"; }
  DRY_RUN=1
  run cmd_enable_secureboot
  [ "$status" -eq 0 ]
  [[ "$output" == *"secureboot_done"* ]]
  [[ "$output" != *"create-keys"* ]]
  [[ "$output" != *"enroll-keys"* ]]
}

@test "cmd_enable_secureboot re-signs only when Secure Boot already enabled" {
  detect_secureboot_state() { echo "enabled"; }
  find_esp_mountpoint() { echo "/boot/efi"; }
  sign_efi_and_kernels() { emit_event "would_run" "info" "sbctl sign-all"; }
  DRY_RUN=1
  run cmd_enable_secureboot
  [ "$status" -eq 0 ]
  [[ "$output" == *"secureboot_done"* ]]
  [[ "$output" != *"create-keys"* ]]
  [[ "$output" != *"enroll-keys"* ]]
}

@test "cmd_enable_secureboot creates keys and enrolls when in setup mode with no keys enrolled" {
  detect_secureboot_state() { echo "setup_mode"; }
  keys_enrolled() { return 1; }
  in_setup_mode() { return 0; }
  choose_enroll_cmd() { echo "sbctl enroll-keys --microsoft"; }
  find_esp_mountpoint() { echo "/boot/efi"; }
  sign_efi_and_kernels() { emit_event "would_run" "info" "sbctl sign-all"; }
  DRY_RUN=1
  run cmd_enable_secureboot
  [ "$status" -eq 0 ]
  [[ "$output" == *"/usr/bin/sbctl create-keys"* ]]
  [[ "$output" == *"sbctl enroll-keys --microsoft"* ]]
  [[ "$output" == *"secureboot_done"* ]]
}

@test "cmd_enable_secureboot's board_vendor lookup does not abort under set -euo pipefail when the DMI sysfs file is missing" {
  run bash -c "
    set -euo pipefail
    source '${BATS_TEST_DIRNAME}/../../lib/jsonevent.sh'
    source '${BATS_TEST_DIRNAME}/../../lib/secureboot.sh'
    cat() { [[ \"\$1\" == /sys/class/dmi/id/board_vendor ]] && return 1 || command cat \"\$@\"; }
    detect_secureboot_state() { echo 'setup_mode'; }
    keys_enrolled() { return 1; }
    in_setup_mode() { return 0; }
    choose_enroll_cmd() { echo 'sbctl enroll-keys --microsoft'; }
    find_esp_mountpoint() { echo '/boot/efi'; }
    sign_efi_and_kernels() { emit_event 'would_run' 'info' 'sbctl sign-all'; }
    DRY_RUN=1
    cmd_enable_secureboot
    echo 'REACHED_END'
  "
  [ "$status" -eq 0 ]
  [[ "$output" == *"REACHED_END"* ]]
  [[ "$output" == *"secureboot_done"* ]]
}

@test "cmd_enable_secureboot emits an explicit error event and stops when sbctl create-keys fails" {
  detect_secureboot_state() { echo "setup_mode"; }
  keys_enrolled() { return 1; }
  in_setup_mode() { return 0; }
  run_cmd() {
    if [[ "$1" == "/usr/bin/sbctl" && "$2" == "create-keys" ]]; then
      return 1
    fi
    emit_event "would_run" "info" "$*"
  }
  choose_enroll_cmd() { echo "SHOULD_NOT_BE_CALLED"; }
  find_esp_mountpoint() { echo "/boot/efi"; }
  sign_efi_and_kernels() { echo "SHOULD_NOT_BE_CALLED"; }
  DRY_RUN=1
  run cmd_enable_secureboot
  [ "$status" -ne 0 ]
  [[ "$output" == *'"event":"error"'* ]]
  [[ "$output" == *"Failed to create Secure Boot keys"* ]]
  [[ "$output" != *"SHOULD_NOT_BE_CALLED"* ]]
}

@test "cmd_enable_secureboot emits an explicit error event and stops when key enrollment fails" {
  detect_secureboot_state() { echo "setup_mode"; }
  keys_enrolled() { return 1; }
  in_setup_mode() { return 0; }
  choose_enroll_cmd() { echo "sbctl enroll-keys --microsoft"; }
  run_cmd() {
    if [[ "$1" == "sbctl" && "$2" == "enroll-keys" ]]; then
      return 1
    fi
    emit_event "would_run" "info" "$*"
  }
  find_esp_mountpoint() { echo "/boot/efi"; }
  sign_efi_and_kernels() { echo "SHOULD_NOT_BE_CALLED"; }
  DRY_RUN=1
  run cmd_enable_secureboot
  [ "$status" -ne 0 ]
  [[ "$output" == *'"event":"error"'* ]]
  [[ "$output" == *"Failed to enroll Secure Boot keys"* ]]
  [[ "$output" != *"SHOULD_NOT_BE_CALLED"* ]]
}

@test "cmd_enable_secureboot emits an explicit error event and stops when signing fails after enrollment" {
  detect_secureboot_state() { echo "setup_mode"; }
  keys_enrolled() { return 1; }
  in_setup_mode() { return 0; }
  choose_enroll_cmd() { echo "sbctl enroll-keys --microsoft"; }
  find_esp_mountpoint() { echo "/boot/efi"; }
  sign_efi_and_kernels() { return 1; }
  DRY_RUN=1
  run cmd_enable_secureboot
  [ "$status" -ne 0 ]
  [[ "$output" == *'"event":"error"'* ]]
  [[ "$output" == *"Failed to sign"* ]]
}

@test "cmd_enable_secureboot emits an explicit error event when re-signing fails while Secure Boot is already enabled" {
  detect_secureboot_state() { echo "enabled"; }
  find_esp_mountpoint() { echo "/boot/efi"; }
  sign_efi_and_kernels() { return 1; }
  DRY_RUN=1
  run cmd_enable_secureboot
  [ "$status" -ne 0 ]
  [[ "$output" == *'"event":"error"'* ]]
  [[ "$output" == *"Failed to sign"* ]]
}

@test "cmd_enable_secureboot emits an explicit error event when re-signing fails while keys are already enrolled" {
  detect_secureboot_state() { echo "setup_mode"; }
  keys_enrolled() { return 0; }
  in_setup_mode() { return 0; }
  find_esp_mountpoint() { echo "/boot/efi"; }
  sign_efi_and_kernels() { return 1; }
  DRY_RUN=1
  run cmd_enable_secureboot
  [ "$status" -ne 0 ]
  [[ "$output" == *'"event":"error"'* ]]
  [[ "$output" == *"Failed to sign"* ]]
}
