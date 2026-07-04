#!/usr/bin/env bash
echo '{"event":"revert_step","level":"info","message":"Reinstalling GRUB packages"}'
echo '{"event":"would_run","level":"info","message":"/usr/bin/pacman -S --noconfirm --needed grub"}'
echo '{"event":"revert_step","level":"info","message":"Reinstalling GRUB to the EFI system partition"}'
echo '{"event":"would_run","level":"info","message":"/usr/bin/grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=GRUB"}'
echo '{"event":"revert_step","level":"info","message":"Removing Limine"}'
echo '{"event":"revert_done","level":"info","message":"Revert complete. GRUB is restored; reboot to use it."}'
exit 0
