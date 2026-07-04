#!/usr/bin/env bash
echo '{"event":"cleanup_step","level":"info","message":"Cleaning up leftover boot files"}'
echo '{"event":"would_run","level":"info","message":"/usr/bin/rm -f /boot/efi/limine.conf.old"}'
echo '{"event":"would_run","level":"info","message":"/usr/bin/rm -rf /boot/efi/loader"}'
echo '{"event":"cleanup_done","level":"info","message":"ESP cleanup complete."}'
exit 0
