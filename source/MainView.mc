import Toybox.Graphics;
import Toybox.Lang;
import Toybox.Math;
import Toybox.WatchUi;

class MainView extends WatchUi.View {
    private var _app as PubCompassApp;

    public function initialize(app as PubCompassApp) {
        View.initialize();
        _app = app;
    }

    public function onUpdate(dc as Dc) as Void {
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_BLACK);
        dc.clear();

        var state = _app.getUiState();
        if (state == AppState.WAIT_GPS && _app.getPubCount() == 0) {
            drawMessage(dc, "Finding GPS...", "");
        } else if ((state == AppState.FETCHING || state == AppState.FETCH_FAILED || state == AppState.NO_PUBS) &&
            _app.getPubCount() == 0) {
            drawEmptyState(dc, state);
        } else if (state == AppState.ARRIVED) {
            drawArrival(dc);
        } else if (state == AppState.CALIBRATE) {
            drawMessage(dc, "Calibrate compass", "Hold level; wave in a figure 8");
        } else {
            drawCompass(dc);
        }
    }

    private function drawCompass(dc as Dc) as Void {
        var width = dc.getWidth();
        var height = dc.getHeight();
        var cx = width / 2;
        var cy = height / 2;
        var radius = (width < height ? width : height) / 2 - 12;

        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_BLACK);
        dc.setPenWidth(3);
        dc.drawCircle(cx, cy, radius);
        dc.setPenWidth(1);

        var heading = _app.getHeading();
        var target = _app.getTarget();
        if (heading != null) {
            drawNorthMarker(dc, cx, cy, radius - 10, heading);
        }
        if (target != null && heading != null) {
            drawDirection(dc, cx, cy, radius, target.getBearing(), heading);
        }

        if (target == null) {
            dc.drawText(cx, cy - 14, Graphics.FONT_SMALL, "Finding pubs...", Graphics.TEXT_JUSTIFY_CENTER);
            return;
        }

        dc.drawText(cx, cy - 31, Graphics.FONT_LARGE, target.getDistanceText(), Graphics.TEXT_JUSTIFY_CENTER);
        dc.drawText(cx, cy - 8, Graphics.FONT_SMALL, target.getDisplayName(14), Graphics.TEXT_JUSTIFY_CENTER);
        dc.drawText(cx, cy + 10, Graphics.FONT_TINY, target.getOpeningText(), Graphics.TEXT_JUSTIFY_CENTER);
        dc.drawText(cx, cy + 27, Graphics.FONT_TINY,
            (_app.getTargetIndex() + 1).toString() + "/10",
            Graphics.TEXT_JUSTIFY_CENTER);

        var status = _app.getStatusLine();
        if (status.length() > 0) {
            dc.drawText(cx, height - 27, Graphics.FONT_TINY, status, Graphics.TEXT_JUSTIFY_CENTER);
        }
        dc.drawText(cx, height - 9, Graphics.FONT_TINY,
            "© OpenStreetMap contributors", Graphics.TEXT_JUSTIFY_CENTER);
    }

    private function drawNorthMarker(dc as Dc, cx as Number, cy as Number, radius as Number, heading as Float) as Void {
        var angle = -heading * GeoMath.PI / 180.0;
        var x = cx + Math.sin(angle) * radius;
        var y = cy - Math.cos(angle) * radius;
        dc.drawText(x, y - 5, Graphics.FONT_TINY, "N", Graphics.TEXT_JUSTIFY_CENTER);
    }

    private function drawDirection(dc as Dc, cx as Number, cy as Number, radius as Number, bearing as Float, heading as Float) as Void {
        var angle = (bearing - heading) * GeoMath.PI / 180.0;
        var dotRadius = radius - 3;
        var dotX = cx + Math.sin(angle) * dotRadius;
        var dotY = cy - Math.cos(angle) * dotRadius;
        var barStart = radius - 5;
        var barEnd = radius - 23;
        var startX = cx + Math.sin(angle) * barStart;
        var startY = cy - Math.cos(angle) * barStart;
        var endX = cx + Math.sin(angle) * barEnd;
        var endY = cy - Math.cos(angle) * barEnd;

        dc.setPenWidth(4);
        dc.drawLine(startX, startY, endX, endY);
        dc.fillCircle(dotX, dotY, 5);
        dc.fillCircle(startX, startY, 2);
        dc.fillCircle(endX, endY, 2);
        dc.setPenWidth(1);
    }

    private function drawEmptyState(dc as Dc, state as Number) as Void {
        if (state == AppState.NO_PUBS) {
            drawMessage(dc, "No pubs found", "Nothing within 10 km");
            dc.drawText(dc.getWidth() / 2, dc.getHeight() / 2 + 34, Graphics.FONT_TINY,
                "Press Start to retry", Graphics.TEXT_JUSTIFY_CENTER);
        } else if (state == AppState.FETCH_FAILED) {
            drawMessage(dc, _app.getFetchErrorTitle(), _app.getFetchErrorDetail());
            dc.drawText(dc.getWidth() / 2, dc.getHeight() / 2 + 34, Graphics.FONT_TINY,
                "Press Start to retry", Graphics.TEXT_JUSTIFY_CENTER);
        } else if (state == AppState.FETCHING) {
            drawMessage(dc, _app.getStatusLine(), "");
        } else {
            drawMessage(dc, "Looking for pubs...", "");
        }
    }

    private function drawMessage(dc as Dc, first as String, second as String) as Void {
        var cx = dc.getWidth() / 2;
        var cy = dc.getHeight() / 2;
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_BLACK);
        dc.drawText(cx, cy - 14, Graphics.FONT_MEDIUM, first, Graphics.TEXT_JUSTIFY_CENTER);
        if (second.length() > 0) {
            dc.drawText(cx, cy + 12, Graphics.FONT_SMALL, second, Graphics.TEXT_JUSTIFY_CENTER);
        }
    }

    private function drawArrival(dc as Dc) as Void {
        var cx = dc.getWidth() / 2;
        var top = 29;
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_BLACK);
        dc.drawLine(cx - 8, top, cx + 8, top);
        dc.drawLine(cx - 7, top + 1, cx - 4, top + 30);
        dc.drawLine(cx + 7, top + 1, cx + 4, top + 30);
        dc.drawLine(cx - 4, top + 30, cx + 4, top + 30);
        dc.drawLine(cx + 8, top + 7, cx + 14, top + 9);
        dc.drawLine(cx + 14, top + 9, cx + 14, top + 21);
        dc.drawLine(cx + 14, top + 21, cx + 5, top + 21);
        dc.drawText(cx, 76, Graphics.FONT_MEDIUM, "You're here", Graphics.TEXT_JUSTIFY_CENTER);

        var target = _app.getTarget();
        if (target != null) {
            dc.drawText(cx, 102, Graphics.FONT_SMALL, target.getDisplayName(14), Graphics.TEXT_JUSTIFY_CENTER);
        }
        dc.drawText(cx, dc.getHeight() - 9, Graphics.FONT_TINY,
            "© OpenStreetMap contributors", Graphics.TEXT_JUSTIFY_CENTER);
    }
}
