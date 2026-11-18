import Toybox.Lang;
import Toybox.WatchUi;

class MainDelegate extends WatchUi.BehaviorDelegate {
    private var _app as PubCompassApp;

    public function initialize(app as PubCompassApp) {
        BehaviorDelegate.initialize();
        _app = app;
    }

    public function onNextPage() as Boolean {
        _app.cycleTarget(1);
        return true;
    }

    public function onPreviousPage() as Boolean {
        _app.cycleTarget(-1);
        return true;
    }

    public function onSelect() as Boolean {
        if (_app.getPubCount() == 0) {
            _app.retry();
        } else {
            _app.openList();
        }
        return true;
    }

    public function onMenu() as Boolean {
        _app.retry();
        return true;
    }
}
