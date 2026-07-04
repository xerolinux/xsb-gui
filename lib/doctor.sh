#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
#
# Boot Doctor: read-only, non-destructive consistency checks. Safe to run any
# time regardless of DRY_RUN - nothing here mutates anything. Each
# doctor_check_* function returns "status|message" (status one of ok/warning/
# error) so cmd_doctor and run_boot_doctor_checks can emit and aggregate them
# uniformly. Designed to catch the exact class of bug behind a real incident:
# a stale fallback bootloader binary silently taking priority over a
# correctly-registered NVRAM entry, discovered only after a failed boot.

doctor_check_uefi() {
    if is_uefi "${1-}"; then
        printf 'ok|Booted in UEFI mode.'
    else
        printf 'error|Not booted in UEFI mode. Secure Boot and Limine are unavailable.'
    fi
}

doctor_check_gpt() {
    if detect_partition_table "${1-}"; then
        printf 'ok|Disk uses a GPT partition table.'
    else
        printf 'error|Disk is not using GPT. UEFI requires GPT; BIOS/MBR disks are not supported.'
    fi
}

doctor_check_esp_present() {
    local esp_mountpoint="$1"
    if [[ -n "$esp_mountpoint" ]]; then
        printf 'ok|EFI system partition found at %s.' "$esp_mountpoint"
    else
        printf 'error|No EFI system partition found.'
    fi
}

# Whether the active bootloader has a working NVRAM boot entry. GRUB's own
# entry isn't managed/verified by this tool outside of revert, so its
# presence there is only ever informational, never a failure on its own.
doctor_check_nvram_entry() {
    local bootloader="$1" efibootmgr_output="$2"
    case "$bootloader" in
        limine)
            if verify_limine_entry "$efibootmgr_output"; then
                printf 'ok|Limine is registered in the firmware boot menu (NVRAM).'
            else
                printf 'error|Limine has no NVRAM boot entry. Firmware may be unable to find it without a working fallback path.'
            fi
            ;;
        grub)
            printf 'ok|GRUB is the active bootloader (NVRAM entry not managed by this tool).'
            ;;
        *)
            printf 'warning|No managed bootloader (GRUB or Limine) currently recognized as installed.'
            ;;
    esac
}

doctor_check_limine_deployed() {
    local esp_mountpoint="$1" bootloader="$2"
    if [[ "$bootloader" != "limine" ]]; then
        printf 'ok|Not applicable (Limine is not the active bootloader).'
        return 0
    fi
    if verify_limine_deployed "$esp_mountpoint"; then
        printf 'ok|Limine binary present on the ESP.'
    else
        printf 'error|Limine binary missing from the ESP (EFI/XeroLinux/BOOTX64.EFI).'
    fi
}

doctor_check_kernel_entry() {
    local esp_mountpoint="$1" bootloader="$2"
    if [[ "$bootloader" != "limine" ]]; then
        printf 'ok|Not applicable (Limine is not the active bootloader).'
        return 0
    fi
    if verify_limine_conf_has_kernel_entry "${esp_mountpoint}/limine.conf" "$esp_mountpoint"; then
        printf 'ok|limine.conf references a kernel that actually exists on the ESP.'
    else
        printf 'error|limine.conf has no bootable kernel entry, or the kernel it references is missing from the ESP. The system may not boot.'
    fi
}

# The exact failure pattern behind a real incident: migration writes the
# active bootloader's binary to the generic UEFI fallback path
# (EFI/Boot/BOOTX64.EFI) so firmware can find it even without a working
# NVRAM entry. If that file drifts from whatever bootloader is ACTUALLY
# active (e.g. a stale copy left behind by an incomplete revert), firmware
# that ever falls back to it boots the wrong thing - with no other symptom
# until the next reboot.
doctor_check_fallback_path() {
    local esp_mountpoint="$1" bootloader="$2"
    local fallback="${esp_mountpoint}/EFI/Boot/BOOTX64.EFI"
    if [[ ! -e "$fallback" ]]; then
        printf 'warning|No generic UEFI fallback binary (EFI/Boot/BOOTX64.EFI) present. Some firmware relies on this path when NVRAM entries are missing or invalid.'
        return 0
    fi
    case "$bootloader" in
        limine)
            if [[ -f "${esp_mountpoint}/EFI/XeroLinux/BOOTX64.EFI" ]] && cmp -s "$fallback" "${esp_mountpoint}/EFI/XeroLinux/BOOTX64.EFI" 2>/dev/null; then
                printf 'ok|UEFI fallback binary matches the active Limine install.'
            else
                printf 'warning|UEFI fallback binary (EFI/Boot/BOOTX64.EFI) does not match the active Limine install. If firmware ever uses this path, it may boot a stale or wrong bootloader.'
            fi
            ;;
        grub)
            local real_grub
            real_grub="$(find "${esp_mountpoint}/EFI" -iname 'grubx64.efi' 2>/dev/null | head -1)"
            if [[ -n "$real_grub" ]] && cmp -s "$fallback" "$real_grub" 2>/dev/null; then
                printf 'ok|UEFI fallback binary matches the active GRUB install.'
            else
                printf 'warning|UEFI fallback binary (EFI/Boot/BOOTX64.EFI) does not match GRUB'"'"'s own binary. If this is leftover from a different bootloader, firmware falling back to this path would not boot GRUB.'
            fi
            ;;
        *)
            printf 'warning|A UEFI fallback binary exists at EFI/Boot/BOOTX64.EFI but no managed bootloader is currently recognized as installed.'
            ;;
    esac
}

# fwupd's UEFI capsule updates need DisableShimForSecureBoot=true once
# Secure Boot is active (see configure_fwupd_secureboot in secureboot.sh).
# Purely informational check, never gates anything - fwupd being
# misconfigured doesn't affect whether the system boots.
doctor_check_fwupd_secureboot() {
    local secureboot_state="$1" fwupd_efi="${2-/usr/lib/fwupd/efi/fwupdx64.efi}" fwupd_conf="${3-/etc/fwupd/fwupd.conf}"
    if [[ "$secureboot_state" != "enabled" ]] || [[ ! -f "$fwupd_efi" ]]; then
        printf 'ok|Not applicable (Secure Boot is not active, or fwupd is not installed).'
        return 0
    fi
    if [[ ! -f "${fwupd_efi}.signed" ]]; then
        printf 'warning|fwupd is installed and Secure Boot is active, but %s.signed does not exist yet. Firmware updates via fwupd may fail until enable-secureboot runs.' "$fwupd_efi"
        return 0
    fi
    if grep -qiE '^[[:space:]]*DisableShimForSecureBoot[[:space:]]*=[[:space:]]*true' "$fwupd_conf" 2>/dev/null; then
        printf 'ok|fwupd is signed and configured to trust its own binary under Secure Boot.'
    else
        printf 'warning|fwupd'"'"'s UEFI binary is signed, but DisableShimForSecureBoot is not set in %s. Firmware updates via fwupd will still require shim.' "$fwupd_conf"
    fi
}

# Runs every check and emits one "doctor_check" event per result plus a
# final "doctor_done" summary, returning the worst status seen (0 for
# ok/warning, 1 if any check is "error") so callers can decide whether to
# treat this as a hard failure. Never mutates anything.
run_boot_doctor_checks() {
    local esp_mountpoint bootloader secureboot_state efibootmgr_output
    local worst="ok" name status message entry

    is_uefi || {
        entry="$(doctor_check_uefi)"
        IFS='|' read -r status message <<< "$entry"
        emit_event "doctor_check" "$status" "UEFI mode: $message"
        emit_event "doctor_done" "error" "Boot diagnostics stopped early: not booted in UEFI mode."
        return 1
    }
    emit_event "doctor_check" "ok" "UEFI mode: Booted in UEFI mode."

    entry="$(doctor_check_gpt)"
    IFS='|' read -r status message <<< "$entry"
    emit_event "doctor_check" "$status" "Partition table: $message"
    [[ "$status" == "error" ]] && worst="error"

    esp_mountpoint="$(find_esp_mountpoint)" || esp_mountpoint=""
    entry="$(doctor_check_esp_present "$esp_mountpoint")"
    IFS='|' read -r status message <<< "$entry"
    emit_event "doctor_check" "$status" "EFI system partition: $message"
    if [[ "$status" == "error" ]]; then
        emit_event "doctor_done" "error" "Boot diagnostics stopped early: no EFI system partition found."
        return 1
    fi

    bootloader="$(detect_bootloader)"
    efibootmgr_output="$(efibootmgr -v 2>/dev/null)"

    entry="$(doctor_check_nvram_entry "$bootloader" "$efibootmgr_output")"
    IFS='|' read -r status message <<< "$entry"
    emit_event "doctor_check" "$status" "Firmware boot entry ($bootloader): $message"
    [[ "$status" == "error" ]] && worst="error"
    [[ "$status" == "warning" && "$worst" == "ok" ]] && worst="warning"

    entry="$(doctor_check_limine_deployed "$esp_mountpoint" "$bootloader")"
    IFS='|' read -r status message <<< "$entry"
    emit_event "doctor_check" "$status" "Limine deployment: $message"
    [[ "$status" == "error" ]] && worst="error"

    entry="$(doctor_check_kernel_entry "$esp_mountpoint" "$bootloader")"
    IFS='|' read -r status message <<< "$entry"
    emit_event "doctor_check" "$status" "Bootable kernel: $message"
    [[ "$status" == "error" ]] && worst="error"

    entry="$(doctor_check_fallback_path "$esp_mountpoint" "$bootloader")"
    IFS='|' read -r status message <<< "$entry"
    emit_event "doctor_check" "$status" "UEFI fallback path: $message"
    [[ "$status" == "error" ]] && worst="error"
    [[ "$status" == "warning" && "$worst" == "ok" ]] && worst="warning"

    secureboot_state="$(detect_secureboot_state)"
    emit_event "doctor_check" "ok" "Secure Boot firmware state: ${secureboot_state}."

    entry="$(doctor_check_fwupd_secureboot "$secureboot_state")"
    IFS='|' read -r status message <<< "$entry"
    emit_event "doctor_check" "$status" "fwupd Secure Boot config: $message"
    [[ "$status" == "warning" && "$worst" == "ok" ]] && worst="warning"

    case "$worst" in
        ok) emit_event "doctor_done" "ok" "Boot diagnostics complete: no issues found." ;;
        warning) emit_event "doctor_done" "warning" "Boot diagnostics complete: potential issues found, review above." ;;
        error) emit_event "doctor_done" "error" "Boot diagnostics complete: real problems found, review above." ;;
    esac
    [[ "$worst" == "error" ]] && return 1
    return 0
}

cmd_doctor() {
    run_boot_doctor_checks
}
