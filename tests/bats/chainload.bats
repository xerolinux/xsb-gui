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

@test "detect_other_os excludes Lenovo legacy device-class and diagnostics entries, real hardware sample" {
  # Reconstructed from a real ThinkPad's efibootmgr -v output: Lenovo
  # firmware lists a legacy BBS boot entry per generic device class plus
  # a vendor diagnostics tool alongside the real OS entries.
  sample=$'BootCurrent: 0001\nBootOrder: 0000,0001,0002,0003,0004,0005,0006\nBoot0000* XeroLinux\tHD(1,GPT,...)\nBoot0001* Windows Boot Manager\tHD(1,GPT,...)\nBoot0002* HDD Boot: ST1000LM035-1RK172\tBBS(HD,,0x0)\nBoot0003* FDD Boot\tBBS(FDD,,0x0)\nBoot0004* USB Boot\tBBS(USB,,0x0)\nBoot0005* USB HDD: Kingston DataTraveler\tBBS(HD,,0x0)\nBoot0006* Lenovo Diagnostics\tFvVol(7cb8bdc9-f8eb-4f34-aaea-3ee4af6516a1)/FvFile(462caa21-7614-4503-836e-8ab6f4662331)'
  result="$(detect_other_os "$sample")"
  [ "$result" = "Windows Boot Manager" ]
}

@test "detect_other_os excludes ATA/IDE/NVMe generic device-class entries" {
  sample=$'BootCurrent: 0000\nBootOrder: 0000,0001,0002,0003\nBoot0000* XeroLinux\tHD(1,GPT,...)\nBoot0001* ATA HDD0: Samsung SSD\tBBS(HD,,0x0)\nBoot0002* IDE HDD: WDC WD10\tBBS(HD,,0x0)\nBoot0003* NVMe0: Samsung 970 EVO\tBBS(HD,,0x0)'
  result="$(detect_other_os "$sample")"
  [ -z "$result" ]
}

@test "detect_other_os excludes a generic HDD device-class entry expanded with the real drive model (no literal 'Boot' in the label)" {
  # On real hardware (unlike QEMU/OVMF) firmware often expands the generic
  # device-class entry to include the actual drive model, e.g. "HDD0: <SSD
  # model>" instead of a fixed "HDD Boot" string.
  sample=$'BootCurrent: 0000\nBootOrder: 0000,0001\nBoot0000* XeroLinux\tHD(1,GPT,...)\nBoot0001* HDD0: Samsung SSD 980 PRO 1TB\tBBS(HD,,0x0)'
  result="$(detect_other_os "$sample")"
  [ -z "$result" ]
}

@test "detect_other_os excludes 'Enter Setup' firmware menu entry" {
  sample=$'BootCurrent: 0000\nBootOrder: 0000,0001\nBoot0000* XeroLinux\tHD(1,GPT,...)\nBoot0001* Enter Setup\tFvVol(...)'
  result="$(detect_other_os "$sample")"
  [ -z "$result" ]
}

@test "detect_other_os excludes generic desktop-vendor (Dell/HP-style) firmware entries, not just Lenovo wording" {
  sample=$'BootCurrent: 0001\nBootOrder: 0000,0001,0002,0003,0004,0005,0006,0007\nBoot0000* XeroLinux\tHD(1,GPT,...)\nBoot0001* Windows Boot Manager\tHD(1,GPT,...)\nBoot0002* Onboard NIC (IPV4)\tPciRoot(0x0)/Pci(0x1c,0x0)\nBoot0003* Onboard NIC (IPV6)\tPciRoot(0x0)/Pci(0x1c,0x0)\nBoot0004* Diskette Drive\tBBS(FDD,,0x0)\nBoot0005* USB Storage Device\tBBS(HD,,0x0)\nBoot0006* SupportAssist OS Recovery\tFvVol(...)\nBoot0007* BIOS Setup\tFvVol(...)'
  result="$(detect_other_os "$sample")"
  [ "$result" = "Windows Boot Manager" ]
}

@test "detect_other_os excludes a made-up, never-blocklisted vendor entry purely because it lacks a real HD() disk reference" {
  # Proves the general structural blocker works independent of the label
  # blocklist: this label matches none of _XSB_NON_OS_BOOT_ENTRY_PATTERNS,
  # simulating a brand new vendor phrase we've never seen before.
  sample=$'BootCurrent: 0000\nBootOrder: 0000,0001\nBoot0000* XeroLinux\tHD(1,GPT,...)\nBoot0001* Acme SuperBoot Wizard 9000\tFvVol(deadbeef-...)/FvFile(cafebabe-...)'
  result="$(detect_other_os "$sample")"
  [ -z "$result" ]
}

@test "detect_other_os still includes an unrecognized OS name as long as it has a real HD() disk reference" {
  # The structural blocker is an ADDITIONAL filter, not a replacement
  # allowlist of known distro names - any real bootloader entry backed by
  # an actual disk partition must still come through untouched.
  sample=$'BootCurrent: 0000\nBootOrder: 0000,0001\nBoot0000* XeroLinux\tHD(1,GPT,...)\nBoot0001* SomeBrandNewDistro\tHD(2,GPT,...)'
  result="$(detect_other_os "$sample")"
  [ "$result" = "SomeBrandNewDistro" ]
}

@test "detect_other_os excludes 'UEFI OS' - firmware's own fake fallback entry, even though it has a real HD() device path" {
  # Real efibootmgr -v output captured live from a dev sandbox: firmware
  # auto-registers a "UEFI OS" entry pointing at the SAME ESP partition and
  # the same generic \EFI\BOOT\BOOTX64.EFI fallback path this tool's own
  # deploy_limine_to_esp manages - not a real second OS. Documented as "a
  # fake OS the firmware creates to prevent wiping other NVRAM boot
  # entries" (Arch Linux forums). It DOES have a real HD() device path
  # (same partition as XeroLinux's own entry), so the general structural
  # blocker alone does not exclude it - this is the one confirmed
  # exception, handled by an explicit label-blocklist entry instead.
  sample=$'BootCurrent: 0006
Timeout: 3 seconds
BootOrder: 0006,0047,0008,000A
Boot0006* xerolinux\tHD(1,GPT,740728ed-ff0c-4bf1-a9fb-a6476f2f760d,0x1000,0x3e8000)/\\EFI\\XEROLINUX\\GRUBX64.EFI
Boot0008* Windows Boot Manager\tHD(1,GPT,4286bc9e-1a7e-479c-a8a0-d5d483df874a,0x800,0x32000)/\\EFI\\MICROSOFT\\BOOT\\BOOTMGFW.EFI
Boot000A* BOOT\tVenHw(99e275e7-75a0-4b37-a2e6-c5385e6c00cb)
Boot0047* UEFI OS\tHD(1,GPT,740728ed-ff0c-4bf1-a9fb-a6476f2f760d,0x1000,0x3e8000)/\\EFI\\BOOT\\BOOTX64.EFI'
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
