#!/usr/bin/env bash
echo '{"event":"preflight_step","level":"info","message":"checking"}'
echo '{"event":"preflight_result","level":"info","data":{"uefi":true,"gpt":true,"esp_mountpoint":"/boot/efi","bootloader":"grub","luks":false,"mkinitcpio_hook":"none","other_os":[],"secureboot_state":"disabled","esp_size_bytes":524288000}}'
exit 0
