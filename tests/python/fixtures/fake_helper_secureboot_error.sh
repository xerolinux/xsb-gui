#!/usr/bin/env bash
echo '{"event":"secureboot_step","level":"info","message":"Signing EFI binaries and kernels"}'
echo '{"event":"error","level":"error","message":"Setup Mode is not active. Reboot into UEFI firmware settings and clear all Secure Boot keys (PK, KEK, db, dbx) before running this again."}'
exit 1
