from xsb_gui.parsing import parse_preflight_result, build_summary_text, format_event_line, PreflightResult


def test_parse_preflight_result_reads_all_fields():
    event = {
        "event": "preflight_result",
        "level": "info",
        "data": {
            "uefi": True,
            "gpt": True,
            "esp_mountpoint": "/boot/efi",
            "bootloader": "grub",
            "luks": False,
            "mkinitcpio_hook": "none",
            "other_os": ["Windows Boot Manager"],
            "secureboot_state": "disabled",
            "esp_size_bytes": 1073741824,
        },
    }
    result = parse_preflight_result(event)
    assert result == PreflightResult(
        uefi=True, gpt=True, esp_mountpoint="/boot/efi", bootloader="grub",
        luks=False, mkinitcpio_hook="none", other_os=["Windows Boot Manager"],
        secureboot_state="disabled", esp_size_bytes=1073741824,
    )


def test_parse_preflight_result_defaults_esp_size_bytes_when_missing():
    event = {
        "event": "preflight_result",
        "level": "info",
        "data": {
            "uefi": True,
            "gpt": True,
            "esp_mountpoint": "/boot/efi",
            "bootloader": "grub",
            "luks": False,
            "mkinitcpio_hook": "none",
            "other_os": [],
            "secureboot_state": "disabled",
        },
    }
    result = parse_preflight_result(event)
    assert result.esp_size_bytes == 0


def test_build_summary_text_lists_detected_other_os():
    result = PreflightResult(
        uefi=True, gpt=True, esp_mountpoint="/boot/efi", bootloader="grub",
        luks=True, mkinitcpio_hook="sd-encrypt", other_os=["Windows Boot Manager"],
        secureboot_state="setup_mode", esp_size_bytes=1073741824,
    )
    text = build_summary_text(result)
    assert "Windows Boot Manager" in text
    assert "Encrypted root (LUKS): yes" in text
    assert "grub" in text


def test_build_summary_text_omits_other_os_line_when_none_found():
    result = PreflightResult(
        uefi=True, gpt=True, esp_mountpoint="/boot/efi", bootloader="grub",
        luks=False, mkinitcpio_hook="none", other_os=[], secureboot_state="disabled",
        esp_size_bytes=1073741824,
    )
    text = build_summary_text(result)
    assert "chainload" not in text


def test_format_event_line_uppercases_level():
    line = format_event_line({"event": "migrate_step", "level": "info", "message": "Installing Limine"})
    assert line == "[INFO] Installing Limine"
