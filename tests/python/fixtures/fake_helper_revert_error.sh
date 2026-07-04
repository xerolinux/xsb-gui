#!/usr/bin/env bash
echo '{"event":"error","level":"error","message":"No pre-migration GRUB backup found at /var/lib/xsb-gui/grub-backup. There is nothing to revert to (a backup is only created when you migrate with this tool)."}'
exit 1
