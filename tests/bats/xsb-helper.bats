#!/usr/bin/env bats

setup() {
  STUB_BIN="$BATS_TEST_TMPDIR/bin"
  mkdir -p "$STUB_BIN"
  cat > "$STUB_BIN/findmnt" <<'EOF'
#!/usr/bin/env bash
if [[ "$*" == *"-no SOURCE /boot/efi"* ]]; then echo "/dev/vda1"; exit 0; fi
echo "/boot/efi"
EOF
  cat > "$STUB_BIN/lsblk" <<'EOF'
#!/usr/bin/env bash
if [[ "$*" == *"PKNAME"* ]]; then echo "vda"; exit 0; fi
echo "gpt"
EOF
  cat > "$STUB_BIN/pacman" <<'EOF'
#!/usr/bin/env bash
echo "grub"
EOF
  cat > "$STUB_BIN/efibootmgr" <<'EOF'
#!/usr/bin/env bash
echo 'Boot0000* XeroLinux	HD(1,GPT,aaaa,0x800,0x100000)/File(\EFI\XeroLinux\BOOTX64.EFI)'
EOF
  cat > "$STUB_BIN/sbctl" <<'EOF'
#!/usr/bin/env bash
echo "Secure Boot: Disabled"
EOF
  cat > "$STUB_BIN/mkinitcpio" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
  chmod +x "$STUB_BIN"/*
  # Pre-populate a fake /boot tree with Limine's binary already deployed
  # under efi/EFI/XeroLinux, plus a limine.conf that already has a kernel
  # stanza; stub efibootmgr to already show Limine's (not GRUB's) EFI
  # entry. This gives cmd_migrate's triple verification gate
  # (verify_limine_entry, verify_limine_deployed,
  # verify_limine_conf_has_kernel_entry) real state to check against, even
  # though DRY_RUN itself never mutates anything.
  mkdir -p "$BATS_TEST_TMPDIR/boot/efi/EFI/XeroLinux"
  : > "$BATS_TEST_TMPDIR/boot/efi/EFI/XeroLinux/BOOTX64.EFI"
  printf 'timeout: 5\ndefault_entry: 1\n\n/XeroLinux\n    protocol: linux\n    kernel_path: boot():/vmlinuz-linux\n' \
    > "$BATS_TEST_TMPDIR/boot/efi/limine.conf"
  export PATH="$STUB_BIN:$PATH"
}

# cmd_migrate hard-requires a real /boot/efi/EFI directory to exist on disk
# (find_esp_mountpoint does a real `[[ -d ]]` filesystem check that no
# PATH stub can intercept), and verify_limine_conf_has_kernel_entry reads
# the real limine.conf file on the ESP (/boot/efi/limine.conf). Run the
# real xsb-helper entrypoint
# inside a private, unprivileged mount namespace with the whole /boot
# directory bind-mounted to our fake tree, so the real host /boot is never
# touched and the test is deterministic regardless of the host's actual
# ESP/limine.conf layout.
run_xsb_helper() {
  # cmd_migrate now also shells out to /usr/bin/limine-mkinitcpio by its
  # real absolute path (Fix B hardening), checked for existence even under
  # --dry-run (run_limine_mkinitcpio's own [[ -x ]] guard). Dev/CI machines
  # running this test don't have that package installed, so layer a writable
  # overlay on top of the real (read-only lowerdir) /usr/bin, inside this
  # private mount namespace only, that adds a stub limine-mkinitcpio without
  # ever touching the host's real /usr/bin.
  local usrbin_upper="$BATS_TEST_TMPDIR/usrbin-upper"
  local usrbin_work="$BATS_TEST_TMPDIR/usrbin-work"
  mkdir -p "$usrbin_upper" "$usrbin_work"
  printf '#!/usr/bin/env bash\nexit 0\n' > "$usrbin_upper/limine-mkinitcpio"
  chmod +x "$usrbin_upper/limine-mkinitcpio"
  XSB_HELPER_BIN="${BATS_TEST_DIRNAME}/../../xsb-helper" \
  FAKE_BOOT="$BATS_TEST_TMPDIR/boot" \
  USRBIN_UPPER="$usrbin_upper" \
  USRBIN_WORK="$usrbin_work" \
    unshare --mount --map-root-user --propagation private bash -c \
      'mount -t overlay overlay -o lowerdir=/usr/bin,upperdir="$USRBIN_UPPER",workdir="$USRBIN_WORK" /usr/bin \
        && mount --bind "$FAKE_BOOT" /boot && exec "$XSB_HELPER_BIN" "$@"' \
      _ "$@"
}

@test "xsb-helper preflight emits a preflight_result line" {
  mkdir -p /tmp/xsb-fake-efi 2>/dev/null || true
  run "${BATS_TEST_DIRNAME}/../../xsb-helper" preflight
  [ "$status" -eq 0 ]
  [[ "$output" == *'"event":"preflight_result"'* ]]
}

@test "xsb-helper with an unknown subcommand fails clearly" {
  run "${BATS_TEST_DIRNAME}/../../xsb-helper" bogus
  [ "$status" -ne 0 ]
  [[ "$output" == *"Unknown subcommand"* ]]
}

@test "xsb-helper migrate --dry-run previews without mutating anything" {
  run run_xsb_helper migrate --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *"migrate_done"* ]]
  [[ "$output" != *'"event":"running"'* ]]
}

@test "xsb-helper enable-secureboot --dry-run previews without mutating anything" {
  run "${BATS_TEST_DIRNAME}/../../xsb-helper" enable-secureboot --dry-run
  [ "$status" -ne 0 ]
  [[ "$output" == *"Setup Mode"* ]]
}

@test "xsb-helper apply-theme --dry-run applies the theme when the system is already migrated to Limine" {
  printf '#!/usr/bin/env bash\necho "limine"\n' > "$STUB_BIN/pacman"
  run run_xsb_helper apply-theme --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *"apply_theme_done"* ]]
}

@test "xsb-helper reset-keys --dry-run previews without mutating anything" {
  run "${BATS_TEST_DIRNAME}/../../xsb-helper" reset-keys --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *"would_run"* ]]
  [[ "$output" == *"/usr/bin/rm -rf /usr/share/secureboot"* ]]
  [[ "$output" == *"reset_keys_done"* ]]
}
