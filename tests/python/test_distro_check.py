from unittest.mock import MagicMock, patch

from xsb_gui.distro_check import detect_distro, maybe_warn_unsupported_distro

XEROLINUX_OS_RELEASE = 'NAME="XeroLinux"\nID=xerolinux\nPRETTY_NAME="XeroLinux"\n'
CACHYOS_OS_RELEASE = 'NAME="CachyOS Linux"\nID=cachyos\nPRETTY_NAME="CachyOS Linux"\n'
NO_PRETTY_NAME_OS_RELEASE = 'NAME="Foo"\nID=foo\n'


def test_detect_distro_parses_id_and_pretty_name():
    distro_id, display_name = detect_distro(XEROLINUX_OS_RELEASE)
    assert distro_id == "xerolinux"
    assert display_name == "XeroLinux"


def test_detect_distro_falls_back_to_name_without_pretty_name():
    distro_id, display_name = detect_distro(NO_PRETTY_NAME_OS_RELEASE)
    assert distro_id == "foo"
    assert display_name == "Foo"


def test_detect_distro_strips_trailing_linux_word():
    distro_id, display_name = detect_distro(CACHYOS_OS_RELEASE)
    assert distro_id == "cachyos"
    assert display_name == "CachyOS"


def test_detect_distro_does_not_mangle_xerolinux():
    distro_id, display_name = detect_distro(XEROLINUX_OS_RELEASE)
    assert distro_id == "xerolinux"
    assert display_name == "XeroLinux"


def test_detect_distro_handles_missing_os_release(tmp_path, monkeypatch):
    import xsb_gui.distro_check as distro_check

    monkeypatch.setattr(distro_check, "OS_RELEASE_PATH", tmp_path / "does-not-exist")
    distro_id, display_name = detect_distro()
    assert distro_id == "unknown"
    assert display_name == "an unknown distro"


def test_maybe_warn_returns_false_and_shows_nothing_on_xerolinux():
    with patch("xsb_gui.distro_check.QMessageBox") as mock_box_cls:
        shown = maybe_warn_unsupported_distro(None, XEROLINUX_OS_RELEASE)

    assert shown is False
    mock_box_cls.assert_not_called()


def test_maybe_warn_shows_popup_with_distro_name_on_other_distro():
    mock_box = MagicMock()
    with patch("xsb_gui.distro_check.QMessageBox", return_value=mock_box) as mock_box_cls:
        shown = maybe_warn_unsupported_distro(None, CACHYOS_OS_RELEASE)

    assert shown is True
    mock_box_cls.assert_called_once()
    set_text_call = mock_box.setText.call_args[0][0]
    assert "CachyOS" in set_text_call
    assert "CachyOS Linux" not in set_text_call
    mock_box.addButton.assert_called_once()
    assert mock_box.addButton.call_args[0][0] == "I Understand"
    mock_box.exec.assert_called_once()
