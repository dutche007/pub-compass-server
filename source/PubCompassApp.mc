import Toybox.Application;
import Toybox.Communications;
import Toybox.Lang;
import Toybox.Position;
import Toybox.Sensor;
import Toybox.System;
import Toybox.Time;
import Toybox.Time.Gregorian;
import Toybox.Timer;
import Toybox.WatchUi;

class PubCompassApp extends Application.AppBase {
    private var _service as PubService;
    private var _compass as Compass;
    private var _timer as Timer.Timer;
    private var _pubs as Array<PubRecord> = [];
    private var _latitude as Float = 0.0;
    private var _longitude as Float = 0.0;
    private var _pendingFetchLatitude as Float = 0.0;
    private var _pendingFetchLongitude as Float = 0.0;
    private var _lastFetchRootKey as String?;
    private var _lastFetchPrefixPath as String?;
    private var _lastFetchTileKey as String?;
    private var _heading as Float? = null;
    private var _targetIndex as Number = 0;
    private var _listCursor as Number = 0;
    private var _hasFix as Boolean = false;
    private var _hasAttemptedFetch as Boolean = false;
    private var _fetching as Boolean = false;
    private var _offline as Boolean = false;
    private var _fetchErrorCode as Number? = null;
    private var _arrived as Boolean = false;
    private var _lastMinute as Number = -1;

    public function initialize() {
        AppBase.initialize();
        _service = new PubService();
        _compass = new Compass();
        _timer = new Timer.Timer();
        _pubs = _service.loadCache();

        var origin = _service.loadFetchOrigin();
        if (origin != null && origin.size() == 2) {
            updatePubsAt(origin[0], origin[1]);
        }
        updateOpeningLines();
    }

    public function onStart(state as Dictionary?) as Void {
        _timer.start(method(:onTick), 1000, true);
        Sensor.enableSensorEvents(method(:onSensor));
        Position.enableLocationEvents(Position.LOCATION_CONTINUOUS, method(:onPosition));
    }

    public function onStop(state as Dictionary?) as Void {
        Position.enableLocationEvents(Position.LOCATION_DISABLE, method(:onPosition));
        Sensor.enableSensorEvents(null);
        _timer.stop();
        _service.cancel();
    }

    public function getInitialView() as [Views] or [Views, InputDelegates] {
        var view = new $.MainView(self);
        var delegate = new $.MainDelegate(self);
        return [view, delegate];
    }

    public function onPosition(info as Position.Info) as Void {
        var position = info.position;
        if (position == null) {
            return;
        }
        if (info.accuracy < Position.QUALITY_USABLE) {
            return;
        }

        var coordinates = position.toDegrees();
        if (coordinates == null || coordinates.size() < 2) {
            return;
        }

        _latitude = coordinates[0] as Float;
        _longitude = coordinates[1] as Float;
        _hasFix = true;
        updatePubsAt(_latitude, _longitude);

        if (!_hasAttemptedFetch || shouldRefetch()) {
            startFetch();
        }

        WatchUi.requestUpdate();
    }

    public function onSensor(info as Sensor.Info) as Void {
        var heading = info.heading;
        if (heading == null) {
            return;
        }
        _heading = _compass.update(heading as Float);
    }

    public function onTick() as Void {
        var timeInfo = Gregorian.info(Time.now(), Time.FORMAT_SHORT);
        var minute = (timeInfo.hour as Number) * 60 + (timeInfo.min as Number);
        if (minute != _lastMinute) {
            _lastMinute = minute;
            updateOpeningLines();
        }
        WatchUi.requestUpdate();
    }

    public function getUiState() as Number {
        if (_pubs.size() == 0) {
            if (!_hasFix) {
                return AppState.WAIT_GPS;
            }
            if (_fetching) {
                return AppState.FETCHING;
            }
            if (_offline) {
                return AppState.FETCH_FAILED;
            }
            return AppState.NO_PUBS;
        }
        if (_arrived) {
            return AppState.ARRIVED;
        }
        if (_compass.needsCalibration()) {
            return AppState.CALIBRATE;
        }
        return AppState.TRACKING;
    }

    public function getStatusLine() as String {
        if (!_hasFix) {
            return "Finding GPS...";
        }
        if (_fetching) {
            if (_service.isWaitingForPhone()) {
                return "Waiting for phone...";
            }
            return "Loading map...";
        }
        if (_offline) {
            return "Offline";
        }
        return "";
    }

    public function getFetchErrorTitle() as String {
        if (_fetchErrorCode == null) {
            return "Data source failed";
        }
        return PubService.getErrorTitle(_fetchErrorCode as Number);
    }

    public function getFetchErrorDetail() as String {
        if (_fetchErrorCode == null) {
            return "Unknown error";
        }
        if (_fetchErrorCode == Communications.INVALID_HTTP_BODY_IN_NETWORK_RESPONSE) {
            return _service.getLastRequestType() + " text -400";
        }
        return PubService.getErrorDetail(_fetchErrorCode as Number);
    }

    public function getPubCount() as Number {
        return _pubs.size();
    }

    public function getPubs() as Array<PubRecord> {
        return _pubs;
    }

    public function getTargetIndex() as Number {
        return _targetIndex;
    }

    public function getTarget() as PubRecord? {
        if (_pubs.size() == 0 || _targetIndex >= _pubs.size()) {
            return null;
        }
        return _pubs[_targetIndex];
    }

    public function getHeading() as Float? {
        return _heading;
    }

    public function isOffline() as Boolean {
        return _offline;
    }

    public function cycleTarget(delta as Number) as Void {
        if (_pubs.size() == 0) {
            return;
        }
        _targetIndex = (_targetIndex + delta + _pubs.size()) % _pubs.size();
        updateArrivalState();
        WatchUi.requestUpdate();
    }

    public function openList() as Void {
        if (_pubs.size() == 0) {
            return;
        }
        _listCursor = _targetIndex;
        var view = new $.PubListView(self);
        var delegate = new $.PubListDelegate(self);
        WatchUi.pushView(view, delegate, WatchUi.SLIDE_UP);
    }

    public function getListCursor() as Number {
        return _listCursor;
    }

    public function moveListCursor(delta as Number) as Void {
        if (_pubs.size() == 0) {
            return;
        }
        _listCursor = (_listCursor + delta + _pubs.size()) % _pubs.size();
        WatchUi.requestUpdate();
    }

    public function selectListCursor() as Void {
        if (_pubs.size() == 0) {
            return;
        }
        _targetIndex = _listCursor;
        updateArrivalState();
        WatchUi.popView(WatchUi.SLIDE_DOWN);
    }

    public function retry() as Void {
        _offline = false;
        _hasAttemptedFetch = false;
        if (_hasFix) {
            startFetch();
        } else {
            WatchUi.requestUpdate();
        }
    }

    public function onFetchComplete(pubs as Array<PubRecord>?, result as Number) as Void {
        _fetching = false;
        _hasAttemptedFetch = true;

        if (result == PubService.RESULT_OK && pubs != null) {
            _offline = false;
            _fetchErrorCode = null;
            _pubs = pubs;
            updateOpeningLines();
            updatePubsAt(_latitude, _longitude);
            _targetIndex = 0;
            _arrived = false;
            _service.saveCache(_pubs, _pendingFetchLatitude, _pendingFetchLongitude);
            _lastFetchRootKey = PubService.getRootKey(_pendingFetchLatitude, _pendingFetchLongitude);
            _lastFetchPrefixPath = PubService.getIndexPrefixPath(_pendingFetchLatitude, _pendingFetchLongitude);
            _lastFetchTileKey = _service.getTileKey(_pendingFetchLatitude, _pendingFetchLongitude);
        } else if (result == PubService.RESULT_NO_PUBS) {
            _offline = false;
            _fetchErrorCode = null;
            _pubs = [];
            _targetIndex = 0;
            _arrived = false;
            _lastFetchRootKey = PubService.getRootKey(_pendingFetchLatitude, _pendingFetchLongitude);
            _lastFetchPrefixPath = PubService.getIndexPrefixPath(_pendingFetchLatitude, _pendingFetchLongitude);
            _lastFetchTileKey = _service.getTileKey(_pendingFetchLatitude, _pendingFetchLongitude);
            System.println("No pubs in tile: " + _service.getLastRequestKey());
        } else {
            _offline = true;
            _fetchErrorCode = result;
            _lastFetchRootKey = PubService.getRootKey(_pendingFetchLatitude, _pendingFetchLongitude);
            _lastFetchPrefixPath = PubService.getIndexPrefixPath(_pendingFetchLatitude, _pendingFetchLongitude);
            _lastFetchTileKey = _service.getTileKey(_pendingFetchLatitude, _pendingFetchLongitude);
            System.println("Pub fetch failed: " + _service.getLastRequestKey() + " code " + result.toString());
        }
        WatchUi.requestUpdate();
    }

    private function startFetch() as Void {
        if (!_hasFix || _fetching) {
            return;
        }
        _fetching = true;
        _offline = false;
        _fetchErrorCode = null;
        _hasAttemptedFetch = true;
        _pendingFetchLatitude = _latitude;
        _pendingFetchLongitude = _longitude;
        _lastFetchRootKey = PubService.getRootKey(_pendingFetchLatitude, _pendingFetchLongitude);
        _lastFetchPrefixPath = PubService.getIndexPrefixPath(_pendingFetchLatitude, _pendingFetchLongitude);
        _service.fetch(_latitude, _longitude, method(:onFetchComplete));
        WatchUi.requestUpdate();
    }

    private function shouldRefetch() as Boolean {
        var rootKey = PubService.getRootKey(_latitude, _longitude);
        var prefixPath = PubService.getIndexPrefixPath(_latitude, _longitude);
        if (_lastFetchRootKey == null || rootKey != _lastFetchRootKey ||
            _lastFetchPrefixPath == null || prefixPath != _lastFetchPrefixPath) {
            return true;
        }
        var tileKey = _service.getTileKey(_latitude, _longitude);
        if (tileKey == null) {
            return false;
        }
        return _lastFetchTileKey == null || tileKey != _lastFetchTileKey;
    }

    private function updatePubsAt(latitude as Float, longitude as Float) as Void {
        for (var pubIndex = 0; pubIndex < _pubs.size(); pubIndex++) {
            var pub = _pubs[pubIndex];
            pub.updatePosition(latitude, longitude);
        }

        var remaining = _pubs;
        var sorted = [];
        while (remaining.size() > 0) {
            var nearestIndex = 0;
            for (var index = 1; index < remaining.size(); index++) {
                if (remaining[index].getDistance() < remaining[nearestIndex].getDistance()) {
                    nearestIndex = index;
                }
            }
            sorted.add(remaining[nearestIndex]);
            remaining.remove(remaining[nearestIndex]);
        }
        _pubs = sorted;

        while (_pubs.size() > 10) {
            _pubs.remove(_pubs[_pubs.size() - 1]);
        }

        if (_targetIndex >= _pubs.size()) {
            _targetIndex = 0;
        }
        updateArrivalState();
    }

    private function updateOpeningLines() as Void {
        for (var pubIndex = 0; pubIndex < _pubs.size(); pubIndex++) {
            var pub = _pubs[pubIndex];
            pub.updateOpeningText();
        }
    }

    private function updateArrivalState() as Void {
        if (!_hasFix) {
            _arrived = false;
            return;
        }
        var target = getTarget();
        if (target == null) {
            _arrived = false;
        } else if (!_arrived && target.getDistance() < 30.0) {
            _arrived = true;
        } else if (_arrived && target.getDistance() > 50.0) {
            _arrived = false;
        }
    }
}
