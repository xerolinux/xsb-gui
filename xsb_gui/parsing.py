from dataclasses import dataclass


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
    return "\n".join(lines)


def format_event_line(event: dict) -> str:
    level = event.get("level", "info").upper()
    message = event.get("message", "")
    return f"[{level}] {message}"
