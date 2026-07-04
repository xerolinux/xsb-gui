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

@test "detect_secureboot_state reports enabled with real sbctl checkmark glyphs" {
  result="$(detect_secureboot_state $'Installed: \xe2\x9c\x93 Sbctl is installed\nSetup Mode: \xe2\x9c\x93 Disabled\nSecure Boot: \xe2\x9c\x93 Enabled')"
  [ "$result" = "enabled" ]
}

@test "detect_secureboot_state reports disabled with real sbctl checkmark glyphs" {
  result="$(detect_secureboot_state $'Installed: \xe2\x9c\x93 Sbctl is installed\nSetup Mode: \xe2\x9c\x97 Disabled\nSecure Boot: \xe2\x9c\x97 Disabled')"
  [ "$result" = "disabled" ]
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

@test "sbctl_keys_exist_locally true when the keys directory exists" {
  keys_dir="$BATS_TEST_TMPDIR/keys"
  mkdir -p "$keys_dir"
  run sbctl_keys_exist_locally "$keys_dir"
  [ "$status" -eq 0 ]
}

@test "sbctl_keys_exist_locally false when the keys directory does not exist" {
  keys_dir="$BATS_TEST_TMPDIR/no-such-keys-dir"
  run sbctl_keys_exist_locally "$keys_dir"
  [ "$status" -eq 1 ]
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

@test "sign_efi_and_kernels returns failure when one file fails to sign even though a later file succeeds" {
  esp="$BATS_TEST_TMPDIR/efi2"
  mkdir -p "$esp/EFI/XeroLinux" "$esp/EFI/Boot"
  touch "$esp/EFI/XeroLinux/BOOTX64.EFI" "$esp/EFI/Boot/BOOTX64.EFI"
  DRY_RUN=0
  run_cmd() {
    [[ "$4" == *"/EFI/XeroLinux/"* ]] && return 1
    return 0
  }
  run sign_efi_and_kernels "$esp"
  [ "$status" -ne 0 ]
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
  sbctl_keys_exist_locally() { return 0; }
  choose_enroll_cmd() { echo "sbctl enroll-keys --microsoft"; }
  find_esp_mountpoint() { echo "/boot/efi"; }
  sign_efi_and_kernels() { emit_event "would_run" "info" "sbctl sign-all"; }
  DRY_RUN=1
  run cmd_enable_secureboot
  [ "$status" -eq 0 ]
  [[ "$output" == *"secureboot_needs_reboot"* ]]
  [[ "$output" != *"create-keys"* ]]
  [[ "$output" != *"enroll-keys"* ]]
}

@test "cmd_enable_secureboot re-signs only when Secure Boot already enabled" {
  detect_secureboot_state() { echo "enabled"; }
  sbctl_keys_exist_locally() { return 0; }
  find_esp_mountpoint() { echo "/boot/efi"; }
  sign_efi_and_kernels() { emit_event "would_run" "info" "sbctl sign-all"; }
  DRY_RUN=1
  run cmd_enable_secureboot
  [ "$status" -eq 0 ]
  [[ "$output" == *"secureboot_already_active"* ]]
  [[ "$output" != *"create-keys"* ]]
  [[ "$output" != *"enroll-keys"* ]]
}

@test "cmd_enable_secureboot refuses to sign when Secure Boot is enabled but sbctl has no local keys" {
  detect_secureboot_state() { echo "enabled"; }
  sbctl_keys_exist_locally() { return 1; }
  find_esp_mountpoint() { echo "/boot/efi"; }
  sign_efi_and_kernels() { echo "SHOULD_NOT_BE_CALLED"; }
  DRY_RUN=1
  run cmd_enable_secureboot
  [ "$status" -ne 0 ]
  [[ "$output" == *'"event":"error"'* ]]
  [[ "$output" == *"not by this tool"* ]]
  [[ "$output" != *"SHOULD_NOT_BE_CALLED"* ]]
}

@test "cmd_enable_secureboot refuses to sign when keys are enrolled but sbctl has no local keys" {
  detect_secureboot_state() { echo "setup_mode"; }
  keys_enrolled() { return 0; }
  in_setup_mode() { return 0; }
  sbctl_keys_exist_locally() { return 1; }
  find_esp_mountpoint() { echo "/boot/efi"; }
  sign_efi_and_kernels() { echo "SHOULD_NOT_BE_CALLED"; }
  DRY_RUN=1
  run cmd_enable_secureboot
  [ "$status" -ne 0 ]
  [[ "$output" == *'"event":"error"'* ]]
  [[ "$output" == *"not by this tool"* ]]
  [[ "$output" != *"SHOULD_NOT_BE_CALLED"* ]]
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
  [[ "$output" == *"secureboot_needs_reboot"* ]]
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
  [[ "$output" == *"secureboot_needs_reboot"* ]]
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
  sbctl_keys_exist_locally() { return 0; }
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
  sbctl_keys_exist_locally() { return 0; }
  find_esp_mountpoint() { echo "/boot/efi"; }
  sign_efi_and_kernels() { return 1; }
  DRY_RUN=1
  run cmd_enable_secureboot
  [ "$status" -ne 0 ]
  [[ "$output" == *'"event":"error"'* ]]
  [[ "$output" == *"Failed to sign"* ]]
}

@test "cmd_reset_secureboot_keys previews clearing the local key database under DRY_RUN" {
  detect_secureboot_state() { echo "setup_mode"; }
  DRY_RUN=1
  result="$(cmd_reset_secureboot_keys)"
  [[ "$result" == *"would_run"* ]]
  [[ "$result" == *"/usr/bin/rm -rf /usr/share/secureboot"* ]]
}

@test "cmd_reset_secureboot_keys tells the user to run enable-secureboot when firmware is in Setup Mode" {
  detect_secureboot_state() { echo "setup_mode"; }
  DRY_RUN=1
  run cmd_reset_secureboot_keys
  [ "$status" -eq 0 ]
  [[ "$output" == *"reset_keys_done"* ]]
  [[ "$output" == *"you can now run enable-secureboot to start fresh"* ]]
}

@test "cmd_reset_secureboot_keys tells the user to clear firmware keys manually when not in Setup Mode" {
  detect_secureboot_state() { echo "disabled"; }
  DRY_RUN=1
  run cmd_reset_secureboot_keys
  [ "$status" -eq 0 ]
  [[ "$output" == *"reset_keys_done"* ]]
  [[ "$output" == *"firmware still has existing keys enrolled"* ]]
  [[ "$output" == *"PK, KEK, db, dbx"* ]]
}

@test "cmd_reset_secureboot_keys tells the user the state is unknown when sbctl is unavailable, instead of claiming keys are enrolled" {
  # Real-world case found by running the real xsb-helper on a sandbox with
  # no sbctl installed: detect_secureboot_state returns "unsupported", not
  # "keys enrolled" - the old in_setup_mode-only check couldn't tell the
  # difference and would wrongly claim keys were confirmed enrolled.
  detect_secureboot_state() { echo "unsupported"; }
  DRY_RUN=1
  run cmd_reset_secureboot_keys
  [ "$status" -eq 0 ]
  [[ "$output" == *"reset_keys_done"* ]]
  [[ "$output" == *"Could not determine the firmware's current Secure Boot state"* ]]
  [[ "$output" != *"firmware still has existing keys enrolled"* ]]
}

@test "cmd_reset_secureboot_keys emits an explicit error event and stops when clearing local keys fails" {
  run_cmd() {
    if [[ "$1" == "/usr/bin/rm" && "$2" == "-rf" && "$3" == "/usr/share/secureboot" ]]; then
      return 1
    fi
    emit_event "would_run" "info" "$*"
  }
  detect_secureboot_state() { echo "SHOULD_NOT_BE_CALLED"; }
  DRY_RUN=1
  run cmd_reset_secureboot_keys
  [ "$status" -ne 0 ]
  [[ "$output" == *'"event":"error"'* ]]
  [[ "$output" == *"Failed to clear local Secure Boot keys"* ]]
  [[ "$output" != *"reset_keys_done"* ]]
  [[ "$output" != *"SHOULD_NOT_BE_CALLED"* ]]
}

@test "configure_fwupd_secureboot does nothing when fwupd's UEFI binary is not present" {
  fwupd_efi="$BATS_TEST_TMPDIR/does-not-exist/fwupdx64.efi"
  fwupd_conf="$BATS_TEST_TMPDIR/fwupd.conf"
  run_cmd() { echo "SHOULD_NOT_BE_CALLED"; }
  result="$(configure_fwupd_secureboot "$fwupd_efi" "$fwupd_conf")"
  [ -z "$result" ]
}

@test "configure_fwupd_secureboot signs the binary and adds DisableShimForSecureBoot under DRY_RUN" {
  fwupd_efi="$BATS_TEST_TMPDIR/fwupdx64.efi"
  fwupd_conf="$BATS_TEST_TMPDIR/fwupd.conf"
  : > "$fwupd_efi"
  DRY_RUN=1
  result="$(configure_fwupd_secureboot "$fwupd_efi" "$fwupd_conf")"
  [[ "$result" == *"Signing fwupd's UEFI update binary"* ]]
  [[ "$result" == *"sbctl sign -s -o ${fwupd_efi}.signed ${fwupd_efi}"* ]]
  [[ "$result" == *"DisableShimForSecureBoot=true"* ]]
  [ ! -f "$fwupd_conf" ]
}

@test "configure_fwupd_secureboot really signs and appends config when not in DRY_RUN, restarting fwupd.service only if active" {
  fwupd_efi="$BATS_TEST_TMPDIR/fwupdx64.efi"
  fwupd_conf="$BATS_TEST_TMPDIR/fwupd.conf"
  : > "$fwupd_efi"
  DRY_RUN=0
  run_cmd() { echo "RUN_CMD: $*"; }
  systemctl() { [[ "$1" == "is-active" ]] && return 0; echo "SHOULD_NOT_REACH_HERE"; }
  result="$(configure_fwupd_secureboot "$fwupd_efi" "$fwupd_conf")"
  [[ "$result" == *"RUN_CMD: /usr/bin/sbctl sign -s -o ${fwupd_efi}.signed ${fwupd_efi}"* ]]
  [[ "$result" == *"RUN_CMD: /usr/bin/systemctl restart fwupd.service"* ]]
  grep -q "\[uefi_capsule\]" "$fwupd_conf"
  grep -q "DisableShimForSecureBoot=true" "$fwupd_conf"
}

@test "configure_fwupd_secureboot does not restart fwupd.service when it is not active" {
  fwupd_efi="$BATS_TEST_TMPDIR/fwupdx64.efi"
  fwupd_conf="$BATS_TEST_TMPDIR/fwupd2.conf"
  : > "$fwupd_efi"
  DRY_RUN=0
  run_cmd() { echo "RUN_CMD: $*"; }
  systemctl() { return 1; }
  result="$(configure_fwupd_secureboot "$fwupd_efi" "$fwupd_conf")"
  [[ "$result" != *"systemctl restart"* ]]
}

@test "configure_fwupd_secureboot skips the config rewrite when DisableShimForSecureBoot is already active" {
  fwupd_efi="$BATS_TEST_TMPDIR/fwupdx64.efi"
  fwupd_conf="$BATS_TEST_TMPDIR/fwupd3.conf"
  : > "$fwupd_efi"
  printf '[uefi_capsule]\nDisableShimForSecureBoot=true\n' > "$fwupd_conf"
  before="$(cat "$fwupd_conf")"
  DRY_RUN=0
  run_cmd() { echo "RUN_CMD: $*"; }
  systemctl() { return 1; }
  result="$(configure_fwupd_secureboot "$fwupd_efi" "$fwupd_conf")"
  [[ "$result" != *"Configuring fwupd to trust"* ]]
  [ "$(cat "$fwupd_conf")" = "$before" ]
}

@test "configure_fwupd_secureboot still adds the setting when the key is present but set to false or commented out" {
  fwupd_efi="$BATS_TEST_TMPDIR/fwupdx64.efi"
  fwupd_conf="$BATS_TEST_TMPDIR/fwupd5.conf"
  : > "$fwupd_efi"
  printf '[uefi_capsule]\n#DisableShimForSecureBoot=false\n' > "$fwupd_conf"
  DRY_RUN=1
  result="$(configure_fwupd_secureboot "$fwupd_efi" "$fwupd_conf")"
  [[ "$result" == *"Configuring fwupd to trust the signed binary directly"* ]]
  [[ "$result" == *"DisableShimForSecureBoot=true"* ]]
}

@test "configure_fwupd_secureboot is best-effort: a signing failure is logged but does not fail the function or touch the config" {
  fwupd_efi="$BATS_TEST_TMPDIR/fwupdx64.efi"
  fwupd_conf="$BATS_TEST_TMPDIR/fwupd4.conf"
  : > "$fwupd_efi"
  DRY_RUN=0
  run_cmd() { return 1; }
  run configure_fwupd_secureboot "$fwupd_efi" "$fwupd_conf"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Could not sign fwupd's UEFI binary"* ]]
  [ ! -f "$fwupd_conf" ]
}

@test "cmd_enable_secureboot calls configure_fwupd_secureboot after successfully (re-)signing, on all three success paths" {
  find_esp_mountpoint() { echo "/boot/efi"; }
  choose_enroll_cmd() { echo "sbctl enroll-keys --microsoft"; }
  sign_efi_and_kernels() { emit_event "would_run" "info" "sbctl sign-all"; }
  configure_fwupd_secureboot() { emit_event "would_run" "info" "configure_fwupd_secureboot called"; }
  DRY_RUN=1

  detect_secureboot_state() { echo "enabled"; }
  sbctl_keys_exist_locally() { return 0; }
  result="$(cmd_enable_secureboot)"
  [[ "$result" == *"configure_fwupd_secureboot called"* ]]

  detect_secureboot_state() { echo "setup_mode"; }
  keys_enrolled() { return 0; }
  in_setup_mode() { return 0; }
  result="$(cmd_enable_secureboot)"
  [[ "$result" == *"configure_fwupd_secureboot called"* ]]

  keys_enrolled() { return 1; }
  result="$(cmd_enable_secureboot)"
  [[ "$result" == *"configure_fwupd_secureboot called"* ]]
}
