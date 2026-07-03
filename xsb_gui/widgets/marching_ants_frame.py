from PyQt6.QtCore import QPointF, QRectF, Qt, QTimer
from PyQt6.QtGui import QColor, QLinearGradient, QPainter, QPainterPath, QPen, QRadialGradient
from PyQt6.QtWidgets import QFrame, QGraphicsDropShadowEffect, QLabel, QVBoxLayout

FILL_PINK = QColor(150, 40, 100, 90)
FILL_BLUE = QColor(40, 70, 150, 90)
BORDER_PINK = QColor(200, 70, 130)
BORDER_BLUE = QColor(70, 110, 190)
GLOW_COLOR = QColor(120, 80, 150, 100)
GLOW_BLUR_RADIUS = 22
CORNER_RADIUS = 16
DASH_PATTERN = [6, 4]
FRAME_INTERVAL_MS = 60

SIREN_COLORS = [QColor(255, 30, 30), QColor(30, 90, 255)]
SIREN_INTERVAL_MS = 220
SIREN_RADIUS = 6.0
SIREN_MARGIN = 12.0


class MarchingAntsFrame(QFrame):
    """Rounded, filled frame with a border whose dashes continuously travel
    around the perimeter (a "marching ants" outline). Chosen over a pulsating
    glow/opacity animation because a moving outline reads as "active warning"
    without the breathing effect a pulse implies.
    """

    def __init__(self, text, parent=None):
        super().__init__(parent)
        self._dash_offset = 0.0
        self._siren_index = 0

        layout = QVBoxLayout(self)
        layout.setContentsMargins(22, 10, 22, 10)
        self.label = QLabel(text)
        self.label.setWordWrap(True)
        self.label.setStyleSheet(
            "color: white; font-weight: bold; font-size: 11pt; background: transparent;"
        )
        layout.addWidget(self.label)

        glow = QGraphicsDropShadowEffect(self)
        glow.setBlurRadius(GLOW_BLUR_RADIUS)
        glow.setOffset(0, 0)
        glow.setColor(GLOW_COLOR)
        self.setGraphicsEffect(glow)

        self._timer = QTimer(self)
        self._timer.timeout.connect(self._advance)
        self._timer.start(FRAME_INTERVAL_MS)

        self._siren_timer = QTimer(self)
        self._siren_timer.timeout.connect(self._toggle_siren)
        self._siren_timer.start(SIREN_INTERVAL_MS)

    def _advance(self):
        self._dash_offset = (self._dash_offset - 1) % sum(DASH_PATTERN)
        self.update()

    def _toggle_siren(self):
        self._siren_index = (self._siren_index + 1) % len(SIREN_COLORS)
        self.update()

    def paintEvent(self, event):
        painter = QPainter(self)
        painter.setRenderHint(QPainter.RenderHint.Antialiasing)

        rect = QRectF(self.rect().adjusted(1, 1, -1, -1))
        path = QPainterPath()
        path.addRoundedRect(rect, CORNER_RADIUS, CORNER_RADIUS)

        fill_gradient = QLinearGradient(rect.topLeft(), rect.bottomRight())
        fill_gradient.setColorAt(0.0, FILL_PINK)
        fill_gradient.setColorAt(1.0, FILL_BLUE)
        painter.fillPath(path, fill_gradient)

        border_gradient = QLinearGradient(rect.topLeft(), rect.bottomRight())
        border_gradient.setColorAt(0.0, BORDER_PINK)
        border_gradient.setColorAt(1.0, BORDER_BLUE)

        pen = QPen(border_gradient, 2.0)
        pen.setDashPattern(DASH_PATTERN)
        pen.setDashOffset(self._dash_offset)
        painter.setPen(pen)
        painter.drawPath(path)

        self._paint_siren(painter, rect)

        super().paintEvent(event)

    def _paint_siren(self, painter, rect):
        center = QPointF(rect.right() - SIREN_MARGIN, rect.top() + SIREN_MARGIN)
        color = SIREN_COLORS[self._siren_index]

        halo = QRadialGradient(center, SIREN_RADIUS * 2.2)
        halo.setColorAt(0.0, color.lighter(140))
        edge = QColor(color)
        edge.setAlpha(0)
        halo.setColorAt(1.0, edge)
        painter.setPen(Qt.PenStyle.NoPen)
        painter.setBrush(halo)
        painter.drawEllipse(center, SIREN_RADIUS * 2.2, SIREN_RADIUS * 2.2)

        painter.setBrush(color)
        painter.drawEllipse(center, SIREN_RADIUS, SIREN_RADIUS)

        highlight = QColor(255, 255, 255, 190)
        painter.setBrush(highlight)
        painter.drawEllipse(
            QPointF(center.x() - SIREN_RADIUS * 0.3, center.y() - SIREN_RADIUS * 0.3),
            SIREN_RADIUS * 0.3,
            SIREN_RADIUS * 0.3,
        )
