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
          mkinitcpio_hook="$6" other_os_json="$7" secureboot_state="$8"
    printf '{"event":"preflight_result","level":"info","data":{"uefi":%s,"gpt":%s,"esp_mountpoint":"%s","bootloader":"%s","luks":%s,"mkinitcpio_hook":"%s","other_os":%s,"secureboot_state":"%s"}}\n' \
        "$uefi" "$gpt" "$(json_escape "$esp_mountpoint")" "$(json_escape "$bootloader")" \
        "$luks" "$(json_escape "$mkinitcpio_hook")" "$other_os_json" "$(json_escape "$secureboot_state")"
}

cmd_preflight() {
    if ! is_uefi; then
        emit_event "error" "error" "This system is not booted in UEFI mode. Secure Boot and this migration are unavailable."
        return 1
    fi
    emit_event "preflight_step" "info" "Checking EFI system partition"
    local esp_mountpoint
    esp_mountpoint="$(find_esp_mountpoint)" || esp_mountpoint=""
    emit_event "preflight_step" "info" "Checking partition table type"
    local gpt="false"
    detect_partition_table && gpt="true"
    emit_event "preflight_step" "info" "Checking current bootloader"
    local bootloader
    bootloader="$(detect_bootloader)"
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
    emit_preflight_result "true" "$gpt" "$esp_mountpoint" "$bootloader" "$luks" \
        "$mkinitcpio_hook" "$other_os_json" "$secureboot_state"
}

cmd_status() {
    local bootloader secureboot_state
    bootloader="$(detect_bootloader)"
    secureboot_state="$(detect_secureboot_state)"
    printf '{"event":"status_result","level":"info","data":{"bootloader":"%s","secureboot_state":"%s"}}\n' \
        "$(json_escape "$bootloader")" "$(json_escape "$secureboot_state")"
}
