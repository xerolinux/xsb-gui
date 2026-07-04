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

    # Whole /etc/default directory, not just grub's own file: guarantees an
    # exact revert of everything under it (including files migration
    # itself adds, like /etc/default/limine, or anything another package
    # happens to place there), not a selective restore of grub alone.
    # Deliberate tradeoff: if something else under /etc/default is
    # legitimately added/changed while migrated, reverting undoes that too
    # - "revert" here means "put it back exactly as it was before
    # migrating", not a partial merge.
    [[ -d /etc/default ]]     && { run_cmd /usr/bin/cp -a /etc/default "${backup_dir}/etc-default" || return 1; }
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
    if [[ -d "${backup_dir}/etc-default" ]]; then
        # Current backup format: whole-directory snapshot. Wipes the live
        # /etc/default and replaces it wholesale with the exact
        # pre-migration snapshot (see backup_grub_state's own comment on
        # why this is a full replace, not a merge).
        run_cmd /usr/bin/rm -rf /etc/default || return 1
        run_cmd /usr/bin/cp -a "${backup_dir}/etc-default" /etc/default || return 1
    elif [[ -f "${backup_dir}/etc-default-grub" ]]; then
        # Backward compat: a backup made before the whole-directory format
        # existed only has grub's own config file.
        run_cmd /usr/bin/cp -a "${backup_dir}/etc-default-grub" /etc/default/grub || return 1
    fi
    # Saved-default/boot-once state only - grub.cfg itself is NOT restored
    # from backup here. A backed-up grub.cfg reflects whatever
    # kernels/packages existed at migration time, which can be stale by the
    # time of a revert (kernel updates, package changes since); it's
    # regenerated fresh via grub-mkconfig in cmd_revert instead, which
    # discovers whatever's actually installed right now.
    if [[ -f "${backup_dir}/boot-grub/grubenv" ]]; then
        run_cmd /usr/bin/mkdir -p /boot/grub || return 1
        run_cmd /usr/bin/cp -a "${backup_dir}/boot-grub/grubenv" /boot/grub/grubenv || return 1
    fi
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
    # Limine's firmware boot entry(ies). Loops over EVERY match, not just
    # the first: real firmware can end up with more than one XeroLinux/
    # Limine-labeled NVRAM entry (repeated runs, firmware quirks that
    # duplicate entries rather than reusing them), and leaving any behind
    # orphans it pointing at files just deleted above - producing a dead
    # boot option that some firmware won't skip past on its own.
    local limine_bootnums bootnum
    limine_bootnums="$(efibootmgr 2>/dev/null | grep -iE 'XeroLinux|Limine' | grep -oE '^Boot[0-9A-Fa-f]{4}' | sed 's/^Boot//')" || true
    while IFS= read -r bootnum; do
        [[ -n "$bootnum" ]] && run_cmd /usr/bin/efibootmgr -b "$bootnum" -B
    done <<< "$limine_bootnums"
    return 0
}

# Defense-in-depth against the same incident the loop above fixes: rather
# than trusting firmware to correctly skip past any stale/orphaned boot
# entries on its own, explicitly put GRUB's own NVRAM entry first in
# BootOrder. Some firmware stops at the first boot option that fails to
# load instead of trying the next one - a device booting straight to
# firmware setup after a revert is exactly that failure mode. Best-effort:
# GRUB's own NVRAM entry (created by grub-install) already exists
# regardless of whether this reordering succeeds, so a failure here must
# never turn an already-successful revert into a reported failure.
promote_grub_boot_order() {
    local grub_efi_path="$1" efibootmgr_v_output="${2-$(efibootmgr -v 2>/dev/null)}"
    local grub_bootnum
    grub_bootnum="$(find_grub_efi_bootnum "$efibootmgr_v_output" "$grub_efi_path")"
    [[ -z "$grub_bootnum" ]] && return 0

    local current_order
    current_order="${3-$(efibootmgr 2>/dev/null | grep -iE '^BootOrder:' | sed 's/^BootOrder:[[:space:]]*//')}"
    [[ -z "$current_order" ]] && return 0

    local -a order_list
    IFS=',' read -ra order_list <<< "$current_order"
    local new_order="$grub_bootnum" entry
    for entry in "${order_list[@]}"; do
        [[ -n "$entry" && "$entry" != "$grub_bootnum" ]] && new_order+=",${entry}"
    done

    [[ "$new_order" != "$current_order" ]] && run_cmd /usr/bin/efibootmgr -o "$new_order"
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

    # Restoring /etc/default/grub MUST happen before grub-install runs, not
    # after: grub-install itself (not just grub-mkconfig) reads settings
    # from /etc/default/grub at install time (e.g. GRUB_ENABLE_CRYPTODISK
    # controls whether cryptodisk support gets baked into the core image).
    # Running grub-install first meant it only ever saw the
    # freshly-reinstalled grub package's default config, never the user's
    # real one - a real ordering bug regardless of which /etc/default/grub
    # settings the user actually relies on.
    emit_event "revert_step" "info" "Restoring your original GRUB configuration"
    restore_grub_files || {
        emit_event "error" "error" "Failed to restore GRUB configuration files. Limine has NOT been touched; your system still boots via Limine."
        return 1
    }

    emit_event "revert_step" "info" "Reinstalling GRUB to the EFI system partition"
    local grub_id
    grub_id="$(grub_bootloader_id_from_backup)"
    # --force: allow installing over an existing/foreign bootloader in that
    # location without refusing. --recheck: re-probe disk devices instead
    # of trusting any stale device.map, since the disk layout may have
    # changed since GRUB was last installed here (Limine migration, disk
    # changes). Both match the known-working manual recipe for this exact
    # scenario.
    run_cmd /usr/bin/grub-install --target=x86_64-efi --efi-directory="$esp_mountpoint" --bootloader-id="$grub_id" --force --recheck || {
        emit_event "error" "error" "grub-install failed. Limine has NOT been touched; your system still boots via Limine."
        return 1
    }

    # grub.cfg is generated fresh here, not restored from backup: this
    # discovers whatever kernels/OS state actually exist right now (reading
    # the just-restored /etc/default/grub for GRUB_CMDLINE_LINUX_DEFAULT
    # etc.), rather than trusting a snapshot that may be stale relative to
    # kernel/package updates since migration.
    emit_event "revert_step" "info" "Generating GRUB configuration"
    run_cmd /usr/bin/grub-mkconfig -o /boot/grub/grub.cfg || {
        emit_event "error" "error" "grub-mkconfig failed. Limine has NOT been touched; your system still boots via Limine."
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

    emit_event "revert_step" "info" "Making sure GRUB boots first"
    promote_grub_boot_order "/EFI/${grub_id}/grubx64.efi" || true

    # Post-revert self-check: this is exactly the class of bug a real
    # incident exposed (a stale Limine fallback binary left behind after
    # revert), so this check would have caught it before the next reboot.
    # `|| true` - a finding here must never turn an already-successful
    # revert into a reported failure.
    run_boot_doctor_checks || true

    emit_event "revert_done" "info" "Revert complete. GRUB is restored; reboot to use it."
}
