#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later

detect_secureboot_state() {
    local sbctl_status_output="${1-$(sbctl status 2>/dev/null)}"
    if [[ -z "$sbctl_status_output" ]]; then
        printf 'unsupported'
    elif grep -qE 'Secure Boot:[[:space:]]*Enabled' <<< "$sbctl_status_output"; then
        printf 'enabled'
    elif grep -qE 'Setup Mode:[[:space:]]*Enabled' <<< "$sbctl_status_output"; then
        printf 'setup_mode'
    else
        printf 'disabled'
    fi
}

in_setup_mode() {
    local sbctl_status_output="${1-$(sbctl status 2>/dev/null)}"
    grep -q "Setup Mode:.*Enabled" <<< "$sbctl_status_output"
}

keys_enrolled() {
    local sbctl_status_output="${1-$(sbctl status 2>/dev/null)}"
    grep -q "Setup Mode:.*Disabled" <<< "$sbctl_status_output"
}

sbctl_keys_exist_locally() {
    local keys_dir="${1-/usr/share/secureboot/keys}"
    [[ -d "$keys_dir" ]]
}

choose_enroll_cmd() {
    local board_vendor="${1-$(cat /sys/class/dmi/id/board_vendor 2>/dev/null)}"
    local db_default_exists="${2-0}"
    if [[ "$board_vendor" == *ASUS* ]]; then
        printf '/usr/bin/sbctl enroll-keys --microsoft'
    elif [[ "$db_default_exists" != "1" ]]; then
        printf '/usr/bin/sbctl enroll-keys --microsoft'
    else
        printf '/usr/bin/sbctl enroll-keys --microsoft --firmware-builtin'
    fi
}

sign_efi_and_kernels() {
    local esp_dir="$1"
    local efi_file kernel_file
    while IFS= read -r efi_file; do
        [[ -z "$efi_file" ]] && continue
        run_cmd /usr/bin/sbctl sign -s "$efi_file"
    done < <(find "$esp_dir" -name '*.efi' -o -iname '*.EFI' 2>/dev/null)
    for kernel_file in /boot/vmlinuz-*; do
        [[ -f "$kernel_file" ]] || continue
        run_cmd /usr/bin/sbctl sign -s "$kernel_file"
    done
}

cmd_enable_secureboot() {
    local state
    state="$(detect_secureboot_state)"

    if [[ "$state" == "enabled" ]] || keys_enrolled; then
        if ! sbctl_keys_exist_locally; then
            emit_event "error" "error" "Secure Boot keys are already enrolled in firmware, but not by this tool. sbctl has no local key database on this system, so it cannot safely sign anything against an unrelated existing enrollment. Reboot into UEFI firmware settings and clear all Secure Boot keys (PK, KEK, db, dbx) to start fresh, then run this again."
            return 1
        fi

        local esp_dir
        esp_dir="$(find_esp_mountpoint)" || esp_dir="/boot/efi"

        if [[ "$state" == "enabled" ]]; then
            emit_event "secureboot_step" "info" "Secure Boot already active. Re-signing EFI binaries."
            sign_efi_and_kernels "$esp_dir" || {
                emit_event "error" "error" "Failed to sign EFI binaries/kernels. Secure Boot is already active; unsigned binaries may fail to boot on the next update."
                return 1
            }
            emit_event "secureboot_already_active" "info" "Secure Boot re-signing complete."
        else
            emit_event "secureboot_step" "info" "Keys already enrolled. Re-signing EFI binaries."
            sign_efi_and_kernels "$esp_dir" || {
                emit_event "error" "error" "Failed to sign EFI binaries/kernels. Do NOT enable Secure Boot in firmware yet; boot binaries are not signed."
                return 1
            }
            emit_event "secureboot_needs_reboot" "info" "Reboot into firmware setup and enable Secure Boot."
        fi
        return 0
    fi

    if ! in_setup_mode; then
        emit_event "error" "error" "Setup Mode is not active. Reboot into UEFI firmware settings and clear all Secure Boot keys (PK, KEK, db, dbx) before running this again."
        return 1
    fi

    emit_event "secureboot_step" "info" "Creating Secure Boot keys"
    run_cmd /usr/bin/sbctl create-keys || {
        emit_event "error" "error" "Failed to create Secure Boot keys."
        return 1
    }

    local board_vendor db_default enroll_cmd
    board_vendor="$(cat /sys/class/dmi/id/board_vendor 2>/dev/null)" || true
    if [[ -f "/sys/firmware/efi/efivars/dbDefault-8be4df61-93ca-11d2-aa0d-00e098032b8c" ]]; then
        db_default="1"
    else
        db_default="0"
    fi
    enroll_cmd="$(choose_enroll_cmd "$board_vendor" "$db_default")"
    emit_event "secureboot_step" "info" "Enrolling keys: $enroll_cmd"
    run_cmd $enroll_cmd || {
        emit_event "error" "error" "Failed to enroll Secure Boot keys."
        return 1
    }

    local esp_dir
    esp_dir="$(find_esp_mountpoint)" || esp_dir="/boot/efi"
    emit_event "secureboot_step" "info" "Signing EFI binaries and kernels"
    sign_efi_and_kernels "$esp_dir" || {
        emit_event "error" "error" "Failed to sign EFI binaries/kernels. Do NOT enable Secure Boot in firmware yet; boot binaries are not signed."
        return 1
    }

    emit_event "secureboot_needs_reboot" "info" "Secure Boot setup complete. Reboot into firmware settings and enable Secure Boot."
}

cmd_reset_secureboot_keys() {
    emit_event "secureboot_step" "info" "Clearing local Secure Boot key database"
    run_cmd /usr/bin/rm -rf /usr/share/secureboot || {
        emit_event "error" "error" "Failed to clear local Secure Boot keys."
        return 1
    }
    if in_setup_mode; then
        emit_event "reset_keys_done" "info" "Local Secure Boot keys cleared. Firmware is in Setup Mode; you can now run enable-secureboot to start fresh."
    else
        emit_event "reset_keys_done" "info" "Local Secure Boot keys cleared, but firmware still has existing keys enrolled. Reboot into UEFI firmware settings and clear all Secure Boot keys (PK, KEK, db, dbx) before running enable-secureboot again."
    fi
}
