#!/usr/bin/env bats

setup() {
  source "${BATS_TEST_DIRNAME}/../../lib/chainload.sh"
}

@test "detect_other_os finds Windows Boot Manager and excludes XeroLinux" {
  sample=$'BootCurrent: 0001\nBootOrder: 0000,0001\nBoot0000* XeroLinux\tHD(1,GPT,...)\nBoot0001* Windows Boot Manager\tHD(1,GPT,...)'
  result="$(detect_other_os "$sample")"
  [ "$result" = "Windows Boot Manager" ]
}

@test "detect_other_os returns nothing when only XeroLinux is present" {
  sample=$'BootCurrent: 0000\nBootOrder: 0000\nBoot0000* XeroLinux\tHD(1,GPT,...)'
  result="$(detect_other_os "$sample")"
  [ -z "$result" ]
}

@test "detect_other_os does not abort under set -e -o pipefail when no other OS is found" {
  run bash -c "
    set -euo pipefail
    source '${BATS_TEST_DIRNAME}/../../lib/chainload.sh'
    sample=\$'Boot0000* XeroLinux\tHD(1,GPT,...)'
    other_os=\"\$(detect_other_os \"\$sample\")\"
    echo \"ok:[\$other_os]\"
  "
  [ "$status" -eq 0 ]
  [[ "$output" == "ok:[]" ]]
}

@test "detect_other_os returns nothing for real OVMF firmware pseudo-entries (no real dual-boot)" {
  # Real sample reconstructed from a live XeroLinux VM (OVMF firmware) preflight run.
  sample=$'BootCurrent: 0001\nBootOrder: 0000,0001,0002,0003\nBoot0000* XeroLinux\tHD(1,GPT,...)\nBoot0001* BootManagerMenuApp\nBoot0002* EFI Firmware Setup\tFvVol(7cb8bdc9-f8eb-4f34-aaea-3ee4af6516a1)/FvFile(462caa21-7614-4503-836e-8ab6f4662331)\nBoot0003* UEFI Misc Device\tPciRoot(0x0)/Pci(0x2,0x3)/Pci(0x0,0x0){auto_created_boot_option}'
  result="$(detect_other_os "$sample")"
  [ -z "$result" ]
}

@test "detect_other_os extracts Windows Boot Manager cleanly with a non-HD() device path" {
  sample=$'BootCurrent: 0001\nBootOrder: 0000,0001\nBoot0000* XeroLinux\tHD(1,GPT,...)\nBoot0001* Windows Boot Manager\tVenHw(99e275e7-75a0-4b37-a2e6-c5385e6c00cb)'
  result="$(detect_other_os "$sample")"
  [ "$result" = "Windows Boot Manager" ]
}

@test "has_non_windows_other_os false for empty input" {
  run has_non_windows_other_os ""
  [ "$status" -eq 1 ]
}

@test "has_non_windows_other_os false when only Windows Boot Manager is present" {
  run has_non_windows_other_os "Windows Boot Manager"
  [ "$status" -eq 1 ]
}

@test "has_non_windows_other_os true when a non-Windows OS is present" {
  run has_non_windows_other_os "systemd-boot"
  [ "$status" -eq 0 ]
}

@test "has_non_windows_other_os true when both Windows and a non-Windows OS are present" {
  run has_non_windows_other_os $'Windows Boot Manager\nsystemd-boot'
  [ "$status" -eq 0 ]
}
