#!/usr/bin/env bats

setup() {
  source "${BATS_TEST_DIRNAME}/../../lib/jsonevent.sh"
  source "${BATS_TEST_DIRNAME}/../../lib/preflight.sh"
  source "${BATS_TEST_DIRNAME}/../../lib/chainload.sh"
  source "${BATS_TEST_DIRNAME}/../../lib/secureboot.sh"
  source "${BATS_TEST_DIRNAME}/../../lib/doctor.sh"
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

@test "verify_limine_conf_has_kernel_entry true when a protocol: linux stanza is present AND the kernel file exists" {
  target="$BATS_TEST_TMPDIR/limine.conf"
  printf 'timeout: 5\ndefault_entry: 1\n\n/XeroLinux\n    protocol: linux\n    kernel_path: boot():/vmlinuz-linux\n' > "$target"
  : > "$BATS_TEST_TMPDIR/vmlinuz-linux"
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

@test "verify_limine_conf_has_kernel_entry fails when protocol: linux is present but the referenced kernel file is missing" {
  # Regression (F2): a textual "protocol: linux" match alone doesn't prove
  # the kernel it references actually exists - this would let GRUB be
  # removed atop a config pointing at a missing kernel image.
  target="$BATS_TEST_TMPDIR/limine.conf"
  printf 'timeout: 5\ndefault_entry: 1\n\n/XeroLinux\n    protocol: linux\n    path: boot():/vmlinuz-linux\n' > "$target"
  run verify_limine_conf_has_kernel_entry "$target"
  [ "$status" -ne 0 ]
}

@test "verify_limine_conf_has_kernel_entry ignores module_path (initramfs) and checks the actual kernel path" {
  target="$BATS_TEST_TMPDIR/limine.conf"
  mkdir -p "$BATS_TEST_TMPDIR/abc123"
  : > "$BATS_TEST_TMPDIR/abc123/initramfs-linux.img"
  printf '/XeroLinux\n    protocol: linux\n    module_path: boot():/abc123/initramfs-linux.img\n    path: boot():/abc123/vmlinuz-linux\n' > "$target"
  run verify_limine_conf_has_kernel_entry "$target"
  [ "$status" -ne 0 ]
  : > "$BATS_TEST_TMPDIR/abc123/vmlinuz-linux"
  run verify_limine_conf_has_kernel_entry "$target"
  [ "$status" -eq 0 ]
}

@test "resolve_root_cmdline_params non-LUKS uses root=UUID=" {
  result="$(resolve_root_cmdline_params "false" "none" "root-uuid-1234" "" "" "ext4" "")"
  [ "$result" = "root=UUID=root-uuid-1234" ]
}

@test "resolve_root_cmdline_params LUKS with sd-encrypt uses rd.luks.name" {
  result="$(resolve_root_cmdline_params "true" "sd-encrypt" "root-uuid" $'cryptroot UUID=luks-uuid-5678 none luks' "" "ext4" "" "")"
  [ "$result" = "rd.luks.name=luks-uuid-5678=cryptroot root=/dev/mapper/cryptroot" ]
}

@test "resolve_root_cmdline_params LUKS with encrypt uses cryptdevice=" {
  result="$(resolve_root_cmdline_params "true" "encrypt" "root-uuid" $'cryptroot UUID=luks-uuid-5678 none luks' "" "ext4" "" "")"
  [ "$result" = "cryptdevice=UUID=luks-uuid-5678:cryptroot root=/dev/mapper/cryptroot" ]
}

@test "resolve_root_cmdline_params REGRESSION GUARD: plain LUKS (no LVM) is completely unchanged when pvs reports no VG" {
  # pvs_output (8th param) explicitly empty == the LUKS mapper is NOT an
  # LVM PV. This must preserve the exact pre-fix root=/dev/mapper/... output.
  result="$(resolve_root_cmdline_params "true" "encrypt" "root-uuid" $'cryptroot UUID=luks-uuid-5678 none luks' "/dev/mapper/cryptroot" "ext4" "" "")"
  [ "$result" = "cryptdevice=UUID=luks-uuid-5678:cryptroot root=/dev/mapper/cryptroot" ]
}

@test "resolve_root_cmdline_params LVM-on-LUKS resolves root= to the real root LV's UUID, not the raw LUKS mapper" {
  crypttab=$'cryptlvm UUID=luks-uuid-9999 none luks'
  result="$(resolve_root_cmdline_params "true" "sd-encrypt" "root-uuid" "$crypttab" "/dev/mapper/vgxero-root" "ext4" "" "  vgxero  " "lv-root-uuid-abcd")"
  [ "$result" = "rd.luks.name=luks-uuid-9999=cryptlvm root=UUID=lv-root-uuid-abcd" ]
}

@test "resolve_root_cmdline_params multi-crypttab picks the entry matching the live root mapper, not the first (e.g. swap) line" {
  crypttab=$'cryptswap UUID=swap-uuid-1111 /dev/urandom swap\ncryptroot UUID=luks-uuid-5678 none luks'
  result="$(resolve_root_cmdline_params "true" "encrypt" "root-uuid" "$crypttab" "/dev/mapper/cryptroot" "ext4" "" "")"
  [ "$result" = "cryptdevice=UUID=luks-uuid-5678:cryptroot root=/dev/mapper/cryptroot" ]
}

@test "resolve_root_cmdline_params multi-crypttab falls back to the first entry (without crashing) when nothing matches the live root mapper" {
  crypttab=$'cryptswap UUID=swap-uuid-1111 /dev/urandom swap\ncryptroot UUID=luks-uuid-5678 none luks'
  result="$(resolve_root_cmdline_params "true" "encrypt" "root-uuid" "$crypttab" "/dev/mapper/doesnotmatch" "ext4" "" "")"
  [ "$result" = "cryptdevice=UUID=swap-uuid-1111:cryptswap root=/dev/mapper/cryptswap" ]
}

@test "resolve_root_cmdline_params LVM-on-LUKS + multi-crypttab (encrypted swap listed FIRST) selects the correct LVM-bearing entry via VG matching, not head -1" {
  # Regression test for the combined-bug scenario: root_source is the LV
  # (/dev/mapper/vgxero-root), which never direct-matches any crypttab
  # mapper name. crypttab lists an unrelated encrypted swap entry first and
  # the real LVM-bearing LUKS container second. Faking lvs (root LV's VG)
  # and pvs (per-crypttab-entry PV check) proves selection is driven by VG
  # membership, not by which line comes first in crypttab.
  crypttab=$'cryptswap UUID=swap-uuid-1111 /dev/urandom swap\ncryptlvm UUID=luks-uuid-9999 none luks'
  lvs() { echo "  vgxero  "; }
  pvs() {
    case "$*" in
      *cryptlvm*) echo "  vgxero  " ;;
      *) echo "" ;;
    esac
  }
  blkid() { echo "lv-root-uuid-abcd"; }
  result="$(resolve_root_cmdline_params "true" "sd-encrypt" "root-uuid" "$crypttab" "/dev/mapper/vgxero-root" "ext4" "")"
  [ "$result" = "rd.luks.name=luks-uuid-9999=cryptlvm root=UUID=lv-root-uuid-abcd" ]
}

@test "resolve_root_cmdline_params appends rootflags=subvol= for a btrfs root (non-LUKS)" {
  result="$(resolve_root_cmdline_params "false" "none" "root-uuid-1234" "" "" "btrfs" "rw,noatime,compress=zstd,ssd,space_cache=v2,subvolid=256,subvol=/@")"
  [ "$result" = "root=UUID=root-uuid-1234 rootflags=subvol=@" ]
}

@test "resolve_root_cmdline_params does not append rootflags for a non-btrfs (xfs, XeroLinux's default) root" {
  result="$(resolve_root_cmdline_params "false" "none" "root-uuid-1234" "" "" "xfs" "rw,relatime,attr2,inode64")"
  [ "$result" = "root=UUID=root-uuid-1234" ]
}

@test "resolve_root_cmdline_params appends rootflags=subvol= for a btrfs root behind plain LUKS too" {
  crypttab=$'cryptroot UUID=luks-uuid-5678 none luks'
  result="$(resolve_root_cmdline_params "true" "encrypt" "root-uuid" "$crypttab" "/dev/mapper/cryptroot" "btrfs" "subvol=/@,compress=zstd" "")"
  [ "$result" = "cryptdevice=UUID=luks-uuid-5678:cryptroot root=/dev/mapper/cryptroot rootflags=subvol=@" ]
}

@test "resolve_root_cmdline_params omits rootflags=subvol= entirely when the root IS the top-level btrfs subvolume (subvol=/)" {
  result="$(resolve_root_cmdline_params "false" "none" "root-uuid-1234" "" "" "btrfs" "rw,relatime,subvol=/")"
  [ "$result" = "root=UUID=root-uuid-1234" ]
  [[ "$result" != *"rootflags"* ]]
}

@test "resolve_root_cmdline_params does not abort under set -e -o pipefail when the real pvs/blkid defaults are exercised (plain LUKS, pvs unavailable/non-PV)" {
  # Real production entrypoint (xsb-helper) runs under set -euo pipefail.
  # pvs legitimately exits non-zero for a non-PV device (the common plain
  # LUKS case), and blkid can too. Since params 8/9 are left unset here,
  # this exercises the REAL pvs/blkid command-substitution defaults, not
  # injected fakes - proving the split-assignment set -e trap doesn't
  # silently kill cmd_migrate for the common case.
  run bash -c "
    set -euo pipefail
    source '${BATS_TEST_DIRNAME}/../../lib/jsonevent.sh'
    source '${BATS_TEST_DIRNAME}/../../lib/chainload.sh'
    source '${BATS_TEST_DIRNAME}/../../lib/migrate.sh'
    result=\"\$(resolve_root_cmdline_params 'true' 'encrypt' 'root-uuid' \$'cryptroot UUID=luks-uuid-5678 none luks' '/dev/mapper/cryptroot' 'ext4' '')\"
    echo \"ok:[\$result]\"
  "
  [ "$status" -eq 0 ]
  [[ "$output" == "ok:[cryptdevice=UUID=luks-uuid-5678:cryptroot root=/dev/mapper/cryptroot]" ]]
}

@test "resolve_root_cmdline_params does not abort under set -e -o pipefail when a btrfs root's options contain no subvol= (top-level mount)" {
  # Real production entrypoint (xsb-helper) runs under set -euo pipefail.
  # grep -oE 'subvol=...' legitimately exits non-zero when root_options
  # has no subvol= at all (a plausible top-level-btrfs-mount scenario).
  # Proves the fixed subvol_opt line's "no match" case is a handled empty
  # string, not an accidental abort of the whole function.
  #
  # `shopt -s inherit_errexit` is added on top of the prior round's
  # set -e regression test style deliberately: bash's inherit_errexit is
  # OFF by default, and resolve_root_cmdline_params is always invoked via
  # a `$(...)` command substitution in real call sites (see cmd_migrate) -
  # meaning that WITHOUT inherit_errexit, an internal split-assignment
  # abort is silently swallowed by the command-substitution boundary and
  # this test would pass even against the unfixed, buggy code (verified
  # by hand: it does). Enabling inherit_errexit makes -e propagate into
  # the substitution the way a defensively-written production script
  # should, so this test genuinely fails against the bug and genuinely
  # passes against the fix.
  run bash -c "
    set -euo pipefail
    shopt -s inherit_errexit
    source '${BATS_TEST_DIRNAME}/../../lib/jsonevent.sh'
    source '${BATS_TEST_DIRNAME}/../../lib/chainload.sh'
    source '${BATS_TEST_DIRNAME}/../../lib/migrate.sh'
    result=\"\$(resolve_root_cmdline_params 'false' 'none' 'root-uuid-1234' '' '' 'btrfs' 'rw,relatime')\"
    echo \"ok:[\$result]\"
  "
  [ "$status" -eq 0 ]
  [[ "$output" == "ok:[root=UUID=root-uuid-1234]" ]]
}

@test "resolve_grub_extra_params extracts GRUB_CMDLINE_LINUX_DEFAULT value, ignoring unrelated lines" {
  grub_content=$'GRUB_DEFAULT=0\nGRUB_TIMEOUT=5\nGRUB_CMDLINE_LINUX_DEFAULT="quiet nowatchdog loglevel=3 modprobe.blacklist=nouveau"\nGRUB_CMDLINE_LINUX=""'
  result="$(resolve_grub_extra_params "$grub_content")"
  [ "$result" = "quiet nowatchdog loglevel=3 modprobe.blacklist=nouveau" ]
}

@test "resolve_grub_extra_params handles a single-quoted GRUB_CMDLINE_LINUX_DEFAULT value" {
  grub_content="GRUB_CMDLINE_LINUX_DEFAULT='quiet mitigations=off'"
  result="$(resolve_grub_extra_params "$grub_content")"
  [ "$result" = "quiet mitigations=off" ]
}

@test "resolve_grub_extra_params falls back to the stock string when GRUB_CMDLINE_LINUX_DEFAULT is absent" {
  grub_content=$'GRUB_DEFAULT=0\nGRUB_TIMEOUT=5'
  result="$(resolve_grub_extra_params "$grub_content")"
  [ "$result" = "quiet nowatchdog loglevel=3" ]
}

@test "resolve_grub_extra_params falls back to the stock string when GRUB_CMDLINE_LINUX_DEFAULT is present but empty" {
  grub_content='GRUB_CMDLINE_LINUX_DEFAULT=""'
  result="$(resolve_grub_extra_params "$grub_content")"
  [ "$result" = "quiet nowatchdog loglevel=3" ]
}

@test "resolve_grub_extra_params uses the last GRUB_CMDLINE_LINUX_DEFAULT line when multiple are present" {
  grub_content=$'GRUB_CMDLINE_LINUX_DEFAULT="first value"\nGRUB_CMDLINE_LINUX_DEFAULT="second value"'
  result="$(resolve_grub_extra_params "$grub_content")"
  [ "$result" = "second value" ]
}

@test "build_limine_defaults_content includes the resolved grub extra params and root cmdline params" {
  result="$(build_limine_defaults_content "root=UUID=root-uuid-1234" "quiet loglevel=3 modprobe.blacklist=nouveau")"
  [[ "$result" == *"KERNEL_CMDLINE[default]="* ]]
  [[ "$result" == *"quiet loglevel=3 modprobe.blacklist=nouveau"* ]]
  [[ "$result" == *"root=UUID=root-uuid-1234"* ]]
  [[ "$result" != *"nowatchdog"* ]]
}

@test "write_limine_defaults writes build_limine_defaults_content output including custom grub extra params to the given path" {
  target="$BATS_TEST_TMPDIR/limine-defaults"
  write_limine_defaults "$target" "root=UUID=root-uuid-1234" "quiet loglevel=3 modprobe.blacklist=nouveau"
  grep -q "root=UUID=root-uuid-1234" "$target"
  grep -q "modprobe.blacklist=nouveau" "$target"
  grep -q "KERNEL_CMDLINE\[default\]=" "$target"
}

@test "write_limine_defaults falls back to the stock grub extra params when the third argument is omitted" {
  target="$BATS_TEST_TMPDIR/limine-defaults"
  write_limine_defaults "$target" "root=UUID=root-uuid-1234"
  grep -q "quiet nowatchdog loglevel=3" "$target"
  grep -q "root=UUID=root-uuid-1234" "$target"
}

@test "write_limine_defaults previews without writing when DRY_RUN=1" {
  target="$BATS_TEST_TMPDIR/does-not-exist-dir/limine-defaults"
  DRY_RUN=1
  result="$(write_limine_defaults "$target" "root=UUID=root-uuid-1234")"
  [[ "$result" == *"would_run"* ]]
  [ ! -e "$target" ]
}

@test "find_grub_efi_bootnum matches by real loader path, not by an assumed XeroLinux label" {
  # Regression: the original installer almost never labels GRUB's own NVRAM
  # entry "XeroLinux" - it's whatever bootloader-id THAT installer used
  # (here "opensuse"). A fixed-label match would silently find nothing.
  efibootmgr_output=$'BootCurrent: 0001\nBootOrder: 0000,0001\nBoot0000* opensuse-secureboot\tHD(1,GPT,aaaa,0x800,0x100000)/File(\\EFI\\opensuse\\grubx64.efi)\nBoot0001* XeroLinux\tHD(1,GPT,aaaa,0x800,0x100000)/File(\\EFI\\XeroLinux\\BOOTX64.EFI)'
  result="$(find_grub_efi_bootnum "$efibootmgr_output" $'/EFI/opensuse/grubx64.efi')"
  [ "$result" = "0000" ]
}

@test "find_grub_efi_bootnum does not match an unrelated OS's GRUB entry not found on this ESP" {
  # Safety check: a bare "any grubx64.efi" match (the naive alternative fix)
  # would delete a different OS's unrelated GRUB entry in a dual-boot setup.
  # Only paths remove_grub actually found on THIS system's ESP are passed in,
  # so an entry pointing elsewhere must never match.
  efibootmgr_output=$'Boot0000* ubuntu\tHD(2,GPT,bbbb,0x800,0x100000)/File(\\EFI\\ubuntu\\grubx64.efi)\nBoot0001* XeroLinux\tHD(1,GPT,aaaa,0x800,0x100000)/File(\\EFI\\XeroLinux\\BOOTX64.EFI)'
  result="$(find_grub_efi_bootnum "$efibootmgr_output" $'/EFI/opensuse/grubx64.efi')"
  [ -z "$result" ]
}

@test "find_grub_efi_bootnum returns empty when no grub_efi_paths are given" {
  efibootmgr_output=$'Boot0000* opensuse\tHD(1,GPT,aaaa,0x800,0x100000)/File(\\EFI\\opensuse\\grubx64.efi)'
  result="$(find_grub_efi_bootnum "$efibootmgr_output" "")"
  [ -z "$result" ]
}

@test "find_grub_efi_bootnum exits 0 even when nothing is found (safe under set -e pipefail)" {
  efibootmgr_output=$'Boot0001* XeroLinux\tHD(1,GPT,aaaa,0x800,0x100000)/File(\\EFI\\XeroLinux\\BOOTX64.EFI)'
  run find_grub_efi_bootnum "$efibootmgr_output" $'/EFI/opensuse/grubx64.efi'
  [ "$status" -eq 0 ]
}

@test "find_grub_efi_bootnum does not abort under set -e -o pipefail when no GRUB entry is found" {
  run bash -c "
    set -euo pipefail
    source '${BATS_TEST_DIRNAME}/../../lib/jsonevent.sh'
    source '${BATS_TEST_DIRNAME}/../../lib/migrate.sh'
    efibootmgr_output=\$'Boot0001* XeroLinux\tHD(1,GPT,aaaa,0x800,0x100000)/File(\\\\EFI\\\\XeroLinux\\\\BOOTX64.EFI)'
    grub_bootnum=\"\$(find_grub_efi_bootnum \"\$efibootmgr_output\" \$'/EFI/opensuse/grubx64.efi')\"
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
  [[ "$result" == *"remove leftover GRUB EFI files"* ]]
  [[ "$result" == *"/usr/bin/efibootmgr -b 0000 -B"* ]]
}

@test "remove_grub does not attempt to delete an EFI entry when none is found" {
  DRY_RUN=1
  find_grub_efi_bootnum() { echo ""; }
  result="$(remove_grub)"
  [[ "$result" != *"/usr/bin/efibootmgr -b"* ]]
}

@test "remove_grub only removes packages that are actually installed (not the full hardcoded candidate list)" {
  DRY_RUN=0
  find_grub_efi_bootnum() { echo ""; }
  run_cmd() { echo "RUN_CMD: $*"; }
  result="$(remove_grub "$BATS_TEST_TMPDIR/esp" $'grub\ngrub-hooks')"
  [[ "$result" == *"RUN_CMD: /usr/bin/pacman -Rns --noconfirm grub grub-hooks"* ]]
  [[ "$result" != *"update-grub"* ]]
  [[ "$result" != *"os-prober"* ]]
}

@test "remove_grub skips pacman entirely when none of the candidate packages are installed" {
  DRY_RUN=0
  find_grub_efi_bootnum() { echo ""; }
  run_cmd() { echo "RUN_CMD: $*"; }
  result="$(remove_grub "$BATS_TEST_TMPDIR/esp" "")"
  [[ "$result" != *"pacman"* ]]
  [[ "$result" == *"RUN_CMD: /usr/bin/rm -rf /boot/grub"* ]]
}

@test "remove_grub returns failure when pacman fails to remove installed GRUB packages" {
  DRY_RUN=0
  find_grub_efi_bootnum() { echo ""; }
  run_cmd() {
    [[ "$1" == "/usr/bin/pacman" ]] && return 1
    return 0
  }
  run remove_grub "$BATS_TEST_TMPDIR/esp" $'grub\ngrub-hooks'
  [ "$status" -ne 0 ]
}

@test "remove_grub finds and removes GRUB's real NVRAM entry end-to-end, without stubbing find_grub_efi_bootnum" {
  # Regression test for the "XeroLinux label" bug: this GRUB entry is
  # labeled per its own original installer's bootloader-id ("opensuse"),
  # never "XeroLinux" - proving the fix finds it by real loader path.
  DRY_RUN=0
  esp="$BATS_TEST_TMPDIR/esp"
  mkdir -p "$esp/EFI/opensuse"
  : > "$esp/EFI/opensuse/grubx64.efi"
  efibootmgr() {
    if [[ "$1" == "-v" ]]; then
      printf 'Boot0000* opensuse-secureboot\tHD(1,GPT,aaaa,0x800,0x100000)/File(\\EFI\\opensuse\\grubx64.efi)\n'
    fi
  }
  run_cmd() {
    if [[ "$1" == "/usr/bin/efibootmgr" ]]; then
      echo "RUN_CMD: $*"
      return 0
    fi
    return 0
  }
  export -f efibootmgr
  result="$(remove_grub "$esp" "")"
  [[ "$result" == *"RUN_CMD: /usr/bin/efibootmgr -b 0000 -B"* ]]
}

@test "remove_grub_efi_leftovers deletes grub*.efi files under ESP EFI dirs regardless of bootloader-id directory name" {
  DRY_RUN=0
  esp="$BATS_TEST_TMPDIR/esp"
  mkdir -p "$esp/EFI/some-random-bootloader-id" "$esp/EFI/XeroLinux"
  : > "$esp/EFI/some-random-bootloader-id/grubx64.efi"
  : > "$esp/EFI/XeroLinux/BOOTX64.EFI"
  result="$(remove_grub_efi_leftovers "$esp")"
  [[ "$result" == *"/usr/bin/rm -f $esp/EFI/some-random-bootloader-id/grubx64.efi"* ]]
  [[ "$result" != *"BOOTX64.EFI"* ]]
}

@test "remove_grub_efi_leftovers deletes leftover grub.cfg anywhere under the ESP" {
  DRY_RUN=0
  esp="$BATS_TEST_TMPDIR/esp2"
  mkdir -p "$esp/EFI/some-random-bootloader-id"
  : > "$esp/EFI/some-random-bootloader-id/grub.cfg"
  result="$(remove_grub_efi_leftovers "$esp")"
  [[ "$result" == *"/usr/bin/rm -f $esp/EFI/some-random-bootloader-id/grub.cfg"* ]]
}

@test "remove_grub_efi_leftovers does nothing when the ESP has no GRUB leftovers" {
  DRY_RUN=0
  esp="$BATS_TEST_TMPDIR/esp3"
  mkdir -p "$esp/EFI/XeroLinux"
  : > "$esp/EFI/XeroLinux/BOOTX64.EFI"
  result="$(remove_grub_efi_leftovers "$esp")"
  [ -z "$result" ]
}

@test "remove_grub_efi_leftovers does not touch the filesystem under DRY_RUN" {
  DRY_RUN=1
  esp="$BATS_TEST_TMPDIR/esp4"
  mkdir -p "$esp/EFI/grub"
  : > "$esp/EFI/grub/grubx64.efi"
  result="$(remove_grub_efi_leftovers "$esp")"
  [[ "$result" == *"would_run"* ]]
  [ -f "$esp/EFI/grub/grubx64.efi" ]
}

@test "write_limine_conf appends chainload stanzas to the given path without clobbering it" {
  target="$BATS_TEST_TMPDIR/limine.conf"
  printf 'timeout: 5\ndefault_entry: 1\n' > "$target"
  write_limine_conf "$target" "Windows Boot Manager"
  grep -q "timeout: 5" "$target"
  grep -q "/Windows Boot Manager" "$target"
}

@test "write_limine_conf adds no chainload block when there is no other OS" {
  target="$BATS_TEST_TMPDIR/limine.conf"
  printf 'timeout: 5\ndefault_entry: 1\n' > "$target"
  write_limine_conf "$target" ""
  content="$(cat "$target")"
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

@test "build_limine_splash_header emits the wallpaper-only theme block" {
  result="$(build_limine_splash_header)"
  [[ "$result" == *"### Theme"* ]]
  [[ "$result" == *"wallpaper: boot():/splash.png"* ]]
}

@test "write_limine_splash prepends the splash header when no existing theme section is present" {
  target="$BATS_TEST_TMPDIR/limine.conf"
  printf 'timeout: 5\ndefault_entry: 1\n\n/XeroLinux\n    protocol: linux\n' > "$target"
  write_limine_splash "$target"
  content="$(cat "$target")"
  [[ "$content" == *"### Theme"* ]]
  [[ "$content" == *"wallpaper: boot():/splash.png"* ]]
  [[ "$content" == *"timeout: 5"* ]]
  [[ "$content" == *"/XeroLinux"* ]]
  [[ "$content" == *"protocol: linux"* ]]
  count="$(grep -c '^### Theme$' "$target")"
  [ "$count" -eq 1 ]
  [ "$(head -1 "$target")" = "### Theme" ]
}

@test "write_limine_splash replaces an existing old palette-style theme section with the wallpaper-only header, leaving no leftover palette lines" {
  target="$BATS_TEST_TMPDIR/limine.conf"
  printf '### Theme\nterm_palette: 232136;eb6f92;9ccfd8;f6c177;3e8fb0;c4a7e7;9ccfd8;e0def4\nterm_background: 00232136\nterm_foreground: e0def4\n\ntimeout: 5\ndefault_entry: 1\n\n/XeroLinux\n    protocol: linux\n\n/Windows Boot Manager\n    protocol: efi_chainload\n' > "$target"
  write_limine_splash "$target"
  content="$(cat "$target")"
  [[ "$content" == *"### Theme"* ]]
  [[ "$content" == *"wallpaper: boot():/splash.png"* ]]
  [[ "$content" != *"term_palette"* ]]
  [[ "$content" != *"term_background"* ]]
  [[ "$content" != *"term_foreground"* ]]
  count="$(grep -c '^### Theme$' "$target")"
  [ "$count" -eq 1 ]
  [[ "$content" == *"timeout: 5"* ]]
  [[ "$content" == *"/XeroLinux"* ]]
  [[ "$content" == *"protocol: linux"* ]]
  [[ "$content" == *"/Windows Boot Manager"* ]]
  [[ "$content" == *"protocol: efi_chainload"* ]]
}

@test "write_limine_splash preserves the original file's permission bits" {
  target="$BATS_TEST_TMPDIR/limine.conf"
  printf 'timeout: 5\ndefault_entry: 1\n' > "$target"
  chmod 644 "$target"
  write_limine_splash "$target"
  mode="$(stat -c '%a' "$target")"
  [ "$mode" = "644" ]
}

@test "write_limine_splash previews without writing when DRY_RUN=1" {
  target="$BATS_TEST_TMPDIR/limine.conf"
  printf 'timeout: 5\ndefault_entry: 1\n' > "$target"
  DRY_RUN=1
  result="$(write_limine_splash "$target")"
  [[ "$result" == *"would_run"* ]]
  content="$(cat "$target")"
  [[ "$content" != *"### Theme"* ]]
  [[ "$content" == "timeout: 5"$'\n'"default_entry: 1" ]]
}

@test "verify_wallpaper_source_exists true when the wallpaper file is present" {
  wallpaper="$BATS_TEST_TMPDIR/Xero-Plasma4.png"
  : > "$wallpaper"
  run verify_wallpaper_source_exists "$wallpaper"
  [ "$status" -eq 0 ]
}

@test "verify_wallpaper_source_exists false when the wallpaper file is absent" {
  run verify_wallpaper_source_exists "$BATS_TEST_TMPDIR/does-not-exist.png"
  [ "$status" -eq 1 ]
}

stub_cmd_migrate_happy_path() {
  detect_bootloader() { echo "grub"; }
  detect_secureboot_state() { echo "disabled"; }
  find_esp_mountpoint() { echo "/boot/efi"; return 0; }
  detect_other_os() { echo ""; }
  detect_luks_root() { return 1; }
  detect_mkinitcpio_hook_family() { echo "none"; }
  findmnt() { echo "root-uuid-1234"; }
  resolve_grub_extra_params() { echo "quiet nowatchdog loglevel=3"; }
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

@test "cmd_migrate runs a post-migration boot doctor check and includes it in the output" {
  # detect_bootloader stays "grub" throughout (stub_cmd_migrate_happy_path's
  # own value) since cmd_migrate itself requires it at entry - this only
  # needs to prove the doctor check's output is wired into migrate's own
  # output stream, not simulate a fully realistic post-migration state.
  stub_cmd_migrate_happy_path
  is_uefi() { return 0; }
  detect_partition_table() { return 0; }
  efibootmgr() { printf 'Boot0000* XeroLinux\tHD(1,GPT,aaaa,0x800,0x100000)/File(\\EFI\\XeroLinux\\BOOTX64.EFI)\n'; }
  export -f efibootmgr
  DRY_RUN=1
  run cmd_migrate
  [ "$status" -eq 0 ]
  [[ "$output" == *"doctor_check"* ]]
  [[ "$output" == *"doctor_done"* ]]
  [[ "$output" == *"migrate_done"* ]]
}

@test "cmd_migrate still reports success even when the post-migration doctor check finds a problem" {
  stub_cmd_migrate_happy_path
  run_boot_doctor_checks() { emit_event "doctor_done" "error" "simulated doctor failure"; return 1; }
  DRY_RUN=1
  run cmd_migrate
  [ "$status" -eq 0 ]
  [[ "$output" == *"simulated doctor failure"* ]]
  [[ "$output" == *"migrate_done"* ]]
}

@test "cmd_migrate resolves the EFI disk/partition from the REAL discovered ESP mountpoint, not a hardcoded /boot/efi default" {
  stub_cmd_migrate_happy_path
  find_esp_mountpoint() { echo "/efi"; return 0; }
  findmnt() {
    if [[ "$*" == *"SOURCE /efi"* ]]; then
      echo "/dev/vdb1"
      return 0
    fi
    echo "root-uuid-1234"
  }
  captured_source_file="$BATS_TEST_TMPDIR/captured_esp_source"
  resolve_esp_disk_and_part() {
    echo "$1" > "$captured_source_file"
    echo "/dev/vdb 1"
  }
  DRY_RUN=1
  run cmd_migrate
  [ "$status" -eq 0 ]
  [ "$(cat "$captured_source_file")" = "/dev/vdb1" ]
}

@test "cmd_migrate passes the user's real GRUB_CMDLINE_LINUX_DEFAULT customizations through to the final /etc/default/limine content" {
  stub_cmd_migrate_happy_path
  resolve_grub_extra_params() { echo "quiet loglevel=3 modprobe.blacklist=nouveau"; }
  captured_file="$BATS_TEST_TMPDIR/captured_limine_defaults_content"
  write_limine_defaults() {
    build_limine_defaults_content "$2" "$3" > "$captured_file"
  }
  DRY_RUN=1
  run cmd_migrate
  [ "$status" -eq 0 ]
  grep -q "modprobe.blacklist=nouveau" "$captured_file"
  grep -q "root=UUID=root-uuid-1234" "$captured_file"
  ! grep -q "quiet nowatchdog loglevel=3" "$captured_file"
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

@test "cmd_migrate reports a clear error instead of dying silently when remove_grub fails" {
  stub_cmd_migrate_happy_path
  remove_grub() { return 1; }
  DRY_RUN=1
  run cmd_migrate
  [ "$status" -ne 0 ]
  [[ "$output" == *'"event":"error"'* ]]
  [[ "$output" == *"Failed to remove GRUB"* ]]
  [[ "$output" != *"migrate_done"* ]]
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

@test "cmd_apply_splash refuses when Limine is not the active bootloader" {
  detect_bootloader() { echo "grub"; }
  find_esp_mountpoint() { echo "SHOULD_NOT_BE_CALLED"; return 0; }
  write_limine_splash() { echo "SHOULD_NOT_BE_CALLED"; }
  run cmd_apply_splash
  [ "$status" -ne 0 ]
  [[ "$output" == *'"event":"error"'* ]]
  [[ "$output" != *"SHOULD_NOT_BE_CALLED"* ]]
}

@test "cmd_apply_splash refuses when no EFI system partition is found" {
  detect_bootloader() { echo "limine"; }
  find_esp_mountpoint() { return 1; }
  write_limine_splash() { echo "SHOULD_NOT_BE_CALLED"; }
  run cmd_apply_splash
  [ "$status" -ne 0 ]
  [[ "$output" == *'"event":"error"'* ]]
  [[ "$output" != *"SHOULD_NOT_BE_CALLED"* ]]
}

@test "cmd_apply_splash refuses when limine.conf does not exist at the ESP mountpoint" {
  detect_bootloader() { echo "limine"; }
  find_esp_mountpoint() { echo "$BATS_TEST_TMPDIR"; return 0; }
  write_limine_splash() { echo "SHOULD_NOT_BE_CALLED"; }
  run cmd_apply_splash
  [ "$status" -ne 0 ]
  [[ "$output" == *'"event":"error"'* ]]
  [[ "$output" != *"SHOULD_NOT_BE_CALLED"* ]]
}

@test "cmd_apply_splash refuses when the XeroLinux wallpaper source file is missing" {
  detect_bootloader() { echo "limine"; }
  find_esp_mountpoint() { echo "$BATS_TEST_TMPDIR"; return 0; }
  : > "$BATS_TEST_TMPDIR/limine.conf"
  verify_wallpaper_source_exists() { return 1; }
  run_cmd() { echo "SHOULD_NOT_BE_CALLED"; }
  write_limine_splash() { echo "SHOULD_NOT_BE_CALLED"; }
  run cmd_apply_splash
  [ "$status" -ne 0 ]
  [[ "$output" == *'"event":"error"'* ]]
  [[ "$output" != *"SHOULD_NOT_BE_CALLED"* ]]
}

@test "cmd_apply_splash copies the wallpaper to the ESP and writes the splash header on success" {
  detect_bootloader() { echo "limine"; }
  find_esp_mountpoint() { echo "$BATS_TEST_TMPDIR"; return 0; }
  : > "$BATS_TEST_TMPDIR/limine.conf"
  verify_wallpaper_source_exists() { return 0; }
  run_cmd_args_file="$BATS_TEST_TMPDIR/run_cmd_args"
  run_cmd() { printf '%s\n' "$*" >> "$run_cmd_args_file"; }
  write_limine_splash_args_file="$BATS_TEST_TMPDIR/write_limine_splash_args"
  write_limine_splash() { printf '%s\n' "$1" > "$write_limine_splash_args_file"; }
  run cmd_apply_splash
  [ "$status" -eq 0 ]
  [[ "$output" == *"apply_splash_done"* ]]
  grep -q "/usr/bin/cp /usr/share/wallpapers/Xero-Plasma4.png $BATS_TEST_TMPDIR/splash.png" "$run_cmd_args_file"
  [ "$(cat "$write_limine_splash_args_file")" = "$BATS_TEST_TMPDIR/limine.conf" ]
}

# --- Post-migration cleanup ---

@test "cleanup_orphaned_esp_kernels keeps referenced kernels and removes unreferenced ones" {
  esp="$BATS_TEST_TMPDIR/esp"
  mid=b7c2a46f0a084a7d89b7f96a4784b975
  old=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
  mkdir -p "$esp/$mid/linux" "$esp/$old/linux"
  echo k > "$esp/$mid/linux/vmlinuz-linux"
  echo i > "$esp/$mid/linux/initramfs-linux"
  echo oldk > "$esp/$old/linux/vmlinuz-linux"
  {
    echo "    module_path: boot():/$mid/linux/initramfs-linux#abc"
    echo "    path: boot():/$mid/linux/vmlinuz-linux#def"
  } > "$esp/limine.conf"
  run cleanup_orphaned_esp_kernels "$esp"
  [ "$status" -eq 0 ]
  [ -f "$esp/$mid/linux/vmlinuz-linux" ]
  [ -f "$esp/$mid/linux/initramfs-linux" ]
  [ ! -e "$esp/$old/linux/vmlinuz-linux" ]
  [ ! -d "$esp/$old" ]
}

@test "cleanup_orphaned_esp_kernels SAFETY: deletes nothing when limine.conf references no kernels" {
  esp="$BATS_TEST_TMPDIR/esp"
  mid=b7c2a46f0a084a7d89b7f96a4784b975
  mkdir -p "$esp/$mid/linux"
  echo k > "$esp/$mid/linux/vmlinuz-linux"
  echo "# no path lines here" > "$esp/limine.conf"
  run cleanup_orphaned_esp_kernels "$esp"
  [ "$status" -eq 0 ]
  [ -f "$esp/$mid/linux/vmlinuz-linux" ]
  [[ "$output" == *"Skipping ESP kernel prune"* ]]
}

@test "cleanup_orphaned_esp_kernels ignores non machine-id dirs (EFI, loader)" {
  esp="$BATS_TEST_TMPDIR/esp"
  mid=b7c2a46f0a084a7d89b7f96a4784b975
  mkdir -p "$esp/$mid/linux" "$esp/EFI/limine" "$esp/loader"
  echo k > "$esp/$mid/linux/vmlinuz-linux"
  echo x > "$esp/EFI/limine/limine_x64.efi"
  echo r > "$esp/loader/random-seed"
  printf '    path: boot():/%s/linux/vmlinuz-linux#h\n' "$mid" > "$esp/limine.conf"
  run cleanup_orphaned_esp_kernels "$esp"
  [ "$status" -eq 0 ]
  [ -f "$esp/EFI/limine/limine_x64.efi" ]
  [ -f "$esp/loader/random-seed" ]
}

@test "cleanup_orphaned_esp_kernels previews without deleting under DRY_RUN" {
  esp="$BATS_TEST_TMPDIR/esp"
  mid=b7c2a46f0a084a7d89b7f96a4784b975
  old=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
  mkdir -p "$esp/$mid/linux" "$esp/$old/linux"
  echo k > "$esp/$mid/linux/vmlinuz-linux"
  echo oldk > "$esp/$old/linux/vmlinuz-linux"
  printf '    path: boot():/%s/linux/vmlinuz-linux#h\n' "$mid" > "$esp/limine.conf"
  DRY_RUN=1
  run cleanup_orphaned_esp_kernels "$esp"
  [ "$status" -eq 0 ]
  [[ "$output" == *"would_run"* ]]
  [[ "$output" == *"rm -f $esp/$old/linux/vmlinuz-linux"* ]]
  [ -f "$esp/$old/linux/vmlinuz-linux" ]
}

@test "cleanup_bootloader_backups removes limine.conf.old and *.bak but keeps the live binary" {
  esp="$BATS_TEST_TMPDIR/esp"
  mkdir -p "$esp/EFI/limine"
  echo old > "$esp/limine.conf.old"
  echo bak > "$esp/EFI/limine/limine_x64.bak"
  echo keep > "$esp/EFI/limine/limine_x64.efi"
  run cleanup_bootloader_backups "$esp"
  [ "$status" -eq 0 ]
  [ ! -e "$esp/limine.conf.old" ]
  [ ! -e "$esp/EFI/limine/limine_x64.bak" ]
  [ -f "$esp/EFI/limine/limine_x64.efi" ]
}

@test "cleanup_old_bootloader_leftovers removes an unused systemd-boot loader dir" {
  esp="$BATS_TEST_TMPDIR/esp"
  mkdir -p "$esp/loader"
  echo r > "$esp/loader/random-seed"
  run cleanup_old_bootloader_leftovers "$esp"
  [ "$status" -eq 0 ]
  [ ! -d "$esp/loader" ]
}

@test "cleanup_old_bootloader_leftovers SAFETY: keeps loader dir when systemd-boot IS deployed" {
  esp="$BATS_TEST_TMPDIR/esp"
  mkdir -p "$esp/loader" "$esp/EFI/systemd"
  echo r > "$esp/loader/random-seed"
  : > "$esp/EFI/systemd/systemd-bootx64.efi"
  run cleanup_old_bootloader_leftovers "$esp"
  [ "$status" -eq 0 ]
  [ -d "$esp/loader" ]
}

@test "cleanup_old_bootloader_leftovers removes an empty leftover GRUB EFI dir" {
  esp="$BATS_TEST_TMPDIR/esp"
  mkdir -p "$esp/EFI/grub"
  run cleanup_old_bootloader_leftovers "$esp"
  [ "$status" -eq 0 ]
  [ ! -d "$esp/EFI/grub" ]
}

@test "cleanup_after_migrate runs all passes, emits a step event, and returns success" {
  esp="$BATS_TEST_TMPDIR/esp"
  mkdir -p "$esp/EFI/limine"
  echo old > "$esp/limine.conf.old"
  printf '    path: boot():/somewhere#h\n' > "$esp/limine.conf"
  run cleanup_after_migrate "$esp"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Cleaning up leftover boot files"* ]]
  [ ! -e "$esp/limine.conf.old" ]
}

@test "cleanup_orphaned_esp_ukis removes an unreferenced UKI and keeps referenced ones" {
  esp="$BATS_TEST_TMPDIR/esp"
  mkdir -p "$esp/EFI/Linux"
  : > "$esp/EFI/Linux/arch_6.0.efi"
  : > "$esp/EFI/Linux/arch_5.0-orphan.efi"
  printf '    path: boot():/EFI/Linux/arch_6.0.efi#h\n' > "$esp/limine.conf"
  run cleanup_orphaned_esp_ukis "$esp"
  [ "$status" -eq 0 ]
  [ -f "$esp/EFI/Linux/arch_6.0.efi" ]
  [ ! -e "$esp/EFI/Linux/arch_5.0-orphan.efi" ]
}

@test "cleanup_orphaned_esp_ukis SAFETY: deletes nothing when limine.conf references no EFI/Linux UKI" {
  esp="$BATS_TEST_TMPDIR/esp"
  mkdir -p "$esp/EFI/Linux"
  : > "$esp/EFI/Linux/arch_6.0.efi"
  printf '    path: boot():/somewhere/vmlinuz-linux#h\n' > "$esp/limine.conf"
  run cleanup_orphaned_esp_ukis "$esp"
  [ "$status" -eq 0 ]
  [ -f "$esp/EFI/Linux/arch_6.0.efi" ]
  [[ "$output" == *"Skipping UKI prune"* ]]
}

@test "cleanup_orphaned_esp_ukis is a no-op when there is no EFI/Linux dir" {
  esp="$BATS_TEST_TMPDIR/esp"
  mkdir -p "$esp"
  printf '    path: boot():/EFI/Linux/x.efi#h\n' > "$esp/limine.conf"
  run cleanup_orphaned_esp_ukis "$esp"
  [ "$status" -eq 0 ]
}

@test "cleanup_orphaned_esp_ukis previews without deleting under DRY_RUN" {
  esp="$BATS_TEST_TMPDIR/esp"
  mkdir -p "$esp/EFI/Linux"
  : > "$esp/EFI/Linux/arch_6.0.efi"
  : > "$esp/EFI/Linux/orphan.efi"
  printf '    path: boot():/EFI/Linux/arch_6.0.efi#h\n' > "$esp/limine.conf"
  DRY_RUN=1
  run cleanup_orphaned_esp_ukis "$esp"
  [ "$status" -eq 0 ]
  [[ "$output" == *"rm -f $esp/EFI/Linux/orphan.efi"* ]]
  [ -f "$esp/EFI/Linux/orphan.efi" ]
}

@test "cmd_cleanup refuses when Limine is not the active bootloader" {
  detect_bootloader() { echo "grub"; }
  run cmd_cleanup
  [ "$status" -ne 0 ]
  [[ "$output" == *"Limine is not the active bootloader"* ]]
}

@test "cmd_cleanup refuses when limine.conf is missing" {
  detect_bootloader() { echo "limine"; }
  find_esp_mountpoint() { echo "$BATS_TEST_TMPDIR/esp"; }
  mkdir -p "$BATS_TEST_TMPDIR/esp"
  run cmd_cleanup
  [ "$status" -ne 0 ]
  [[ "$output" == *"limine.conf not found"* ]]
}

@test "cmd_cleanup runs the cleanup passes and emits cleanup_done when Limine is active" {
  esp="$BATS_TEST_TMPDIR/esp"
  detect_bootloader() { echo "limine"; }
  find_esp_mountpoint() { echo "$esp"; }
  mkdir -p "$esp/EFI/limine"
  printf '    path: boot():/somewhere#h\n' > "$esp/limine.conf"
  echo old > "$esp/limine.conf.old"
  run cmd_cleanup
  [ "$status" -eq 0 ]
  [[ "$output" == *"Cleaning up leftover boot files"* ]]
  [[ "$output" == *"cleanup_done"* ]]
  [ ! -e "$esp/limine.conf.old" ]
}

@test "cmd_cleanup does not abort under set -e -o pipefail when a cleanup sub-pass's run_cmd fails (regression: missing || true)" {
  # Regression: cmd_migrate's own call to cleanup_after_migrate has
  # `|| true` (needed because several cleanup sub-functions have bare
  # run_cmd calls only safe under suspended errexit - e.g.
  # cleanup_bootloader_backups' `[[ -e X ]] && run_cmd rm -f X`, where
  # run_cmd is the LAST command in that && chain and so is NOT exempt from
  # set -e on its own). This standalone entry point (the "Clean up ESP"
  # button / `cleanup` subcommand) was missing it - a real run_cmd failure
  # here would silently abort the whole helper process under the real
  # entrypoint's `set -euo pipefail`, with no error event and no
  # cleanup_done ever emitted. Sourcing raw functions in bats (without
  # set -e) doesn't exercise this - it must run under real set -e to prove
  # the fix, matching this file's other set -e regression tests.
  esp="$BATS_TEST_TMPDIR/esp"
  mkdir -p "$esp/EFI/limine"
  printf '    path: boot():/somewhere#h\n' > "$esp/limine.conf"
  echo old > "$esp/limine.conf.old"
  run bash -c "
    set -euo pipefail
    source '${BATS_TEST_DIRNAME}/../../lib/jsonevent.sh'
    source '${BATS_TEST_DIRNAME}/../../lib/chainload.sh'
    source '${BATS_TEST_DIRNAME}/../../lib/migrate.sh'
    detect_bootloader() { echo limine; }
    find_esp_mountpoint() { echo '$esp'; }
    run_cmd() {
      [[ \"\$*\" == *'limine.conf.old'* ]] && return 1
      \"\$@\"
    }
    cmd_cleanup
    echo DONE_REACHED
  "
  [ "$status" -eq 0 ]
  [[ "$output" == *"cleanup_done"* ]]
  [[ "$output" == *"DONE_REACHED"* ]]
}
