#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later

is_uefi() {
    local efi_dir="${1:-/sys/firmware/efi}"
    [[ -d "$efi_dir" ]]
}

find_esp_mountpoint() {
    local root="${1:-}"
    local mounted_paths="${2:-$(findmnt -rno TARGET)}"
    local candidate
    for candidate in /boot/efi /efi /boot; do
        if grep -qx "$candidate" <<< "$mounted_paths" && [[ -d "${root}${candidate}/EFI" ]]; then
            printf '%s' "$candidate"
            return 0
        fi
    done
    return 1
}

detect_esp_size_bytes() {
    local esp_mountpoint="${1:-}"
    [[ -z "$esp_mountpoint" ]] && return 1
    local esp_source
    esp_source="$(findmnt -no SOURCE "$esp_mountpoint" 2>/dev/null)" || return 1
    [[ -z "$esp_source" ]] && return 1
    lsblk -bdno SIZE "$esp_source" 2>/dev/null
}

# Free (available) bytes on the ESP filesystem, from the live mount. Used to
# warn about a filling ESP - a softer, actionable signal than the hard total
# size floor, since space is what actually runs out as kernels accumulate.
detect_esp_free_bytes() {
    local esp_mountpoint="${1:-}"
    [[ -z "$esp_mountpoint" ]] && return 1
    df -B1 --output=avail "$esp_mountpoint" 2>/dev/null | tail -1 | tr -d '[:space:]'
}

detect_partition_table() {
    local pttype_output="${1:-}"
    if [[ -z "$pttype_output" ]]; then
        local esp_mountpoint="" esp_source="" parent_disk=""
        esp_mountpoint="$(find_esp_mountpoint)" || true
        if [[ -n "$esp_mountpoint" ]]; then
            esp_source="$(findmnt -no SOURCE "$esp_mountpoint" 2>/dev/null)" || true
        fi
        if [[ -n "$esp_source" ]]; then
            parent_disk="$(lsblk -no PKNAME "$esp_source" 2>/dev/null)"
            pttype_output="$(lsblk -dno PTTYPE "/dev/$parent_disk" 2>/dev/null)"
        fi
    fi
    [[ "$pttype_output" == "gpt" ]]
}

detect_bootloader() {
    local installed="${1-$(pacman -Qq grub limine 2>/dev/null)}"
    if grep -qx grub <<< "$installed"; then
        printf 'grub'
    elif grep -qx limine <<< "$installed"; then
        printf 'limine'
    else
        printf 'none'
    fi
}

detect_luks_root() {
    local crypttab_content="${1-$(cat /etc/crypttab 2>/dev/null)}"
    grep -vE '^[[:space:]]*(#|$)' <<< "$crypttab_content" | grep -q .
}

detect_mkinitcpio_hook_family() {
    local conf_content="${1-$(cat /etc/mkinitcpio.conf 2>/dev/null)}"
    if grep -qE '(^|[[:space:]])sd-encrypt([[:space:]]|$)' <<< "$conf_content"; then
        printf 'sd-encrypt'
    elif grep -qE '(^|[[:space:]])encrypt([[:space:]]|$)' <<< "$conf_content"; then
        printf 'encrypt'
    else
        printf 'none'
    fi
}

build_json_string_array() {
    local items="$1"
    local out="[" first=1 item
    while IFS= read -r item; do
        [[ -z "$item" ]] && continue
        [[ $first -eq 0 ]] && out+=","
        out+="\"$(json_escape "$item")\""
        first=0
    done <<< "$items"
    out+="]"
    printf '%s' "$out"
}

emit_preflight_result() {
    local uefi="$1" gpt="$2" esp_mountpoint="$3" bootloader="$4" luks="$5" \
          mkinitcpio_hook="$6" other_os_json="$7" secureboot_state="$8" esp_size_bytes="${9:-0}" \
          esp_free_bytes="${10:-0}"
    printf '{"event":"preflight_result","level":"info","data":{"uefi":%s,"gpt":%s,"esp_mountpoint":"%s","bootloader":"%s","luks":%s,"mkinitcpio_hook":"%s","other_os":%s,"secureboot_state":"%s","esp_size_bytes":%s,"esp_free_bytes":%s}}\n' \
        "$uefi" "$gpt" "$(json_escape "$esp_mountpoint")" "$(json_escape "$bootloader")" \
        "$luks" "$(json_escape "$mkinitcpio_hook")" "$other_os_json" "$(json_escape "$secureboot_state")" \
        "$esp_size_bytes" "$esp_free_bytes"
}

cmd_preflight() {
    if ! is_uefi; then
        emit_event "error" "error" "This system is not booted in UEFI mode. Secure Boot and this migration are unavailable."
        return 1
    fi
    emit_event "preflight_step" "info" "Checking partition table type"
    local gpt="false"
    detect_partition_table && gpt="true"
    if [[ "$gpt" != "true" ]]; then
        emit_event "error" "error" "This system's disk is not using a GPT partition table. UEFI firmware requires GPT, so BIOS/MBR-style disks are not supported by this tool."
        return 1
    fi
    emit_event "preflight_step" "info" "Checking EFI system partition"
    local esp_mountpoint
    esp_mountpoint="$(find_esp_mountpoint)" || esp_mountpoint=""
    if [[ -z "$esp_mountpoint" ]]; then
        emit_event "error" "error" "No EFI system partition found. Nothing can be installed without one."
        return 1
    fi
    local esp_size_bytes esp_free_bytes
    esp_size_bytes="$(detect_esp_size_bytes "$esp_mountpoint")" || esp_size_bytes="0"
    [[ -z "$esp_size_bytes" ]] && esp_size_bytes="0"
    esp_free_bytes="$(detect_esp_free_bytes "$esp_mountpoint")" || esp_free_bytes="0"
    [[ -z "$esp_free_bytes" ]] && esp_free_bytes="0"
    # Hard floor (64MiB), distinct from parsing.py's softer 256MiB warning:
    # below this there's genuinely not enough room for Limine plus a
    # kernel/initramfs copy. Skipped when esp_free_bytes is unknown (0).
    if [[ "$esp_free_bytes" -gt 0 ]] && [[ "$esp_free_bytes" -lt 67108864 ]]; then
        emit_event "error" "error" "The EFI system partition has less than 64MB free. There is not enough room to install Limine and a kernel/initramfs copy."
        return 1
    fi
    emit_event "preflight_step" "info" "Checking current bootloader"
    local bootloader
    bootloader="$(detect_bootloader)"
    if [[ "$bootloader" == "none" ]]; then
        emit_event "error" "error" "Neither GRUB nor Limine is installed. This tool migrates an existing GRUB installation to Limine; there is nothing here to migrate."
        return 1
    fi
    emit_event "preflight_step" "info" "Checking for LUKS-encrypted root"
    local luks="false"
    detect_luks_root && luks="true"
    local mkinitcpio_hook
    mkinitcpio_hook="$(detect_mkinitcpio_hook_family)"
    emit_event "preflight_step" "info" "Checking for other operating systems"
    local other_os_json
    other_os_json="$(build_json_string_array "$(detect_other_os)")"
    emit_event "preflight_step" "info" "Checking Secure Boot firmware state"
    local secureboot_state
    secureboot_state="$(detect_secureboot_state)"
    if [[ "$secureboot_state" == "enabled" && "$bootloader" == "grub" ]]; then
        emit_event "error" "error" "Secure Boot is already enabled in firmware. Migrating now would leave an unsigned, unbootable Limine after reboot. Reboot into UEFI firmware settings and disable Secure Boot first - it can be safely re-enabled after migration completes."
        return 1
    fi
    emit_event "preflight_step" "info" "Checking for existing Secure Boot key enrollment"
    # Hard stop, not just informational: if firmware already has committed
    # keys (Setup Mode: Disabled, or Secure Boot already on) that this tool
    # didn't create, nothing downstream can safely sign against them.
    # Mirrors cmd_enable_secureboot's own refusal, surfaced here instead of
    # discovered only after migration/signing has already started.
    if { [[ "$secureboot_state" == "enabled" ]] || keys_enrolled; } && ! sbctl_keys_exist_locally; then
        emit_event "error" "error" "Secure Boot keys are already enrolled in firmware, but not by this tool. Proceeding could not safely sign anything against an unrelated existing enrollment. Reboot into UEFI firmware settings and clear all Secure Boot keys (PK, KEK, db, dbx) to start fresh, then run this again."
        return 1
    fi
    # Also a hard stop, the opposite case: Secure Boot already enabled AND
    # the keys are this tool's own - everything is already set up. By this
    # point bootloader can only be "limine" (grub+enabled and
    # bootloader=="none" were already refused above), so block rather than
    # run through to a redundant re-sign.
    if [[ "$secureboot_state" == "enabled" ]] && keys_enrolled && sbctl_keys_exist_locally; then
        emit_event "error" "error" "Secure Boot is already enabled and fully configured by this tool. There is nothing further to do here."
        return 1
    fi
    emit_preflight_result "true" "$gpt" "$esp_mountpoint" "$bootloader" "$luks" \
        "$mkinitcpio_hook" "$other_os_json" "$secureboot_state" "$esp_size_bytes" "$esp_free_bytes"
}

cmd_status() {
    local bootloader secureboot_state
    bootloader="$(detect_bootloader)"
    secureboot_state="$(detect_secureboot_state)"
    printf '{"event":"status_result","level":"info","data":{"bootloader":"%s","secureboot_state":"%s"}}\n' \
        "$(json_escape "$bootloader")" "$(json_escape "$secureboot_state")"
}
