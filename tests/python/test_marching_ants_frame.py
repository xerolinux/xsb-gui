from xsb_gui.widgets.marching_ants_frame import MarchingAntsFrame


def test_frame_shows_given_text(qtbot):
    frame = MarchingAntsFrame("<p>hello</p>")
    qtbot.addWidget(frame)
    assert frame.label.text() == "<p>hello</p>"


def test_dash_offset_advances_on_timer_tick(qtbot):
    frame = MarchingAntsFrame("<p>hello</p>")
    qtbot.addWidget(frame)
    before = frame._dash_offset

    frame._advance()

    assert frame._dash_offset != before


def test_dash_offset_wraps_within_dash_pattern_length(qtbot):
    frame = MarchingAntsFrame("<p>hello</p>")
    qtbot.addWidget(frame)

    for _ in range(50):
        frame._advance()

    assert 0 <= frame._dash_offset < 10


def test_siren_index_toggles_between_two_colors(qtbot):
    frame = MarchingAntsFrame("<p>hello</p>")
    qtbot.addWidget(frame)
    before = frame._siren_index

    frame._toggle_siren()

    assert frame._siren_index != before
    assert frame._siren_index in (0, 1)
