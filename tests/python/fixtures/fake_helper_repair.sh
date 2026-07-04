#!/usr/bin/env bash
echo '{"event":"repair_step","level":"info","message":"Reinstalling Limine packages"}'
echo '{"event":"would_run","level":"info","message":"/usr/bin/pacman -S --noconfirm --needed limine limine-mkinitcpio-hook"}'
echo '{"event":"repair_done","level":"info","message":"Limine repair complete."}'
exit 0
