#!/usr/bin/env bash
echo '{"event":"doctor_check","level":"ok","message":"UEFI mode: Booted in UEFI mode."}'
echo '{"event":"doctor_check","level":"warning","message":"UEFI fallback path: UEFI fallback binary does not match the active Limine install."}'
echo '{"event":"doctor_done","level":"warning","message":"Boot diagnostics complete: potential issues found, review above."}'
exit 0
