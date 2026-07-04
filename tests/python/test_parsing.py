from xsb_gui.parsing import (
    parse_preflight_result, build_summary_text, format_event_line, PreflightResult,
    is_esp_low_on_free_space, ESP_LOW_FREE_BYTES,
)


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


def test_build_summary_text_omits_other_os_line_when_not_migrating():
    result = PreflightResult(
        uefi=True, gpt=True, esp_mountpoint="/boot/efi", bootloader="limine",
        luks=False, mkinitcpio_hook="none", other_os=["Windows Boot Manager"],
        secureboot_state="disabled", esp_size_bytes=1073741824,
    )
    text = build_summary_text(result, migrating=False)
    assert "chainload" not in text
    assert "Windows Boot Manager" not in text


def test_parse_preflight_result_reads_esp_free_bytes():
    event = {
        "event": "preflight_result", "level": "info",
        "data": {
            "uefi": True, "gpt": True, "esp_mountpoint": "/boot/efi", "bootloader": "limine",
            "luks": False, "mkinitcpio_hook": "none", "other_os": [],
            "secureboot_state": "enabled", "esp_size_bytes": 2147483648,
            "esp_free_bytes": 104857600,
        },
    }
    result = parse_preflight_result(event)
    assert result.esp_free_bytes == 104857600


def test_parse_preflight_result_defaults_esp_free_bytes_when_missing():
    event = {
        "event": "preflight_result", "level": "info",
        "data": {
            "uefi": True, "gpt": True, "esp_mountpoint": "/boot/efi", "bootloader": "grub",
            "luks": False, "mkinitcpio_hook": "none", "other_os": [],
            "secureboot_state": "disabled", "esp_size_bytes": 1073741824,
        },
    }
    assert parse_preflight_result(event).esp_free_bytes == 0


def test_is_esp_low_on_free_space():
    assert is_esp_low_on_free_space(50 * 1024 * 1024) is True         # 50 MiB -> low
    assert is_esp_low_on_free_space(ESP_LOW_FREE_BYTES - 1) is True
    assert is_esp_low_on_free_space(ESP_LOW_FREE_BYTES) is False      # at floor -> ok
    assert is_esp_low_on_free_space(2 * 1024 * 1024 * 1024) is False  # 2 GiB -> ok
    assert is_esp_low_on_free_space(0) is False                       # unknown -> not flagged


def test_build_summary_text_warns_when_esp_low_on_free_space():
    result = PreflightResult(
        uefi=True, gpt=True, esp_mountpoint="/boot/efi", bootloader="limine",
        luks=False, mkinitcpio_hook="none", other_os=[], secureboot_state="enabled",
        esp_size_bytes=1073741824, esp_free_bytes=50 * 1024 * 1024,
    )
    text = build_summary_text(result)
    assert "low on space" in text
    assert "50 MiB free" in text


def test_build_summary_text_no_low_space_warning_when_ample():
    result = PreflightResult(
        uefi=True, gpt=True, esp_mountpoint="/boot/efi", bootloader="limine",
        luks=False, mkinitcpio_hook="none", other_os=[], secureboot_state="enabled",
        esp_size_bytes=2147483648, esp_free_bytes=2 * 1024 * 1024 * 1024,
    )
    assert "low on space" not in build_summary_text(result)


def test_format_event_line_uppercases_level():
    line = format_event_line({"event": "migrate_step", "level": "info", "message": "Installing Limine"})
    assert line == "[INFO] Installing Limine"
