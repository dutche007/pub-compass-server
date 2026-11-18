import Toybox.Lang;
import Toybox.WatchUi;

class PubListDelegate extends WatchUi.BehaviorDelegate {
    private var _app as PubCompassApp;

    public function initialize(app as PubCompassApp) {
        BehaviorDelegate.initialize();
        _app = app;
    }

    public function onNextPage() as Boolean {
        _app.moveListCursor(1);
        return true;
    }

    public function onPreviousPage() as Boolean {
        _app.moveListCursor(-1);
        return true;
    }

    public function onSelect() as Boolean {
        _app.selectListCursor();
        return true;
    }
}
