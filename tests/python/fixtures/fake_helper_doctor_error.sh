#!/usr/bin/env bash
echo '{"event":"doctor_check","level":"error","message":"UEFI mode: Not booted in UEFI mode. Secure Boot and Limine are unavailable."}'
echo '{"event":"doctor_done","level":"error","message":"Boot diagnostics stopped early: not booted in UEFI mode."}'
exit 1
