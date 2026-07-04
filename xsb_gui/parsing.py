from dataclasses import dataclass

# Warn (non-blocking) when the ESP has less than this much free space. Each
# kernel image copied to the ESP is ~64 MiB, and a kernel update writes the new
# one before removing the old, so a few hundred MiB of headroom is the comfort
# floor. This is softer than esp_size_check's hard *total*-size floor: total
# size can be fine while free space quietly runs out as kernels accumulate.
ESP_LOW_FREE_BYTES = 256 * 1024 * 1024


@dataclass
class PreflightResult:
    uefi: bool
    gpt: bool
    esp_mountpoint: str
    bootloader: str
    luks: bool
    mkinitcpio_hook: str
    other_os: list
    secureboot_state: str
    esp_size_bytes: int
    esp_free_bytes: int = 0


def parse_preflight_result(event: dict) -> PreflightResult:
    data = event["data"]
    return PreflightResult(
        uefi=data["uefi"],
        gpt=data["gpt"],
        esp_mountpoint=data["esp_mountpoint"],
        bootloader=data["bootloader"],
        luks=data["luks"],
        mkinitcpio_hook=data["mkinitcpio_hook"],
        other_os=list(data["other_os"]),
        secureboot_state=data["secureboot_state"],
        esp_size_bytes=data.get("esp_size_bytes", 0),
        esp_free_bytes=data.get("esp_free_bytes", 0),
    )


def is_esp_low_on_free_space(esp_free_bytes) -> bool:
    """True only for a real, positive reading below the headroom floor. A 0/missing
    value means detection failed (treated as unknown), not a genuinely full ESP."""
    return bool(esp_free_bytes) and 0 < esp_free_bytes < ESP_LOW_FREE_BYTES


def esp_low_space_warning(esp_free_bytes) -> str:
    free_mib = esp_free_bytes // (1024 * 1024)
    return (
        f"⚠ EFI partition low on space: only {free_mib} MiB free. Kernel updates copy "
        "images here, so if it fills up, future updates can fail. Use \"Clean up ESP\" "
        "to remove leftover boot files, or free space manually."
    )


def build_summary_text(result: PreflightResult, migrating: bool = True) -> str:
    lines = [
        f"EFI system partition: {result.esp_mountpoint}",
        f"Current bootloader: {result.bootloader}",
        f"Encrypted root (LUKS): {'yes' if result.luks else 'no'}",
    ]
    if migrating and result.other_os:
        lines.append("Other OS detected, chainload entries will be added: " + ", ".join(result.other_os))
    lines.append(f"Secure Boot firmware state: {result.secureboot_state}")
    if is_esp_low_on_free_space(result.esp_free_bytes):
        lines.append(esp_low_space_warning(result.esp_free_bytes))
    return "\n".join(lines)


def format_event_line(event: dict) -> str:
    level = event.get("level", "info").upper()
    message = event.get("message", "")
    return f"[{level}] {message}"
