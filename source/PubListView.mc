import Toybox.Graphics;
import Toybox.Lang;
import Toybox.WatchUi;

class PubListView extends WatchUi.View {
    private var _app as PubCompassApp;

    public function initialize(app as PubCompassApp) {
        View.initialize();
        _app = app;
    }

    public function onUpdate(dc as Dc) as Void {
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_BLACK);
        dc.clear();
        var title = _app.isOffline() ? "Nearest pubs - offline" : "Nearest pubs";
        dc.drawText(dc.getWidth() / 2, 2, Graphics.FONT_SMALL, title, Graphics.TEXT_JUSTIFY_CENTER);

        var pubs = _app.getPubs();
        var count = pubs.size();
        var cursor = _app.getListCursor();
        var start = cursor - 1;
        if (start < 0) {
            start = 0;
        }
        if (start > count - 3) {
            start = count - 3;
        }
        if (start < 0) {
            start = 0;
        }

        for (var row = 0; row < 3; row++) {
            var index = start + row;
            if (index >= count) {
                break;
            }
            drawRow(dc, pubs[index], index, cursor == index, 25 + row * 37);
        }

        dc.drawText(dc.getWidth() / 2, dc.getHeight() - 16, Graphics.FONT_TINY,
            "© OpenStreetMap contributors", Graphics.TEXT_JUSTIFY_CENTER);
    }

    private function drawRow(dc as Dc, pub as PubRecord, index as Number, selected as Boolean, top as Number) as Void {
        if (selected) {
            dc.drawLine(4, top + 5, 10, top + 9);
            dc.drawLine(10, top + 9, 4, top + 13);
            dc.drawLine(4, top + 13, 4, top + 5);
        }

        var name = pub.getDisplayName(13);
        dc.drawText(14, top, Graphics.FONT_SMALL, name, Graphics.TEXT_JUSTIFY_LEFT);
        dc.drawText(dc.getWidth() - 5, top, Graphics.FONT_TINY, pub.getDistanceText(), Graphics.TEXT_JUSTIFY_RIGHT);
        dc.drawText(14, top + 16, Graphics.FONT_TINY, pub.getOpeningText(), Graphics.TEXT_JUSTIFY_LEFT);
    }
}
