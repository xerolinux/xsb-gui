#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later

chainload_loader_path_for_os() {
    local os_label="$1"
    case "$os_label" in
        *[Ww]indows*) printf '/EFI/Microsoft/Boot/bootmgfw.efi' ;;
        *) printf '/EFI/Boot/bootx64.efi' ;;
    esac
}

# Builds ONLY chainload stanzas for detected other-OSes, appended to
# <esp_mountpoint>/limine.conf. The timeout:/default_entry: header and
# XeroLinux's own kernel entries come from limine-mkinitcpio-hook via
# /etc/default/limine (write_limine_defaults) - never emit those here.
build_limine_conf() {
    local other_os_list="${1-}"
    local -a lines=()
    if [[ -n "$other_os_list" ]]; then
        local os_label loader_path
        while IFS= read -r os_label; do
            [[ -z "$os_label" ]] && continue
            loader_path="$(chainload_loader_path_for_os "$os_label")"
            [[ ${#lines[@]} -gt 0 ]] && lines+=("")
            lines+=("/$os_label" "    protocol: efi_chainload" "    path: boot():${loader_path}")
        done <<< "$other_os_list"
    fi
    if [[ ${#lines[@]} -gt 0 ]]; then
        printf '%s\n' "${lines[@]}"
    fi
}

resolve_root_cmdline_params() {
    local luks="$1" mkinitcpio_hook="$2" root_uuid="$3" crypttab_content="${4-$(cat /etc/crypttab 2>/dev/null)}"
    # root_source/fstype/options describe the LIVE mounted root - reliable
    # ground truth for the LVM-on-LUKS and btrfs-subvolume detection below,
    # since this tool only runs on an already-booted system.
    local root_source="${5-$(findmnt -no SOURCE / 2>/dev/null)}"
    local root_fstype="${6-$(findmnt -no FSTYPE / 2>/dev/null)}"
    local root_options="${7-$(findmnt -no OPTIONS / 2>/dev/null)}"

    # btrfs subvol root: grub-mkconfig reads fstab for rootflags=subvol=;
    # this tool doesn't, so read the live mount's OPTIONS instead. Kernel
    # reports subvol= with a leading "/" (e.g. subvol=/@); strip it to
    # match fstab's convention (subvol=@).
    local rootflags=""
    if [[ "$root_fstype" == "btrfs" ]]; then
        # Combined local+assign (not split): grep exits nonzero on "no
        # subvol=" (a valid top-level-mount case); `|| true` makes that an
        # explicit empty result instead of tripping set -e.
        local subvol_opt="$(grep -oE 'subvol=[^,]+' <<< "$root_options" | head -1 || true)"
        if [[ -n "$subvol_opt" ]]; then
            # Bare "subvol=/" (top-level subvolume) strips to empty - the
            # default mount, needing no rootflags=.
            local subvol_name="${subvol_opt#subvol=/}"
            [[ -n "$subvol_name" ]] && rootflags=" rootflags=subvol=${subvol_name}"
        fi
    fi

    if [[ "$luks" != "true" ]]; then
        printf 'root=UUID=%s%s' "$root_uuid" "$rootflags"
        return
    fi

    # Multiple crypttab entries (e.g. swap listed above root): prefer the
    # entry whose mapper matches the live root device over the first line.
    local root_mapper_name=""
    [[ -n "$root_source" ]] && root_mapper_name="$(basename "$root_source")"

    # Direct mapper-name match handles plain (non-LVM) LUKS root.
    # Deliberately doesn't handle LVM-on-LUKS (see below): root_mapper_name
    # there is the LV's basename, never the raw LUKS container's name.
    local crypt_line=""
    if [[ -n "$root_mapper_name" ]]; then
        crypt_line="$(grep -vE '^[[:space:]]*(#|$)' <<< "$crypttab_content" \
            | awk -v m="$root_mapper_name" '$1 == m' | head -1)"
    fi

    if [[ -z "$crypt_line" ]]; then
        # No mapper match: LVM-on-LUKS signature. Instead of blindly
        # falling back to head -1 (wrong entry if swap is listed first),
        # find the root LV's volume group and pick the crypttab entry
        # whose LUKS mapper is a PV in that same VG. Combined local+assign:
        # lvs exits nonzero when root_source isn't an LV (plain-LUKS case).
        local root_lv_vg="${10-$(lvs --noheadings -o vg_name "$root_source" 2>/dev/null | tr -d '[:space:]')}"
        if [[ -n "$root_lv_vg" ]]; then
            local candidate_line
            while IFS= read -r candidate_line; do
                [[ -z "$candidate_line" ]] && continue
                local candidate_mapper="$(awk '{print $1}' <<< "$candidate_line")"
                local candidate_vg="$(pvs --noheadings -o vg_name "/dev/mapper/${candidate_mapper}" 2>/dev/null | tr -d '[:space:]')"
                if [[ -n "$candidate_vg" && "$candidate_vg" == "$root_lv_vg" ]]; then
                    crypt_line="$candidate_line"
                    break
                fi
            done < <(grep -vE '^[[:space:]]*(#|$)' <<< "$crypttab_content")
        fi
    fi

    if [[ -z "$crypt_line" ]]; then
        # Last resort: neither method matched - genuinely ambiguous setup.
        crypt_line="$(grep -vE '^[[:space:]]*(#|$)' <<< "$crypttab_content" | head -1)"
    fi

    local mapper_name="$(awk '{print $1}' <<< "$crypt_line")"
    local luks_uuid="$(awk '{print $2}' <<< "$crypt_line" | sed -E 's#^(UUID=|/dev/disk/by-uuid/)##')"

    # LVM-on-LUKS: Calamares's "erase disk and encrypt" creates LUKS -> PV
    # -> VG -> LV, so the real root isn't the raw LUKS mapper. Detect via
    # whether the mapper is itself an LVM PV; if so, resolve root= to the
    # live root LV's UUID instead. Combined local+assign (not split): pvs
    # exits nonzero on a non-PV device (the plain-LUKS case) - a split
    # assignment would abort under set -e, but `local`'s own exit status
    # masks it, treating "not a PV" as empty output.
    local pvs_output="${8-$(pvs --noheadings -o vg_name "/dev/mapper/${mapper_name}" 2>/dev/null | head -1)}"

    local root_dev_part
    if [[ -n "$pvs_output" ]]; then
        local lv_uuid="${9-$(blkid -s UUID -o value "$root_source" 2>/dev/null)}"
        root_dev_part="root=UUID=${lv_uuid}"
    else
        # Not an LVM PV: plain LUKS root (the common case).
        root_dev_part="root=/dev/mapper/${mapper_name}"
    fi

    if [[ "$mkinitcpio_hook" == "sd-encrypt" ]]; then
        printf 'rd.luks.name=%s=%s %s%s' "$luks_uuid" "$mapper_name" "$root_dev_part" "$rootflags"
    else
        printf 'cryptdevice=UUID=%s:%s %s%s' "$luks_uuid" "$mapper_name" "$root_dev_part" "$rootflags"
    fi
}

resolve_grub_extra_params() {
    local grub_defaults_content="${1-$(cat /etc/default/grub 2>/dev/null)}"
    local line value
    line="$(grep -E '^GRUB_CMDLINE_LINUX_DEFAULT=' <<< "$grub_defaults_content" | tail -1)"
    if [[ -z "$line" ]]; then
        printf 'quiet nowatchdog loglevel=3'
        return
    fi
    value="${line#GRUB_CMDLINE_LINUX_DEFAULT=}"
    value="${value%\"}"
    value="${value#\"}"
    value="${value%\'}"
    value="${value#\'}"
    if [[ -z "$value" ]]; then
        printf 'quiet nowatchdog loglevel=3'
    else
        printf '%s' "$value"
    fi
}

build_limine_defaults_content() {
    local root_cmdline_params="$1" grub_extra_params="$2"
    printf 'KERNEL_CMDLINE[default]="%s %s"\n' "$grub_extra_params" "$root_cmdline_params"
}

write_limine_defaults() {
    local path="${1-/etc/default/limine}" root_cmdline_params="$2" grub_extra_params="${3-quiet nowatchdog loglevel=3}"
    if [[ "${DRY_RUN:-0}" == "1" ]]; then
        emit_event "would_run" "info" "write $path"
        return 0
    fi
    build_limine_defaults_content "$root_cmdline_params" "$grub_extra_params" > "$path"
}

install_limine_packages() {
    run_cmd /usr/bin/pacman -S --noconfirm --needed limine limine-mkinitcpio-hook
}

resolve_esp_disk_and_part() {
    local esp_source="${1-$(findmnt -no SOURCE /boot/efi 2>/dev/null)}"
    local parent_disk part_num
    parent_disk="$(lsblk -no PKNAME "$esp_source" 2>/dev/null)"
    part_num="$(lsblk -no PARTN "$esp_source" 2>/dev/null)"
    printf '/dev/%s %s' "$parent_disk" "$part_num"
}

deploy_limine_to_esp() {
    local esp_mountpoint="${1-/boot/efi}" skip_fallback="${2-0}"
    run_cmd /usr/bin/mkdir -p "${esp_mountpoint}/EFI/XeroLinux"
    run_cmd /usr/bin/cp /usr/share/limine/BOOTX64.EFI "${esp_mountpoint}/EFI/XeroLinux/BOOTX64.EFI"
    # Also overwrite the generic UEFI fallback path (\EFI\Boot\BOOTX64.EFI):
    # GRUB was installed there too, and firmware can auto-create boot
    # options pointing at it independent of any NVRAM entry we control.
    # remove_grub only deletes GRUB's named NVRAM entry, so without this
    # the fallback could still boot GRUB's leftover binary.
    #
    # skip_fallback=1 opts out: chainload_loader_path_for_os uses this same
    # generic path as its best-effort guess for a detected non-Windows
    # other-OS. Overwriting it unconditionally would clobber that OS's
    # real bootable binary. Caller sets skip_fallback based on detection.
    if [[ "$skip_fallback" != "1" ]]; then
        run_cmd /usr/bin/mkdir -p "${esp_mountpoint}/EFI/Boot"
        run_cmd /usr/bin/cp /usr/share/limine/BOOTX64.EFI "${esp_mountpoint}/EFI/Boot/BOOTX64.EFI"
    fi
}

verify_limine_deployed() {
    local esp_mountpoint="${1-/boot/efi}"
    [[ -f "${esp_mountpoint}/EFI/XeroLinux/BOOTX64.EFI" ]]
}

verify_limine_conf_has_kernel_entry() {
    local path="${1-/boot/efi/limine.conf}"
    grep -q 'protocol:[[:space:]]*linux' "$path" 2>/dev/null
}

register_efi_boot_entry() {
    local esp_disk="$1" esp_part_num="$2"
    if verify_limine_entry; then
        emit_event "migrate_step" "info" "Limine EFI boot entry already registered, skipping."
        return 0
    fi
    run_cmd /usr/bin/efibootmgr --create --disk "$esp_disk" --part "$esp_part_num" \
        --label "XeroLinux" --loader '\EFI\XeroLinux\BOOTX64.EFI'
}

verify_limine_entry() {
    local efibootmgr_output="${1-$(efibootmgr -v 2>/dev/null)}"
    grep -qi 'XeroLinux.*BOOTX64\.EFI' <<< "$efibootmgr_output"
}

find_grub_efi_bootnum() {
    local efibootmgr_output="${1-$(efibootmgr -v 2>/dev/null)}"
    # No GRUB entry is a normal outcome, not a failure - grep exits
    # nonzero on no match, which would trip pipefail otherwise. Always
    # succeed; empty result means nothing to delete.
    grep -iE 'XeroLinux.*grubx64\.efi' <<< "$efibootmgr_output" | grep -oE '^Boot[0-9A-Fa-f]{4}' | head -1 | sed 's/^Boot//' || true
}

# GRUB's EFI binary/config live under an unknown bootloader-id directory
# (this tool never recorded it), so scan by content (grub*.efi, grub.cfg)
# instead of a guessed path. Gated behind DRY_RUN like every other
# filesystem helper here.
remove_grub_efi_leftovers() {
    local esp_mountpoint="${1-/boot/efi}"
    if [[ "${DRY_RUN:-0}" == "1" ]]; then
        emit_event "would_run" "info" "remove leftover GRUB EFI files under ${esp_mountpoint}/EFI"
        return 0
    fi
    local efi_dir="${esp_mountpoint}/EFI"
    local f
    if [[ -d "$efi_dir" ]]; then
        while IFS= read -r f; do
            [[ -n "$f" ]] && run_cmd /usr/bin/rm -f "$f"
        done < <(find "$efi_dir" -iname 'grub*.efi' 2>/dev/null)
    fi
    if [[ -d "$esp_mountpoint" ]]; then
        while IFS= read -r f; do
            [[ -n "$f" ]] && run_cmd /usr/bin/rm -f "$f"
        done < <(find "$esp_mountpoint" -iname 'grub.cfg' 2>/dev/null)
    fi
}

remove_grub() {
    local esp_mountpoint="${1-/boot/efi}"
    # pacman -Rns aborts removing NOTHING if even one target isn't
    # installed. update-grub/os-prober are optional, not always present,
    # so filter to actually-installed packages first. Skipped under
    # DRY_RUN so the preview always shows the full candidate list.
    local candidate_pkgs=(grub grub-hooks update-grub os-prober)
    local -a to_remove=()
    if [[ "${DRY_RUN:-0}" == "1" ]]; then
        to_remove=("${candidate_pkgs[@]}")
    else
        local installed_pkgs="${2-$(pacman -Qq "${candidate_pkgs[@]}" 2>/dev/null)}"
        local pkg
        while IFS= read -r pkg; do
            [[ -n "$pkg" ]] && to_remove+=("$pkg")
        done <<< "$installed_pkgs"
    fi
    if [[ "${#to_remove[@]}" -gt 0 ]]; then
        # Explicit `|| return 1` needed: cmd_migrate calls remove_grub via
        # `|| {...}`, which suspends errexit for this whole function body
        # (bash quirk). Without this, a real pacman failure would be
        # silently swallowed and the tool would falsely report success.
        run_cmd /usr/bin/pacman -Rns --noconfirm "${to_remove[@]}" || return 1
    fi
    run_cmd /usr/bin/rm -rf /boot/grub
    run_cmd /usr/bin/rm -f /etc/default/grub
    remove_grub_efi_leftovers "$esp_mountpoint"
    local grub_bootnum
    grub_bootnum="$(find_grub_efi_bootnum)"
    if [[ -n "$grub_bootnum" ]]; then
        run_cmd /usr/bin/efibootmgr -b "$grub_bootnum" -B
    fi
}

write_limine_conf() {
    local path="${1-/boot/efi/limine.conf}" other_os_list="${2-}"
    if [[ "${DRY_RUN:-0}" == "1" ]]; then
        emit_event "would_run" "info" "append chainload entries to $path"
        return 0
    fi
    if [[ -n "$other_os_list" ]]; then
        build_limine_conf "$other_os_list" >> "$path"
    fi
}

run_limine_mkinitcpio() {
    local bin_path="${1-/usr/bin/limine-mkinitcpio}"
    [[ -x "$bin_path" ]] || return 1
    run_cmd "$bin_path"
}

cmd_migrate() {
    if [[ "$(detect_bootloader)" != "grub" ]]; then
        emit_event "error" "error" "GRUB not detected. Nothing to migrate."
        return 1
    fi

    if [[ "$(detect_secureboot_state)" == "enabled" ]]; then
        emit_event "error" "error" "Secure Boot is already enabled in firmware. Migrating now would leave an unsigned, unbootable Limine after reboot. Reboot into UEFI firmware settings and disable Secure Boot first - it can be safely re-enabled after migration completes, once Limine is signed."
        return 1
    fi

    local esp_mountpoint
    esp_mountpoint="$(find_esp_mountpoint)" || {
        emit_event "error" "error" "No EFI system partition found. Aborting before any changes."
        return 1
    }

    emit_event "migrate_step" "info" "Installing Limine and limine-mkinitcpio-hook"
    install_limine_packages || {
        emit_event "error" "error" "Failed to install Limine packages. GRUB has NOT been touched."
        return 1
    }

    emit_event "migrate_step" "info" "Configuring /etc/default/limine"
    local luks="false"
    detect_luks_root && luks="true"
    local mkinitcpio_hook root_uuid root_source root_fstype root_options crypttab_content
    local root_cmdline_params grub_extra_params
    mkinitcpio_hook="$(detect_mkinitcpio_hook_family)"
    root_uuid="$(findmnt -no UUID / 2>/dev/null)" || true
    root_source="$(findmnt -no SOURCE / 2>/dev/null)" || true
    root_fstype="$(findmnt -no FSTYPE / 2>/dev/null)" || true
    root_options="$(findmnt -no OPTIONS / 2>/dev/null)" || true
    crypttab_content="$(cat /etc/crypttab 2>/dev/null)" || true
    root_cmdline_params="$(resolve_root_cmdline_params "$luks" "$mkinitcpio_hook" "$root_uuid" \
        "$crypttab_content" "$root_source" "$root_fstype" "$root_options")"
    grub_extra_params="$(resolve_grub_extra_params)"
    write_limine_defaults "/etc/default/limine" "$root_cmdline_params" "$grub_extra_params" || {
        emit_event "error" "error" "Failed to write /etc/default/limine. GRUB has NOT been touched."
        return 1
    }

    local other_os
    other_os="$(detect_other_os)"
    local skip_fallback=0
    has_non_windows_other_os "$other_os" && skip_fallback=1
    if [[ "$skip_fallback" == "1" ]]; then
        emit_event "migrate_step" "info" "Skipping generic EFI fallback path deploy: a non-Windows dual-boot OS may rely on it."
    fi

    emit_event "migrate_step" "info" "Deploying Limine to the EFI system partition"
    deploy_limine_to_esp "$esp_mountpoint" "$skip_fallback" || {
        emit_event "error" "error" "Failed to deploy Limine to the ESP. GRUB has NOT been touched."
        return 1
    }

    emit_event "migrate_step" "info" "Registering Limine EFI boot entry"
    local esp_disk esp_part_num esp_source
    # resolve_esp_disk_and_part defaults to a hardcoded /boot/efi lookup -
    # calling it bare would ignore the real $esp_mountpoint (which can be
    # /efi or /boot too), resolving to an empty disk/part on such systems.
    esp_source="$(findmnt -no SOURCE "$esp_mountpoint" 2>/dev/null)"
    read -r esp_disk esp_part_num <<< "$(resolve_esp_disk_and_part "$esp_source")"
    register_efi_boot_entry "$esp_disk" "$esp_part_num" || {
        emit_event "error" "error" "Failed to register Limine's EFI boot entry. GRUB has NOT been touched."
        return 1
    }

    emit_event "migrate_step" "info" "Regenerating initramfs"
    run_cmd /usr/bin/mkinitcpio -P || {
        emit_event "error" "error" "Failed to regenerate initramfs. GRUB has NOT been touched."
        return 1
    }

    emit_event "migrate_step" "info" "Regenerating Limine boot entries"
    run_limine_mkinitcpio || {
        emit_event "error" "error" "Failed to regenerate Limine boot entries via limine-mkinitcpio. GRUB has NOT been touched."
        return 1
    }

    emit_event "migrate_step" "info" "Adding chainload entries for other operating systems"
    write_limine_conf "${esp_mountpoint}/limine.conf" "$other_os" || {
        emit_event "error" "error" "Failed to write chainload entries to ${esp_mountpoint}/limine.conf. GRUB has NOT been touched."
        return 1
    }

    emit_event "migrate_step" "info" "Verifying Limine EFI boot entry, ESP deployment, and limine.conf kernel entry"
    if ! verify_limine_entry || ! verify_limine_deployed "$esp_mountpoint" || ! verify_limine_conf_has_kernel_entry "${esp_mountpoint}/limine.conf"; then
        emit_event "error" "error" "Limine's EFI boot entry, ESP deployment, or limine.conf kernel entry could not be verified. GRUB has NOT been removed; your system is still bootable via GRUB."
        return 1
    fi

    emit_event "migrate_step" "info" "Removing GRUB"
    remove_grub "$esp_mountpoint" || {
        emit_event "error" "error" "Failed to remove GRUB. Limine is fully installed, registered, and bootable - you can safely retry this step, or remove GRUB manually later."
        return 1
    }

    emit_event "migrate_done" "info" "Migration to Limine complete."
}

build_limine_splash_header() {
    printf '### Theme\nwallpaper: boot():/splash.png\n\n'
}

# Idempotently rewrites the ### Theme section to contain only the
# wallpaper directive, replacing (not appending to) any prior section -
# older limine.conf files may still carry a stale palette-based block.
write_limine_splash() {
    local path="$1"
    if [[ "${DRY_RUN:-0}" == "1" ]]; then
        emit_event "would_run" "info" "write splash wallpaper header to $path"
        return 0
    fi
    local tmp
    tmp="$(mktemp)"
    awk '
        /^### Theme/ { skip=1; next }
        skip && (/^###/ || NF==0) { skip=0 }
        skip { next }
        { print }
    ' "$path" > "$tmp"
    { build_limine_splash_header; cat "$tmp"; } > "${path}.new"
    rm -f "$tmp"
    chmod --reference="$path" "${path}.new" 2>/dev/null || true
    mv "${path}.new" "$path"
}

verify_wallpaper_source_exists() {
    local wallpaper_path="${1-/usr/share/wallpapers/Xero-Plasma4.png}"
    [[ -f "$wallpaper_path" ]]
}

cmd_apply_splash() {
    if [[ "$(detect_bootloader)" != "limine" ]]; then
        emit_event "error" "error" "Limine is not the active bootloader. Nothing to splash."
        return 1
    fi
    local esp_mountpoint
    esp_mountpoint="$(find_esp_mountpoint)" || {
        emit_event "error" "error" "No EFI system partition found."
        return 1
    }
    if [[ ! -f "${esp_mountpoint}/limine.conf" ]]; then
        emit_event "error" "error" "${esp_mountpoint}/limine.conf not found."
        return 1
    fi
    if ! verify_wallpaper_source_exists; then
        emit_event "error" "error" "XeroLinux wallpaper not found at /usr/share/wallpapers/Xero-Plasma4.png."
        return 1
    fi
    emit_event "splash_step" "info" "Copying boot splash wallpaper"
    run_cmd /usr/bin/cp /usr/share/wallpapers/Xero-Plasma4.png "${esp_mountpoint}/splash.png" || {
        emit_event "error" "error" "Failed to copy splash wallpaper."
        return 1
    }
    write_limine_splash "${esp_mountpoint}/limine.conf" || {
        emit_event "error" "error" "Failed to update ${esp_mountpoint}/limine.conf with splash wallpaper."
        return 1
    }
    emit_event "apply_splash_done" "info" "Boot splash applied to ${esp_mountpoint}/limine.conf."
}
