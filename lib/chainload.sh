#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later

# Non-OS firmware boot entries to exclude, grouped by CATEGORY rather than
# vendor phrase, so this covers any manufacturer (Lenovo, Dell, HP, ASUS,
# generic desktop BIOS) instead of chasing one vendor's exact wording.
# Real hardware often expands these to include the drive model (e.g.
# "HDD0: <SSD model>") - patterns match the device-class prefix, not the
# full label, so that's still excluded.
_XSB_NON_OS_BOOT_ENTRY_PATTERNS=(
    # Firmware apps / boot manager UI
    'BootManagerMenu' 'Boot Menu' 'Boot Device Menu' 'EFI Firmware Setup'
    'UEFI Misc Device' 'UEFI Shell' 'Internal Shell' 'Enter Setup' 'Setup'
    'CSM' 'Launch CSM' '\<UEFI OS\>'
    # Vendor diagnostics / recovery utilities
    'Diagnostic' 'SupportAssist' 'Hardware Diagnostics'
    # Legacy/generic storage device classes - a device class, not an
    # installed OS, regardless of which drive model firmware appends
    'Diskette' 'Floppy' '\<FDD[0-9]*\>' '\<HDD[0-9]*\>' '\<SSD[0-9]*\>'
    '\<SATA[0-9]*\>' '\<ATA[0-9]*\>' 'ATAPI' '\<IDE\>' '\<NVMe[0-9]*\>'
    '\<eMMC\>' 'CD[- /]?ROM' 'DVD[- /]?ROM' 'Optical Drive'
    'USB (HDD|FDD|CD|DVD|Storage|Flash|Disk|Boot)'
    # Network boot
    '\<NIC\>' 'Network (Adapter|Boot|Card)' 'Onboard NIC' 'PXEv4' 'PXEv6'
    'HTTPv4' 'HTTPv6' 'LAN Boot' 'PCI LAN'
)

# General structural blocker, on top of the label blocklist below: every
# real OS/bootloader boot entry references a disk partition via an HD(...)
# device-path node. Legacy BBS entries, firmware-volume apps, and
# network/PCI-only paths never contain literal "HD(", so requiring it
# excludes most non-OS entries by construction - including vendor wording
# never blocklisted below. Windows Boot Manager is special-cased since
# some firmware exposes it via VenHw(...) instead of HD(). One confirmed
# exception needs an explicit blocklist entry: firmware's own auto-created
# "UEFI OS" fallback placeholder DOES carry a real HD(...) path (the same
# ESP partition XeroLinux itself boots from), so it isn't excluded by
# structure alone.
detect_other_os() {
    local efibootmgr_output="${1-$(efibootmgr -v 2>/dev/null)}"
    local exclude_pattern
    exclude_pattern="$(IFS='|'; printf '%s' "${_XSB_NON_OS_BOOT_ENTRY_PATTERNS[*]}")"
    grep -E '^Boot[0-9A-Fa-f]{4}\*?[[:space:]]' <<< "$efibootmgr_output" \
        | grep -viE 'xerolinux|limine' \
        | grep -viE "$exclude_pattern" \
        | grep -E 'Windows Boot Manager|HD\(' \
        | sed -E 's/^Boot[0-9A-Fa-f]{4}\*?[[:space:]]+//' \
        | sed -E 's/\t.*$//' \
        || true
}

# True if other_os_list contains a non-Windows entry. Windows has its own
# loader path (bootmgfw.efi, handled by chainload_loader_path_for_os) and
# never needs the generic EFI fallback. Used to decide if overwriting that
# fallback path is safe.
has_non_windows_other_os() {
    local other_os_list="$1"
    local os_label
    while IFS= read -r os_label; do
        [[ -z "$os_label" ]] && continue
        case "$os_label" in
            *[Ww]indows*) ;;
            *) return 0 ;;
        esac
    done <<< "$other_os_list"
    return 1
}
