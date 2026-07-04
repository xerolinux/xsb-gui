#!/usr/bin/env bash
echo '{"event":"preflight_step","level":"info","message":"checking"}'
echo '{"event":"preflight_result","level":"info","data":{"uefi":true,"gpt":true,"esp_mountpoint":"/boot/efi","bootloader":"limine","luks":false,"mkinitcpio_hook":"none","other_os":[],"secureboot_state":"enabled","esp_size_bytes":1073741824}}'
exit 0
