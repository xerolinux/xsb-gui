from unittest.mock import MagicMock, patch

from xsb_gui.esp_size_check import ESP_MIN_SIZE_BYTES, is_esp_too_small, show_esp_too_small_popup


def test_is_esp_too_small_true_below_floor():
    assert is_esp_too_small(500 * 1024 * 1024) is True


def test_is_esp_too_small_false_at_or_above_floor():
    assert is_esp_too_small(ESP_MIN_SIZE_BYTES) is False
    assert is_esp_too_small(ESP_MIN_SIZE_BYTES * 2) is False


def test_is_esp_too_small_false_when_unknown():
    assert is_esp_too_small(0) is False
    assert is_esp_too_small(None) is False


def test_show_esp_too_small_popup_shows_size_and_quits_app():
    mock_box = MagicMock()
    mock_app = MagicMock()
    with patch("xsb_gui.esp_size_check.QMessageBox", return_value=mock_box) as mock_box_cls, \
            patch("xsb_gui.esp_size_check.QApplication") as mock_app_cls:
        mock_app_cls.instance.return_value = mock_app
        show_esp_too_small_popup(None, 500 * 1024 * 1024)

    mock_box_cls.assert_called_once()
    set_text_call = mock_box.setText.call_args[0][0]
    assert "500&nbsp;MiB" in set_text_call
    mock_box.addButton.assert_called_once()
    assert mock_box.addButton.call_args[0][0] == "Dang It, Ok !"
    mock_box.exec.assert_called_once()
    mock_app.quit.assert_called_once()
