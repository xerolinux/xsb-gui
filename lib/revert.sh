#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
#
# Backup-before-migration and revert-to-GRUB safety net.
#
# backup_grub_state() is called once at the very start of cmd_migrate, before
# anything is changed, and records everything needed to put GRUB back. cmd_revert
# uses that backup to reinstall GRUB and remove Limine, mirroring the migration's
# defensive ordering: it never removes the working bootloader (Limine) until the
# restored one (GRUB) is verified deployed and registered.

XSB_BACKUP_DIR="${XSB_BACKUP_DIR:-/var/lib/xsb-gui/grub-backup}"

# The backup is only usable once its MANIFEST marker (written last) exists, so a
# half-written backup from an interrupted run is never treated as revertible.
grub_backup_is_complete() {
    local backup_dir="${1-$XSB_BACKUP_DIR}"
    [[ -f "${backup_dir}/MANIFEST" ]]
}

# Bootloader-id GRUB was registered under, parsed from the backed-up efibootmgr
# line ("BootXXXX* <label>\tHD(...)"). Defaults to GRUB when unknown so a
# reinstall still gets a sane, non-empty --bootloader-id.
grub_bootloader_id_from_backup() {
    local backup_dir="${1-$XSB_BACKUP_DIR}"
    local line label=""
    line="$(head -1 "${backup_dir}/nvram-grub.txt" 2>/dev/null)"
    if [[ -n "$line" ]]; then
        label="${line#Boot[0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f]}"
        label="${label#\*}"
        label="${label%%$'\t'*}"
        label="${label#"${label%%[![:space:]]*}"}"
        label="${label%"${label##*[![:space:]]}"}"
    fi
    printf '%s' "${label:-GRUB}"
}

# Records the current time and installed kernel packages into the backup
# dir, for backup_grub_state_staleness_warning to compare against later.
# Best-effort: a failure here must never fail the backup it's part of.
snapshot_kernel_state_for_backup() {
    local backup_dir="$1"
    date +%s > "${backup_dir}/timestamp.txt" 2>/dev/null || true
    pacman -Q 2>/dev/null | grep -E '^linux[a-z0-9_-]*[[:space:]]' > "${backup_dir}/kernel-packages.txt" || true
}

# Best-effort, purely informational: warns (never blocks) if the GRUB
# backup is old enough, or predates enough kernel updates, that the
# restored grub.cfg may not reflect the system's current state. Prints a
# message and returns 0 if there's something worth flagging; prints
# nothing and returns 1 otherwise (including when there's no timestamp to
# compare, e.g. a backup made before this check existed).
backup_grub_state_staleness_warning() {
    local backup_dir="${1-$XSB_BACKUP_DIR}"
    local now="${2-$(date +%s)}"
    local max_age_days="${3-30}"

    local backup_ts
    backup_ts="$(cat "${backup_dir}/timestamp.txt" 2>/dev/null)"
    if [[ "$backup_ts" =~ ^[0-9]+$ ]]; then
        local age_days=$(( (now - backup_ts) / 86400 ))
        if [[ "$age_days" -gt "$max_age_days" ]]; then
            printf 'The GRUB backup used for this revert is %s days old. If your system has changed significantly since migrating, the restored configuration may not reflect it.' "$age_days"
            return 0
        fi
    fi

    local backed_up_pkgs current_pkgs
    backed_up_pkgs="$(cat "${backup_dir}/kernel-packages.txt" 2>/dev/null)"
    current_pkgs="${4-$(pacman -Q 2>/dev/null | grep -E '^linux[a-z0-9_-]*[[:space:]]')}"
    if [[ -n "$backed_up_pkgs" ]] && [[ "$backed_up_pkgs" != "$current_pkgs" ]]; then
        printf 'Kernel packages have changed since this GRUB backup was made (e.g. a kernel update). The restored configuration may not include an entry for your current kernel.'
        return 0
    fi

    return 1
}

backup_grub_state() {
    local esp_mountpoint="${1-/boot/efi}"
    local backup_dir="${2-$XSB_BACKUP_DIR}"

    if [[ "${DRY_RUN:-0}" == "1" ]]; then
        emit_event "would_run" "info" "back up current GRUB configuration to $backup_dir"
        return 0
    fi

    run_cmd /usr/bin/rm -rf "$backup_dir" || return 1
    run_cmd /usr/bin/mkdir -p "${backup_dir}/esp-grub" || return 1

    # Config + installed GRUB tree, verbatim (these are what make the restored
    # boot menu identical to the user's original).
    [[ -f /etc/default/grub ]] && { run_cmd /usr/bin/cp -a /etc/default/grub "${backup_dir}/etc-default-grub" || return 1; }
    [[ -d /etc/grub.d ]]       && { run_cmd /usr/bin/cp -a /etc/grub.d "${backup_dir}/etc-grub.d" || return 1; }
    [[ -d /boot/grub ]]        && { run_cmd /usr/bin/cp -a /boot/grub "${backup_dir}/boot-grub" || return 1; }

    # GRUB EFI binaries on the ESP, preserving their path relative to the ESP.
    local f rel
    while IFS= read -r f; do
        [[ -n "$f" ]] || continue
        rel="${f#"$esp_mountpoint"/}"
        run_cmd /usr/bin/mkdir -p "${backup_dir}/esp-grub/$(dirname "$rel")" || return 1
        run_cmd /usr/bin/cp -a "$f" "${backup_dir}/esp-grub/${rel}" || return 1
    done < <(find "$esp_mountpoint" -iname 'grub*.efi' 2>/dev/null)

    # Package list, firmware boot entry, and boot order (best-effort reads).
    pacman -Qq grub grub-hooks update-grub os-prober 2>/dev/null > "${backup_dir}/packages.txt" || true
    efibootmgr -v 2>/dev/null | grep -iE 'grubx64\.efi' > "${backup_dir}/nvram-grub.txt" || true
    efibootmgr 2>/dev/null | grep -iE '^BootOrder:' > "${backup_dir}/bootorder.txt" || true

    snapshot_kernel_state_for_backup "$backup_dir"

    # Completeness marker, written last so a partial backup is never revertible.
    printf 'esp_mountpoint=%s\n' "$esp_mountpoint" > "${backup_dir}/MANIFEST" || return 1
    emit_event "migrate_step" "info" "Backed up current GRUB configuration (revert available)."
}

reinstall_grub_packages() {
    local backup_dir="${1-$XSB_BACKUP_DIR}"
    local -a pkgs=()
    local p
    while IFS= read -r p; do
        [[ -n "$p" ]] && pkgs+=("$p")
    done < "${backup_dir}/packages.txt" 2>/dev/null
    # Fall back to the base package if the list wasn't captured.
    [[ "${#pkgs[@]}" -eq 0 ]] && pkgs=(grub)
    run_cmd /usr/bin/pacman -S --noconfirm --needed "${pkgs[@]}" || return 1
}

restore_grub_files() {
    local backup_dir="${1-$XSB_BACKUP_DIR}"
    [[ -f "${backup_dir}/etc-default-grub" ]] && { run_cmd /usr/bin/cp -a "${backup_dir}/etc-default-grub" /etc/default/grub || return 1; }
    # Restore the exact boot menu and saved-default state produced before
    # migration, over whatever grub-install just laid down.
    if [[ -f "${backup_dir}/boot-grub/grub.cfg" ]]; then
        run_cmd /usr/bin/mkdir -p /boot/grub || return 1
        run_cmd /usr/bin/cp -a "${backup_dir}/boot-grub/grub.cfg" /boot/grub/grub.cfg || return 1
    fi
    [[ -f "${backup_dir}/boot-grub/grubenv" ]] && { run_cmd /usr/bin/cp -a "${backup_dir}/boot-grub/grubenv" /boot/grub/grubenv || return 1; }
    return 0
}

# GRUB is considered restored only when its ESP binary AND a boot menu exist AND
# a firmware boot entry points at it - the same three-way check migration uses
# for Limine before it will remove the old bootloader.
verify_grub_restored() {
    local esp_mountpoint="${1-/boot/efi}"
    local efibootmgr_output="${2-$(efibootmgr -v 2>/dev/null)}"
    local grub_cfg="${3-/boot/grub/grub.cfg}"
    [[ -n "$(find "$esp_mountpoint" -iname 'grubx64.efi' -print -quit 2>/dev/null)" ]] || return 1
    [[ -f "$grub_cfg" ]] || return 1
    grep -qiE 'grubx64\.efi' <<< "$efibootmgr_output" || return 1
}

# Remove Limine only after GRUB is verified bootable. Clears Limine's packages,
# ESP files (including the now-orphaned kernel copies GRUB doesn't need, since it
# reads /boot on the root fs directly), config, and firmware entry.
remove_limine() {
    local esp_mountpoint="${1-/boot/efi}"
    local installed_pkgs="${2-$(pacman -Qq limine limine-mkinitcpio-hook 2>/dev/null)}"
    local -a pkgs=()
    local p
    if [[ "${DRY_RUN:-0}" == "1" ]]; then
        pkgs=(limine limine-mkinitcpio-hook)
    else
        while IFS= read -r p; do
            [[ -n "$p" ]] && pkgs+=("$p")
        done <<< "$installed_pkgs"
    fi
    if [[ "${#pkgs[@]}" -gt 0 ]]; then
        run_cmd /usr/bin/pacman -Rns --noconfirm "${pkgs[@]}" || return 1
    fi
    run_cmd /usr/bin/rm -f /etc/default/limine
    run_cmd /usr/bin/rm -rf "${esp_mountpoint}/EFI/XeroLinux" "${esp_mountpoint}/EFI/limine"
    run_cmd /usr/bin/rm -f "${esp_mountpoint}/limine.conf" "${esp_mountpoint}/limine.conf.old"
    # Orphaned Limine kernel copies in the ESP (machine-id dirs).
    local mid_dir mid
    for mid_dir in "${esp_mountpoint}"/*/; do
        mid_dir="${mid_dir%/}"
        mid="${mid_dir##*/}"
        [[ "$mid" =~ ^[0-9a-f]{32}$ ]] || continue
        [[ -n "$(find "$mid_dir" -maxdepth 2 -name 'vmlinuz-*' -print -quit 2>/dev/null)" ]] || continue
        run_cmd /usr/bin/rm -rf "$mid_dir"
    done
    # Limine's firmware boot entry.
    local limine_bootnum
    limine_bootnum="$(efibootmgr 2>/dev/null | grep -iE 'XeroLinux|Limine' | grep -oE '^Boot[0-9A-Fa-f]{4}' | head -1 | sed 's/^Boot//')" || true
    [[ -n "$limine_bootnum" ]] && run_cmd /usr/bin/efibootmgr -b "$limine_bootnum" -B || true
    return 0
}

cmd_revert() {
    if ! grub_backup_is_complete; then
        emit_event "error" "error" "No pre-migration GRUB backup found at ${XSB_BACKUP_DIR}. There is nothing to revert to (a backup is only created when you migrate with this tool)."
        return 1
    fi

    local staleness_warning
    staleness_warning="$(backup_grub_state_staleness_warning)" && \
        emit_event "revert_step" "warning" "$staleness_warning"

    if [[ "$(detect_bootloader)" != "limine" ]]; then
        emit_event "error" "error" "Limine is not the active bootloader; nothing to revert."
        return 1
    fi
    if [[ "$(detect_secureboot_state)" == "enabled" ]]; then
        emit_event "error" "error" "Secure Boot is enabled. Reverting to GRUB now would leave an unsigned, unbootable GRUB. Reboot into UEFI firmware settings and disable Secure Boot first, then run revert again."
        return 1
    fi

    local esp_mountpoint
    esp_mountpoint="$(find_esp_mountpoint)" || {
        emit_event "error" "error" "No EFI system partition found. Aborting before any changes."
        return 1
    }

    emit_event "revert_step" "info" "Reinstalling GRUB packages"
    reinstall_grub_packages || {
        emit_event "error" "error" "Failed to reinstall GRUB packages. Limine has NOT been touched; your system still boots via Limine."
        return 1
    }

    emit_event "revert_step" "info" "Reinstalling GRUB to the EFI system partition"
    local grub_id
    grub_id="$(grub_bootloader_id_from_backup)"
    run_cmd /usr/bin/grub-install --target=x86_64-efi --efi-directory="$esp_mountpoint" --bootloader-id="$grub_id" || {
        emit_event "error" "error" "grub-install failed. Limine has NOT been touched; your system still boots via Limine."
        return 1
    }

    # Migration also writes Limine's binary to the generic UEFI fallback path
    # (EFI/Boot/BOOTX64.EFI) so firmware can find it even without a working
    # NVRAM entry - see deploy_limine_to_esp in migrate.sh. remove_limine
    # below does not touch that path, so without clearing it here too,
    # firmware that falls back to it after Limine's NVRAM entry is removed
    # loads Limine's now configless binary instead of GRUB: an empty Limine
    # menu with no entries and no way to reach the freshly reinstalled GRUB,
    # even though GRUB's own NVRAM entry is present and correct.
    #
    # Deliberately deletes rather than installing GRUB there via
    # `grub-install --removable`: that permanently plants a second,
    # separately-tracked GRUB install at a well-known path shared with any
    # future OS install, which can conflict down the line and confuses this
    # tool's own other-OS fallback-ownership detection. Deleting just undoes
    # exactly what migration added, leaving firmware to fall through to the
    # NVRAM entry grub-install just registered. Mirrors migrate.sh's own
    # skip_fallback check: never touch that path if a real non-Windows OS
    # bootloader legitimately owns it.
    local other_os
    other_os="$(detect_other_os)"
    if ! has_non_windows_other_os "$other_os" && [[ -e "${esp_mountpoint}/EFI/Boot/BOOTX64.EFI" ]]; then
        emit_event "revert_step" "info" "Clearing Limine's leftover UEFI fallback binary"
        run_cmd /usr/bin/rm -f "${esp_mountpoint}/EFI/Boot/BOOTX64.EFI" || {
            emit_event "error" "error" "Failed to clear Limine's leftover fallback binary. Limine has NOT been touched; your system still boots via Limine."
            return 1
        }
    fi

    emit_event "revert_step" "info" "Restoring your original GRUB configuration"
    restore_grub_files || {
        emit_event "error" "error" "Failed to restore GRUB configuration files. Limine has NOT been touched; your system still boots via Limine."
        return 1
    }

    emit_event "revert_step" "info" "Verifying GRUB is installed, configured, and registered"
    if [[ "${DRY_RUN:-0}" != "1" ]] && ! verify_grub_restored "$esp_mountpoint"; then
        emit_event "error" "error" "GRUB could not be verified as restored. Limine has NOT been removed; your system is still bootable via Limine."
        return 1
    fi

    emit_event "revert_step" "info" "Removing Limine"
    remove_limine "$esp_mountpoint" || {
        emit_event "error" "error" "Failed to fully remove Limine. GRUB is restored and bootable; you can remove leftover Limine files manually."
        return 1
    }

    # Post-revert self-check: this is exactly the class of bug a real
    # incident exposed (a stale Limine fallback binary left behind after
    # revert), so this check would have caught it before the next reboot.
    # `|| true` - a finding here must never turn an already-successful
    # revert into a reported failure.
    run_boot_doctor_checks || true

    emit_event "revert_done" "info" "Revert complete. GRUB is restored; reboot to use it."
}
