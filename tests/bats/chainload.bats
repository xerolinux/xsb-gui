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

@test "detect_other_os returns nothing for real OVMF network-boot and optical-drive firmware entries (no real dual-boot)" {
  # Real sample reconstructed from a live XeroLinux VM (OVMF firmware) preflight run:
  # the Limine boot menu showed bogus "UEFI PXEv4/PXEv6/HTTPv4/HTTPv6 (MAC:...)" and
  # "UEFI QEMU DVD-ROM QM00001" entries alongside XeroLinux.
  sample=$'BootCurrent: 0001\nBootOrder: 0000,0001,0002,0003,0004,0005\nBoot0000* XeroLinux\tHD(1,GPT,...)\nBoot0001* UEFI PXEv4 (MAC:525400123456)\tPciRoot(0x0)/Pci(0x3,0x0)/MAC(525400123456,0)/IPv4(0.0.0.0,0x0,DHCP,0.0.0.0,0.0.0.0,0.0.0.0)\nBoot0002* UEFI PXEv6 (MAC:525400123456)\tPciRoot(0x0)/Pci(0x3,0x0)/MAC(525400123456,0)/IPv6([::],0x0,Static,[::],[::],0)\nBoot0003* UEFI HTTPv4 (MAC:525400123456)\tPciRoot(0x0)/Pci(0x3,0x0)/MAC(525400123456,0)/IPv4(0.0.0.0,0x0,DHCP,0.0.0.0,0.0.0.0,0.0.0.0)/Uri()\nBoot0004* UEFI HTTPv6 (MAC:525400123456)\tPciRoot(0x0)/Pci(0x3,0x0)/MAC(525400123456,0)/IPv6([::],0x0,Static,[::],[::],0)/Uri()\nBoot0005* UEFI QEMU DVD-ROM QM00001\tPciRoot(0x0)/Pci(0x1,0x1)/Ata(1,0,0)'
  result="$(detect_other_os "$sample")"
  [ -z "$result" ]
}

@test "detect_other_os still finds Windows Boot Manager amid a mix of excluded firmware entries" {
  sample=$'BootCurrent: 0001\nBootOrder: 0000,0001,0002,0003,0004,0005,0006\nBoot0000* XeroLinux\tHD(1,GPT,...)\nBoot0001* UEFI PXEv4 (MAC:525400123456)\tPciRoot(0x0)/Pci(0x3,0x0)/MAC(525400123456,0)/IPv4(0.0.0.0,0x0,DHCP,0.0.0.0,0.0.0.0,0.0.0.0)\nBoot0002* UEFI HTTPv6 (MAC:525400123456)\tPciRoot(0x0)/Pci(0x3,0x0)/MAC(525400123456,0)/IPv6([::],0x0,Static,[::],[::],0)/Uri()\nBoot0003* UEFI QEMU DVD-ROM QM00001\tPciRoot(0x0)/Pci(0x1,0x1)/Ata(1,0,0)\nBoot0004* Windows Boot Manager\tHD(1,GPT,...)\nBoot0005* UEFI PXEv6 (MAC:525400123456)\tPciRoot(0x0)/Pci(0x3,0x0)/MAC(525400123456,0)/IPv6([::],0x0,Static,[::],[::],0)\nBoot0006* UEFI HTTPv4 (MAC:525400123456)\tPciRoot(0x0)/Pci(0x3,0x0)/MAC(525400123456,0)/IPv4(0.0.0.0,0x0,DHCP,0.0.0.0,0.0.0.0,0.0.0.0)/Uri()'
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
