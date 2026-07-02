#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later

detect_other_os() {
    local efibootmgr_output="${1-$(efibootmgr -v 2>/dev/null)}"
    grep -E '^Boot[0-9A-Fa-f]{4}\*?[[:space:]]' <<< "$efibootmgr_output" \
        | grep -viE 'xerolinux|limine' \
        | grep -viE 'BootManagerMenu|EFI Firmware Setup|UEFI Misc Device|UEFI Shell|Internal Shell|Diagnostic Splash|PXEv4|PXEv6|HTTPv4|HTTPv6|DVD-ROM|CD-ROM' \
        | sed -E 's/^Boot[0-9A-Fa-f]{4}\*?[[:space:]]+//' \
        | sed -E 's/\t.*$//' \
        || true
}

# True (0) if other_os_list (as produced by detect_other_os) contains any
# non-Windows entry. Windows is excluded because it has its own distinct,
# well-known loader path (bootmgfw.efi) already handled separately by
# chainload_loader_path_for_os, so it never relies on the generic EFI
# fallback path. Used by deploy_limine_to_esp's caller to decide whether
# overwriting the generic fallback path is safe.
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
