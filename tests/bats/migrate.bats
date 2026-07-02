#!/usr/bin/env bats

setup() {
  source "${BATS_TEST_DIRNAME}/../../lib/jsonevent.sh"
  source "${BATS_TEST_DIRNAME}/../../lib/chainload.sh"
  source "${BATS_TEST_DIRNAME}/../../lib/migrate.sh"
}

@test "build_limine_conf with no other OS emits nothing (no header, no /XeroLinux block)" {
  result="$(build_limine_conf "")"
  [ -z "$result" ]
}

@test "build_limine_conf never emits a timeout:/default_entry: header, regardless of input" {
  result="$(build_limine_conf "Windows Boot Manager")"
  [[ "$result" != *"timeout:"* ]]
  [[ "$result" != *"default_entry:"* ]]
}

@test "build_limine_conf adds a chainload stanza per other OS using the correct loader path" {
  result="$(build_limine_conf "Windows Boot Manager")"
  [[ "$result" == *"/Windows Boot Manager"* ]]
  [[ "$result" == *"protocol: efi_chainload"* ]]
  [[ "$result" == *"path: boot():/EFI/Microsoft/Boot/bootmgfw.efi"* ]]
}

@test "build_limine_conf handles multiple other OSes" {
  result="$(build_limine_conf $'Windows Boot Manager\nsystemd-boot')"
  count="$(grep -c 'protocol: efi_chainload' <<< "$result")"
  [ "$count" -eq 2 ]
}

@test "chainload_loader_path_for_os maps Windows Boot Manager to the Microsoft loader" {
  result="$(chainload_loader_path_for_os "Windows Boot Manager")"
  [ "$result" = "/EFI/Microsoft/Boot/bootmgfw.efi" ]
}

@test "chainload_loader_path_for_os is case-insensitive for windows" {
  result="$(chainload_loader_path_for_os "windows boot manager")"
  [ "$result" = "/EFI/Microsoft/Boot/bootmgfw.efi" ]
}

@test "chainload_loader_path_for_os falls back to the generic EFI loader for other OSes" {
  result="$(chainload_loader_path_for_os "systemd-boot")"
  [ "$result" = "/EFI/Boot/bootx64.efi" ]
}

@test "install_limine_packages runs pacman with the right package list" {
  DRY_RUN=1
  result="$(install_limine_packages)"
  [[ "$result" == *"/usr/bin/pacman -S --noconfirm --needed limine limine-mkinitcpio-hook"* ]]
}

@test "register_efi_boot_entry builds the correct efibootmgr invocation when no Limine entry exists yet" {
  DRY_RUN=1
  verify_limine_entry() { return 1; }
  result="$(register_efi_boot_entry "/dev/vda" "1")"
  [[ "$result" == *"/usr/bin/efibootmgr --create --disk /dev/vda --part 1 --label XeroLinux --loader"* ]]
}

@test "register_efi_boot_entry skips creation and emits an info event when a Limine entry already exists" {
  DRY_RUN=1
  verify_limine_entry() { return 0; }
  result="$(register_efi_boot_entry "/dev/vda" "1")"
  [[ "$result" != *"efibootmgr --create"* ]]
  [[ "$result" != *"would_run"* ]]
  [[ "$result" != *"running"* ]]
  [[ "$result" == *"already registered"* ]]
}

@test "verify_limine_entry false when only GRUB's own XeroLinux-labeled entry exists" {
  run verify_limine_entry "Boot0000* XeroLinux	HD(1,GPT,aaaa,0x800,0x100000)/File(\EFI\XeroLinux\grubx64.efi)"
  [ "$status" -eq 1 ]
}

@test "verify_limine_entry true when Limine's BOOTX64.EFI entry exists" {
  run verify_limine_entry "Boot0001* XeroLinux	HD(1,GPT,aaaa,0x800,0x100000)/File(\EFI\XeroLinux\BOOTX64.EFI)"
  [ "$status" -eq 0 ]
}

@test "verify_limine_entry false when XeroLinux is absent entirely" {
  run verify_limine_entry "Boot0000* Windows Boot Manager"
  [ "$status" -eq 1 ]
}

@test "deploy_limine_to_esp previews mkdir and cp under DRY_RUN, including the fallback path when skip_fallback=0" {
  DRY_RUN=1
  result="$(deploy_limine_to_esp "/boot/efi" 0)"
  [[ "$result" == *"/usr/bin/mkdir -p /boot/efi/EFI/XeroLinux"* ]]
  [[ "$result" == *"/usr/bin/cp /usr/share/limine/BOOTX64.EFI /boot/efi/EFI/XeroLinux/BOOTX64.EFI"* ]]
  [[ "$result" == *"/usr/bin/mkdir -p /boot/efi/EFI/Boot"* ]]
  [[ "$result" == *"/usr/bin/cp /usr/share/limine/BOOTX64.EFI /boot/efi/EFI/Boot/BOOTX64.EFI"* ]]
}

@test "deploy_limine_to_esp defaults to deploying the fallback path when skip_fallback is omitted" {
  DRY_RUN=1
  result="$(deploy_limine_to_esp "/boot/efi")"
  [[ "$result" == *"/usr/bin/mkdir -p /boot/efi/EFI/Boot"* ]]
  [[ "$result" == *"/usr/bin/cp /usr/share/limine/BOOTX64.EFI /boot/efi/EFI/Boot/BOOTX64.EFI"* ]]
}

@test "deploy_limine_to_esp skips the fallback path deploy when skip_fallback=1" {
  DRY_RUN=1
  result="$(deploy_limine_to_esp "/boot/efi" 1)"
  [[ "$result" == *"/usr/bin/mkdir -p /boot/efi/EFI/XeroLinux"* ]]
  [[ "$result" == *"/usr/bin/cp /usr/share/limine/BOOTX64.EFI /boot/efi/EFI/XeroLinux/BOOTX64.EFI"* ]]
  [[ "$result" != *"/EFI/Boot"* ]]
  [[ "$result" != *"/usr/bin/mkdir -p /boot/efi/EFI/Boot"* ]]
  [[ "$result" != *"/usr/bin/cp /usr/share/limine/BOOTX64.EFI /boot/efi/EFI/Boot/BOOTX64.EFI"* ]]
}

@test "verify_limine_deployed true when BOOTX64.EFI is present under the ESP" {
  mkdir -p "$BATS_TEST_TMPDIR/EFI/XeroLinux"
  : > "$BATS_TEST_TMPDIR/EFI/XeroLinux/BOOTX64.EFI"
  run verify_limine_deployed "$BATS_TEST_TMPDIR"
  [ "$status" -eq 0 ]
}

@test "verify_limine_deployed false when BOOTX64.EFI is absent under the ESP" {
  run verify_limine_deployed "$BATS_TEST_TMPDIR"
  [ "$status" -eq 1 ]
}

@test "verify_limine_conf_has_kernel_entry true when a protocol: linux stanza is present" {
  target="$BATS_TEST_TMPDIR/limine.conf"
  printf 'timeout: 5\ndefault_entry: 1\n\n/XeroLinux\n    protocol: linux\n    kernel_path: boot():/vmlinuz-linux\n' > "$target"
  run verify_limine_conf_has_kernel_entry "$target"
  [ "$status" -eq 0 ]
}

@test "verify_limine_conf_has_kernel_entry false when no protocol: linux stanza is present" {
  target="$BATS_TEST_TMPDIR/limine.conf"
  printf 'timeout: 5\ndefault_entry: 1\n\n/Windows Boot Manager\n    protocol: efi_chainload\n' > "$target"
  run verify_limine_conf_has_kernel_entry "$target"
  [ "$status" -eq 1 ]
}

@test "verify_limine_conf_has_kernel_entry fails (non-zero) when the file does not exist" {
  run verify_limine_conf_has_kernel_entry "$BATS_TEST_TMPDIR/does-not-exist/limine.conf"
  [ "$status" -ne 0 ]
}

@test "resolve_root_cmdline_params non-LUKS uses root=UUID=" {
  result="$(resolve_root_cmdline_params "false" "none" "root-uuid-1234" "")"
  [ "$result" = "root=UUID=root-uuid-1234" ]
}

@test "resolve_root_cmdline_params LUKS with sd-encrypt uses rd.luks.name" {
  result="$(resolve_root_cmdline_params "true" "sd-encrypt" "root-uuid" $'cryptroot UUID=luks-uuid-5678 none luks')"
  [ "$result" = "rd.luks.name=luks-uuid-5678=cryptroot root=/dev/mapper/cryptroot" ]
}

@test "resolve_root_cmdline_params LUKS with encrypt uses cryptdevice=" {
  result="$(resolve_root_cmdline_params "true" "encrypt" "root-uuid" $'cryptroot UUID=luks-uuid-5678 none luks')"
  [ "$result" = "cryptdevice=UUID=luks-uuid-5678:cryptroot root=/dev/mapper/cryptroot" ]
}

@test "build_limine_defaults_content includes params and fixed base flags" {
  result="$(build_limine_defaults_content "root=UUID=root-uuid-1234")"
  [[ "$result" == *"KERNEL_CMDLINE[default]="* ]]
  [[ "$result" == *"quiet nowatchdog loglevel=3"* ]]
  [[ "$result" == *"root=UUID=root-uuid-1234"* ]]
}

@test "write_limine_defaults writes build_limine_defaults_content output to the given path" {
  target="$BATS_TEST_TMPDIR/limine-defaults"
  write_limine_defaults "$target" "root=UUID=root-uuid-1234"
  grep -q "root=UUID=root-uuid-1234" "$target"
  grep -q "KERNEL_CMDLINE\[default\]=" "$target"
}

@test "write_limine_defaults previews without writing when DRY_RUN=1" {
  target="$BATS_TEST_TMPDIR/does-not-exist-dir/limine-defaults"
  DRY_RUN=1
  result="$(write_limine_defaults "$target" "root=UUID=root-uuid-1234")"
  [[ "$result" == *"would_run"* ]]
  [ ! -e "$target" ]
}

@test "find_grub_efi_bootnum returns only the GRUB entry's hex bootnum" {
  efibootmgr_output=$'BootCurrent: 0001\nBootOrder: 0000,0001\nBoot0000* XeroLinux\tHD(1,GPT,aaaa,0x800,0x100000)/File(\\EFI\\XeroLinux\\grubx64.efi)\nBoot0001* XeroLinux\tHD(1,GPT,aaaa,0x800,0x100000)/File(\\EFI\\XeroLinux\\BOOTX64.EFI)'
  result="$(find_grub_efi_bootnum "$efibootmgr_output")"
  [ "$result" = "0000" ]
}

@test "find_grub_efi_bootnum returns empty when no GRUB entry exists" {
  efibootmgr_output=$'Boot0001* XeroLinux\tHD(1,GPT,aaaa,0x800,0x100000)/File(\\EFI\\XeroLinux\\BOOTX64.EFI)'
  result="$(find_grub_efi_bootnum "$efibootmgr_output")"
  [ -z "$result" ]
}

@test "find_grub_efi_bootnum exits 0 even when nothing is found (safe under set -e pipefail)" {
  efibootmgr_output=$'Boot0001* XeroLinux\tHD(1,GPT,aaaa,0x800,0x100000)/File(\\EFI\\XeroLinux\\BOOTX64.EFI)'
  run find_grub_efi_bootnum "$efibootmgr_output"
  [ "$status" -eq 0 ]
}

@test "find_grub_efi_bootnum does not abort under set -e -o pipefail when no GRUB entry is found" {
  run bash -c "
    set -euo pipefail
    source '${BATS_TEST_DIRNAME}/../../lib/jsonevent.sh'
    source '${BATS_TEST_DIRNAME}/../../lib/migrate.sh'
    efibootmgr_output=\$'Boot0001* XeroLinux\tHD(1,GPT,aaaa,0x800,0x100000)/File(\\\\EFI\\\\XeroLinux\\\\BOOTX64.EFI)'
    grub_bootnum=\"\$(find_grub_efi_bootnum \"\$efibootmgr_output\")\"
    echo \"ok:[\$grub_bootnum]\"
  "
  [ "$status" -eq 0 ]
  [[ "$output" == "ok:[]" ]]
}

@test "remove_grub previews the expected commands under DRY_RUN" {
  DRY_RUN=1
  find_grub_efi_bootnum() { echo "0000"; }
  result="$(remove_grub)"
  [[ "$result" == *"/usr/bin/pacman -Rns --noconfirm grub grub-hooks update-grub os-prober"* ]]
  [[ "$result" == *"/usr/bin/rm -rf /boot/grub"* ]]
  [[ "$result" == *"/usr/bin/rm -f /etc/default/grub"* ]]
  [[ "$result" == *"/usr/bin/efibootmgr -b 0000 -B"* ]]
}

@test "remove_grub does not attempt to delete an EFI entry when none is found" {
  DRY_RUN=1
  find_grub_efi_bootnum() { echo ""; }
  result="$(remove_grub)"
  [[ "$result" != *"/usr/bin/efibootmgr -b"* ]]
}

@test "write_limine_conf appends chainload stanzas to the given path without clobbering it" {
  target="$BATS_TEST_TMPDIR/limine.conf"
  printf 'timeout: 5\ndefault_entry: 1\n' > "$target"
  write_limine_conf "$target" "Windows Boot Manager"
  grep -q "timeout: 5" "$target"
  grep -q "/Windows Boot Manager" "$target"
}

@test "write_limine_conf adds no chainload block when there is no other OS, but still prepends the theme header" {
  target="$BATS_TEST_TMPDIR/limine.conf"
  printf 'timeout: 5\ndefault_entry: 1\n' > "$target"
  write_limine_conf "$target" ""
  content="$(cat "$target")"
  [[ "$content" == *"### Theme"* ]]
  [[ "$content" == *"timeout: 5"* ]]
  [[ "$content" != *"protocol: efi_chainload"* ]]
}

@test "write_limine_conf does not duplicate timeout:/default_entry: lines already written by the hook" {
  target="$BATS_TEST_TMPDIR/limine.conf"
  printf 'timeout: 5\ndefault_entry: 1\n' > "$target"
  write_limine_conf "$target" "Windows Boot Manager"
  timeout_count="$(grep -c '^timeout:' "$target")"
  default_entry_count="$(grep -c '^default_entry:' "$target")"
  [ "$timeout_count" -eq 1 ]
  [ "$default_entry_count" -eq 1 ]
  grep -q "/Windows Boot Manager" "$target"
}

@test "write_limine_conf previews without writing when DRY_RUN=1" {
  target="$BATS_TEST_TMPDIR/does-not-exist-dir/limine.conf"
  DRY_RUN=1
  result="$(write_limine_conf "$target" "Windows Boot Manager")"
  [[ "$result" == *"would_run"* ]]
  [ ! -e "$target" ]
}

@test "build_limine_theme_header emits the fixed Rose Pine theme block" {
  result="$(build_limine_theme_header)"
  [[ "$result" == *"### Theme"* ]]
  [[ "$result" == *"term_palette: 232136;eb6f92;9ccfd8;f6c177;3e8fb0;c4a7e7;9ccfd8;e0def4"* ]]
  [[ "$result" == *"term_palette_bright: 6e6a86;eb6f92;9ccfd8;f6c177;3e8fb0;c4a7e7;9ccfd8;e0def4"* ]]
  [[ "$result" == *"term_background: 232136"* ]]
  [[ "$result" == *"term_foreground: e0def4"* ]]
  [[ "$result" == *"term_background_bright: 6e6a86"* ]]
  [[ "$result" == *"term_foreground_bright: e0def4"* ]]
}

@test "write_limine_conf prepends the theme header first, keeps existing content, then appends chainload stanzas at the bottom" {
  target="$BATS_TEST_TMPDIR/limine.conf"
  printf 'timeout: 5\ndefault_entry: 1\n\n/XeroLinux\n    protocol: linux\n' > "$target"
  write_limine_conf "$target" "Windows Boot Manager"
  theme_line="$(grep -n '^### Theme$' "$target" | head -1 | cut -d: -f1)"
  orig_line="$(grep -n '^timeout: 5$' "$target" | head -1 | cut -d: -f1)"
  chain_line="$(grep -n '/Windows Boot Manager' "$target" | head -1 | cut -d: -f1)"
  [ "$(head -1 "$target")" = "### Theme" ]
  [ -n "$theme_line" ]
  [ -n "$orig_line" ]
  [ -n "$chain_line" ]
  [ "$theme_line" -lt "$orig_line" ]
  [ "$orig_line" -lt "$chain_line" ]
}

@test "write_limine_conf preserves the original file's permission bits across the temp-file swap" {
  target="$BATS_TEST_TMPDIR/limine.conf"
  printf 'timeout: 5\ndefault_entry: 1\n' > "$target"
  chmod 644 "$target"
  write_limine_conf "$target" ""
  mode="$(stat -c '%a' "$target")"
  [ "$mode" = "644" ]
}

@test "write_limine_conf does not duplicate the theme header when run twice against the same file" {
  target="$BATS_TEST_TMPDIR/limine.conf"
  printf 'timeout: 5\ndefault_entry: 1\n' > "$target"
  write_limine_conf "$target" "Windows Boot Manager"
  write_limine_conf "$target" "Windows Boot Manager"
  count="$(grep -c '^### Theme$' "$target")"
  [ "$count" -eq 1 ]
}

stub_cmd_migrate_happy_path() {
  detect_bootloader() { echo "grub"; }
  detect_secureboot_state() { echo "disabled"; }
  find_esp_mountpoint() { echo "/boot/efi"; return 0; }
  detect_other_os() { echo ""; }
  detect_luks_root() { return 1; }
  detect_mkinitcpio_hook_family() { echo "none"; }
  findmnt() { echo "root-uuid-1234"; }
  write_limine_conf() { :; }
  install_limine_packages() { emit_event "would_run" "info" "install limine"; }
  write_limine_defaults() { emit_event "would_run" "info" "write limine defaults"; }
  deploy_limine_to_esp() { emit_event "would_run" "info" "deploy limine to esp skip_fallback=${2-0}"; }
  resolve_esp_disk_and_part() { echo "/dev/vda 1"; }
  register_efi_boot_entry() { emit_event "would_run" "info" "efibootmgr create"; }
  run_limine_mkinitcpio() { emit_event "would_run" "info" "limine-mkinitcpio"; }
  verify_limine_entry() { return 0; }
  verify_limine_deployed() { return 0; }
  verify_limine_conf_has_kernel_entry() { return 0; }
  remove_grub() { emit_event "would_run" "info" "pacman -Rns grub"; }
}

@test "cmd_migrate removes GRUB after a successful verify" {
  stub_cmd_migrate_happy_path
  DRY_RUN=1
  run cmd_migrate
  [ "$status" -eq 0 ]
  [[ "$output" == *"pacman -Rns grub"* ]]
  [[ "$output" == *"migrate_done"* ]]
}

@test "cmd_migrate deploys the fallback path when no other OS is detected" {
  stub_cmd_migrate_happy_path
  detect_other_os() { echo ""; }
  DRY_RUN=1
  run cmd_migrate
  [ "$status" -eq 0 ]
  [[ "$output" == *"skip_fallback=0"* ]]
}

@test "cmd_migrate deploys the fallback path when only Windows is detected as another OS" {
  stub_cmd_migrate_happy_path
  detect_other_os() { echo "Windows Boot Manager"; }
  DRY_RUN=1
  run cmd_migrate
  [ "$status" -eq 0 ]
  [[ "$output" == *"skip_fallback=0"* ]]
}

@test "cmd_migrate skips the fallback path deploy when a non-Windows other OS is detected" {
  stub_cmd_migrate_happy_path
  detect_other_os() { echo "systemd-boot"; }
  DRY_RUN=1
  run cmd_migrate
  [ "$status" -eq 0 ]
  [[ "$output" == *"skip_fallback=1"* ]]
  [[ "$output" == *"Skipping generic EFI fallback path deploy"* ]]
}

@test "cmd_migrate calls detect_other_os only once, reusing the result for both deploy and write_limine_conf" {
  stub_cmd_migrate_happy_path
  call_count_file="$BATS_TEST_TMPDIR/detect_other_os_calls"
  : > "$call_count_file"
  detect_other_os() { echo "call" >> "$call_count_file"; echo "systemd-boot"; }
  write_limine_conf() {
    [[ "$2" == "systemd-boot" ]] || { echo "WRONG_OTHER_OS_PASSED_TO_WRITE_LIMINE_CONF: $2"; return 1; }
  }
  DRY_RUN=1
  run cmd_migrate
  [ "$status" -eq 0 ]
  [[ "$output" != *"WRONG_OTHER_OS_PASSED_TO_WRITE_LIMINE_CONF"* ]]
  call_count="$(wc -l < "$call_count_file")"
  [ "$call_count" -eq 1 ]
}

@test "cmd_migrate does NOT remove GRUB when verify_limine_entry fails" {
  stub_cmd_migrate_happy_path
  verify_limine_entry() { return 1; }
  remove_grub() { echo "SHOULD_NOT_BE_CALLED"; }
  DRY_RUN=1
  run cmd_migrate
  [ "$status" -ne 0 ]
  [[ "$output" != *"SHOULD_NOT_BE_CALLED"* ]]
  [[ "$output" == *'"event":"error"'* ]]
}

@test "cmd_migrate does NOT remove GRUB when verify_limine_entry fails even though verify_limine_deployed passes" {
  stub_cmd_migrate_happy_path
  verify_limine_entry() { return 1; }
  verify_limine_deployed() { return 0; }
  remove_grub() { echo "SHOULD_NOT_BE_CALLED"; }
  DRY_RUN=1
  run cmd_migrate
  [ "$status" -ne 0 ]
  [[ "$output" != *"SHOULD_NOT_BE_CALLED"* ]]
  [[ "$output" == *'"event":"error"'* ]]
}

@test "cmd_migrate does NOT remove GRUB when verify_limine_deployed fails even though verify_limine_entry passes" {
  stub_cmd_migrate_happy_path
  verify_limine_entry() { return 0; }
  verify_limine_deployed() { return 1; }
  remove_grub() { echo "SHOULD_NOT_BE_CALLED"; }
  DRY_RUN=1
  run cmd_migrate
  [ "$status" -ne 0 ]
  [[ "$output" != *"SHOULD_NOT_BE_CALLED"* ]]
  [[ "$output" == *'"event":"error"'* ]]
}

@test "cmd_migrate does NOT remove GRUB when both verify checks fail" {
  stub_cmd_migrate_happy_path
  verify_limine_entry() { return 1; }
  verify_limine_deployed() { return 1; }
  remove_grub() { echo "SHOULD_NOT_BE_CALLED"; }
  DRY_RUN=1
  run cmd_migrate
  [ "$status" -ne 0 ]
  [[ "$output" != *"SHOULD_NOT_BE_CALLED"* ]]
  [[ "$output" == *'"event":"error"'* ]]
}

@test "cmd_migrate does NOT remove GRUB when verify_limine_conf_has_kernel_entry fails even though the other two checks pass" {
  stub_cmd_migrate_happy_path
  verify_limine_entry() { return 0; }
  verify_limine_deployed() { return 0; }
  verify_limine_conf_has_kernel_entry() { return 1; }
  remove_grub() { echo "SHOULD_NOT_BE_CALLED"; }
  DRY_RUN=1
  run cmd_migrate
  [ "$status" -ne 0 ]
  [[ "$output" != *"SHOULD_NOT_BE_CALLED"* ]]
  [[ "$output" == *'"event":"error"'* ]]
}

@test "cmd_migrate does NOT remove GRUB when all three verify checks fail" {
  stub_cmd_migrate_happy_path
  verify_limine_entry() { return 1; }
  verify_limine_deployed() { return 1; }
  verify_limine_conf_has_kernel_entry() { return 1; }
  remove_grub() { echo "SHOULD_NOT_BE_CALLED"; }
  DRY_RUN=1
  run cmd_migrate
  [ "$status" -ne 0 ]
  [[ "$output" != *"SHOULD_NOT_BE_CALLED"* ]]
  [[ "$output" == *'"event":"error"'* ]]
}

@test "cmd_migrate refuses immediately when GRUB is not the detected bootloader" {
  stub_cmd_migrate_happy_path
  detect_bootloader() { echo "limine"; }
  install_limine_packages() { echo "SHOULD_NOT_BE_CALLED"; }
  DRY_RUN=1
  run cmd_migrate
  [ "$status" -ne 0 ]
  [[ "$output" == *'"event":"error"'* ]]
  [[ "$output" != *"SHOULD_NOT_BE_CALLED"* ]]
}

@test "cmd_migrate refuses immediately when no bootloader is detected" {
  stub_cmd_migrate_happy_path
  detect_bootloader() { echo "none"; }
  install_limine_packages() { echo "SHOULD_NOT_BE_CALLED"; }
  DRY_RUN=1
  run cmd_migrate
  [ "$status" -ne 0 ]
  [[ "$output" == *'"event":"error"'* ]]
  [[ "$output" != *"SHOULD_NOT_BE_CALLED"* ]]
}

@test "cmd_migrate refuses immediately when Secure Boot is already enabled in firmware" {
  stub_cmd_migrate_happy_path
  detect_secureboot_state() { echo "enabled"; }
  find_esp_mountpoint() { echo "SHOULD_NOT_BE_CALLED"; return 0; }
  install_limine_packages() { echo "SHOULD_NOT_BE_CALLED"; }
  DRY_RUN=1
  run cmd_migrate
  [ "$status" -ne 0 ]
  [[ "$output" == *'"event":"error"'* ]]
  [[ "$output" != *"SHOULD_NOT_BE_CALLED"* ]]
}

@test "cmd_migrate emits an explicit error event and stops when install_limine_packages fails" {
  stub_cmd_migrate_happy_path
  install_limine_packages() { return 1; }
  write_limine_defaults() { echo "SHOULD_NOT_BE_CALLED"; }
  DRY_RUN=1
  run cmd_migrate
  [ "$status" -ne 0 ]
  [[ "$output" == *'"event":"error"'* ]]
  [[ "$output" == *"GRUB has NOT been touched"* ]]
  [[ "$output" != *"SHOULD_NOT_BE_CALLED"* ]]
}

@test "cmd_migrate emits an explicit error event and stops when register_efi_boot_entry fails" {
  stub_cmd_migrate_happy_path
  register_efi_boot_entry() { return 1; }
  DRY_RUN=1
  run cmd_migrate
  [ "$status" -ne 0 ]
  [[ "$output" == *'"event":"error"'* ]]
  [[ "$output" == *"GRUB has NOT been touched"* ]]
  [[ "$output" != *"SHOULD_NOT_BE_CALLED"* ]]
}

@test "cmd_migrate emits an explicit error event and stops when write_limine_conf fails" {
  stub_cmd_migrate_happy_path
  write_limine_conf() { return 1; }
  remove_grub() { echo "SHOULD_NOT_BE_CALLED"; }
  DRY_RUN=1
  run cmd_migrate
  [ "$status" -ne 0 ]
  [[ "$output" == *'"event":"error"'* ]]
  [[ "$output" == *"GRUB has NOT been touched"* ]]
  [[ "$output" != *"SHOULD_NOT_BE_CALLED"* ]]
}

@test "run_limine_mkinitcpio previews via would_run when the binary exists" {
  bin="$BATS_TEST_TMPDIR/limine-mkinitcpio"
  printf '#!/usr/bin/env bash\nexit 0\n' > "$bin"
  chmod +x "$bin"
  DRY_RUN=1
  result="$(run_limine_mkinitcpio "$bin")"
  [[ "$result" == *"would_run"* ]]
  [[ "$result" == *"$bin"* ]]
}

@test "run_limine_mkinitcpio returns 0 under DRY_RUN when the binary exists" {
  bin="$BATS_TEST_TMPDIR/limine-mkinitcpio"
  printf '#!/usr/bin/env bash\nexit 0\n' > "$bin"
  chmod +x "$bin"
  DRY_RUN=1
  run run_limine_mkinitcpio "$bin"
  [ "$status" -eq 0 ]
}

@test "run_limine_mkinitcpio returns 1 and runs nothing when the binary does not exist" {
  bin="$BATS_TEST_TMPDIR/does-not-exist/limine-mkinitcpio"
  DRY_RUN=1
  run run_limine_mkinitcpio "$bin"
  [ "$status" -eq 1 ]
  [[ "$output" != *"would_run"* ]]
  [[ "$output" != *"running"* ]]
}

@test "cmd_migrate emits an explicit error event and stops when run_limine_mkinitcpio fails" {
  stub_cmd_migrate_happy_path
  run_limine_mkinitcpio() { return 1; }
  write_limine_conf() { echo "SHOULD_NOT_BE_CALLED"; }
  remove_grub() { echo "SHOULD_NOT_BE_CALLED"; }
  DRY_RUN=1
  run cmd_migrate
  [ "$status" -ne 0 ]
  [[ "$output" == *'"event":"error"'* ]]
  [[ "$output" == *"Failed to regenerate Limine boot entries via limine-mkinitcpio"* ]]
  [[ "$output" == *"GRUB has NOT been touched"* ]]
  [[ "$output" != *"SHOULD_NOT_BE_CALLED"* ]]
}

@test "resolve_esp_disk_and_part splits disk and partition number" {
  lsblk() {
    if [[ "$*" == *"PKNAME"* ]]; then echo "vda"; else echo "1"; fi
  }
  result="$(resolve_esp_disk_and_part "/dev/vda1")"
  [ "$result" = "/dev/vda 1" ]
}

@test "cmd_apply_theme refuses when Limine is not the active bootloader" {
  detect_bootloader() { echo "grub"; }
  find_esp_mountpoint() { echo "SHOULD_NOT_BE_CALLED"; return 0; }
  write_limine_conf() { echo "SHOULD_NOT_BE_CALLED"; }
  run cmd_apply_theme
  [ "$status" -ne 0 ]
  [[ "$output" == *'"event":"error"'* ]]
  [[ "$output" != *"SHOULD_NOT_BE_CALLED"* ]]
}

@test "cmd_apply_theme refuses when no EFI system partition is found" {
  detect_bootloader() { echo "limine"; }
  find_esp_mountpoint() { return 1; }
  write_limine_conf() { echo "SHOULD_NOT_BE_CALLED"; }
  run cmd_apply_theme
  [ "$status" -ne 0 ]
  [[ "$output" == *'"event":"error"'* ]]
  [[ "$output" != *"SHOULD_NOT_BE_CALLED"* ]]
}

@test "cmd_apply_theme refuses when limine.conf does not exist at the ESP mountpoint" {
  detect_bootloader() { echo "limine"; }
  find_esp_mountpoint() { echo "$BATS_TEST_TMPDIR"; return 0; }
  write_limine_conf() { echo "SHOULD_NOT_BE_CALLED"; }
  run cmd_apply_theme
  [ "$status" -ne 0 ]
  [[ "$output" == *'"event":"error"'* ]]
  [[ "$output" != *"SHOULD_NOT_BE_CALLED"* ]]
}

@test "cmd_apply_theme applies the theme header only, with an empty other_os_list" {
  detect_bootloader() { echo "limine"; }
  find_esp_mountpoint() { echo "$BATS_TEST_TMPDIR"; return 0; }
  : > "$BATS_TEST_TMPDIR/limine.conf"
  call_args_file="$BATS_TEST_TMPDIR/write_limine_conf_args"
  write_limine_conf() {
    printf '%s\n' "$1" > "$call_args_file"
    printf '%s\n' "$2" >> "$call_args_file"
  }
  run cmd_apply_theme
  [ "$status" -eq 0 ]
  [[ "$output" == *"apply_theme_done"* ]]
  [ "$(sed -n '1p' "$call_args_file")" = "$BATS_TEST_TMPDIR/limine.conf" ]
  [ "$(sed -n '2p' "$call_args_file")" = "" ]
}
