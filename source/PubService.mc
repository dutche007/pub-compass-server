import Toybox.Application.Storage;
import Toybox.Communications;
import Toybox.Lang;
import Toybox.Math;
import Toybox.System;
import Toybox.Timer;
import Toybox.Time;

class PubService {
    static const RESULT_OK = 0;
    static const RESULT_NO_PUBS = 404;
    static const RESULT_INVALID_RESPONSE = -10000;

    private static const PAGES_BASE_URL = "https://dutche007.github.io/pub-compass-server/";

    private var _latitude as Float = 0.0;
    private var _longitude as Float = 0.0;
    private var _rootKey as String = "";
    private var _indexRoot as String?;
    private var _indexPrefixPath as String?;
    private var _prefixPath as String = "";
    private var _splitPaths as Array<String> = [];
    private var _lastRequestKey as String = "";
    private var _done as Method?;
    private var _retryTimer as Timer.Timer;
    private var _busy as Boolean = false;
    private var _phoneRetryCount as Number = 0;
    private var _waitingForPhone as Boolean = false;
    private var _loadingIndex as Boolean = false;

    public function initialize() {
        _retryTimer = new Timer.Timer();
    }

    public function loadCache() as Array<PubRecord> {
        var pubs = [];
        var savedCountValue = Storage.getValue("pubCount");
        if (savedCountValue == null) {
            return pubs;
        }
        var savedCount = savedCountValue as Number;
        if (savedCount < 1) {
            return pubs;
        }

        for (var recordIndex = 0; recordIndex < savedCount && recordIndex < 10; recordIndex++) {
            var prefix = "pub" + recordIndex.toString();
            var lat = Storage.getValue(prefix + "Lat");
            var lon = Storage.getValue(prefix + "Lon");
            if (lat == null || lon == null) {
                continue;
            }
            var name = Storage.getValue(prefix + "Name") as String?;
            var hours = Storage.getValue(prefix + "Hours") as String?;
            pubs.add(new PubRecord(name, lat as Float, lon as Float, hours));
        }
        return pubs;
    }

    public function loadFetchOrigin() as Array<Float>? {
        var latitude = Storage.getValue("fetchLat");
        var longitude = Storage.getValue("fetchLon");
        if (latitude == null || longitude == null) {
            return null;
        }
        return [latitude as Float, longitude as Float];
    }

    public function saveCache(pubs as Array<PubRecord>, latitude as Float, longitude as Float) as Void {
        var savedCount = pubs.size();
        if (savedCount > 10) {
            savedCount = 10;
        }
        for (var pubIndex = 0; pubIndex < savedCount; pubIndex++) {
            var pub = pubs[pubIndex];
            var prefix = "pub" + pubIndex.toString();
            Storage.setValue(prefix + "Name", pub.getRawName());
            Storage.setValue(prefix + "Lat", pub.getLatitude());
            Storage.setValue(prefix + "Lon", pub.getLongitude());
            Storage.setValue(prefix + "Hours", pub.getOpeningHours());
        }
        Storage.setValue("pubCount", savedCount);
        Storage.setValue("fetchLat", latitude);
        Storage.setValue("fetchLon", longitude);
        Storage.setValue("fetchTime", Time.now().value());
    }

    public function fetch(latitude as Float, longitude as Float, callback as Method) as Void {
        if (_busy) {
            return;
        }
        _latitude = latitude;
        _longitude = longitude;
        _rootKey = getRootKey(latitude, longitude);
        _prefixPath = getIndexPrefixPath(latitude, longitude);
        _phoneRetryCount = 0;
        _waitingForPhone = false;
        _done = callback;
        _busy = true;

        if (_indexRoot != _rootKey || _indexPrefixPath != _prefixPath) {
            requestIndex();
        } else {
            requestTile();
        }
    }

    public function cancel() as Void {
        _retryTimer.stop();
        _busy = false;
        _waitingForPhone = false;
        _done = null;
    }

    public function isWaitingForPhone() as Boolean {
        return _waitingForPhone;
    }

    public function getLastRequestKey() as String {
        return _lastRequestKey;
    }

    public function getLastRequestType() as String {
        return _loadingIndex ? "Index" : "Tile";
    }

    public function getTileKey(latitude as Float, longitude as Float) as String? {
        var root = getRootKey(latitude, longitude);
        if (_indexRoot == null || _indexRoot != root ||
            _indexPrefixPath != getIndexPrefixPath(latitude, longitude)) {
            return null;
        }
        var path = resolvePath(latitude, longitude);
        return root + "/" + (path.length() == 0 ? "root" : path);
    }

    public static function getRootKey(latitude as Float, longitude as Float) as String {
        var latDegree = Math.floor(latitude) as Number;
        var lonDegree = Math.floor(longitude) as Number;
        return latDegree.toString() + "_" + lonDegree.toString();
    }

    public static function getIndexPrefixPath(latitude as Float, longitude as Float) as String {
        var minLatitude = Math.floor(latitude) as Float;
        var minLongitude = Math.floor(longitude) as Float;
        var maxLatitude = minLatitude + 1.0;
        var maxLongitude = minLongitude + 1.0;
        var prefix = "";

        for (var depth = 0; depth < 3; depth++) {
            var middleLatitude = (minLatitude + maxLatitude) / 2.0;
            var middleLongitude = (minLongitude + maxLongitude) / 2.0;
            var child = 0;
            if (latitude >= middleLatitude) {
                child += 2;
                minLatitude = middleLatitude;
            } else {
                maxLatitude = middleLatitude;
            }
            if (longitude >= middleLongitude) {
                child += 1;
                minLongitude = middleLongitude;
            } else {
                maxLongitude = middleLongitude;
            }
            prefix += child.toString();
        }
        return prefix;
    }

    public static function getErrorTitle(error as Number) as String {
        if (error == Communications.BLE_CONNECTION_UNAVAILABLE) {
            return "Phone unavailable";
        }
        if (error == Communications.BLE_HOST_TIMEOUT ||
            error == Communications.BLE_SERVER_TIMEOUT ||
            error == Communications.NETWORK_REQUEST_TIMED_OUT) {
            return "Timed out";
        }
        if (error == Communications.BLE_REQUEST_TOO_LARGE) {
            return "Request too large";
        }
        if (error == RESULT_INVALID_RESPONSE) {
            return "Bad data";
        }
        if (error == Communications.INVALID_HTTP_BODY_IN_NETWORK_RESPONSE) {
            return "Bad response";
        }
        if (error < 0) {
            return "Network error";
        }
        return "Source failed";
    }

    public static function getErrorDetail(error as Number) as String {
        if (error == RESULT_INVALID_RESPONSE) {
            return "Invalid tile data";
        }
        if (error == Communications.INVALID_HTTP_BODY_IN_NETWORK_RESPONSE) {
            return "Text error -400";
        }
        if (error == Communications.NETWORK_REQUEST_TIMED_OUT) {
            return "Timeout -300";
        }
        if (error < 0) {
            return "Code " + error.toString();
        }
        return "HTTP " + error.toString();
    }

    private function requestIndex() as Void {
        _loadingIndex = true;
        _lastRequestKey = "index/" + _rootKey + "/" + _prefixPath + ".txt";
        requestUrl(PAGES_BASE_URL + _lastRequestKey);
    }

    private function requestTile() as Void {
        _loadingIndex = false;
        var path = resolvePath(_latitude, _longitude);
        var filename = path.length() == 0 ? "root.txt" : "p" + path + ".txt";
        _lastRequestKey = "tiles/" + _rootKey + "/" + filename;
        requestUrl(PAGES_BASE_URL + _lastRequestKey);
    }

    private function requestUrl(url as String) as Void {
        var options = {
            :responseType => Communications.HTTP_RESPONSE_CONTENT_TYPE_TEXT_PLAIN
        };
        Communications.makeWebRequest(url, null, options, method(:onResponse));
    }

    public function onResponse(responseCode as Number, data as Dictionary or String or Null) as Void {
        if (!_busy) {
            return;
        }

        if (responseCode == Communications.BLE_CONNECTION_UNAVAILABLE) {
            if (_phoneRetryCount < 1) {
                _phoneRetryCount++;
                _waitingForPhone = true;
                _retryTimer.start(method(:retryAfterBackoff), 5000, false);
            } else {
                finish(null, responseCode);
            }
            return;
        }

        if (responseCode == 404) {
            System.println("Pub map empty: " + _lastRequestKey + " HTTP 404");
            finish([], RESULT_NO_PUBS);
            return;
        }
        if (responseCode != 200) {
            finish(null, responseCode);
            return;
        }
        if (!(data instanceof String)) {
            finish(null, RESULT_INVALID_RESPONSE);
            return;
        }

        if (_loadingIndex) {
            if (!parseIndex(data as String)) {
                finish(null, RESULT_INVALID_RESPONSE);
                return;
            }
            _indexRoot = _rootKey;
            _indexPrefixPath = _prefixPath;
            requestTile();
            return;
        }

        var pubs = parseTile(data as String);
        if (pubs == null) {
            finish(null, RESULT_INVALID_RESPONSE);
            return;
        }
        finish(pubs, RESULT_OK);
    }

    private function parseIndex(data as String) as Boolean {
        var lines = splitText(data, "\n");
        if (lines.size() < 2 || lines[0] != "I1") {
            return false;
        }
        var splitCount = lines[1].toNumber();
        if (splitCount == null || splitCount < 0 || lines.size() < splitCount + 2) {
            return false;
        }
        var splitPaths = [];
        for (var index = 0; index < splitCount; index++) {
            splitPaths.add(lines[index + 2]);
        }
        _splitPaths = splitPaths;
        return true;
    }

    private function resolvePath(latitude as Float, longitude as Float) as String {
        var minLatitude = Math.floor(latitude) as Float;
        var minLongitude = Math.floor(longitude) as Float;
        var maxLatitude = minLatitude + 1.0;
        var maxLongitude = minLongitude + 1.0;
        var path = "";
        for (var prefixIndex = 0; prefixIndex < _prefixPath.length(); prefixIndex++) {
            var prefixDigit = _prefixPath.substring(prefixIndex, prefixIndex + 1) as String;
            var prefixChild = 0;
            if (prefixDigit == "1") {
                prefixChild = 1;
            } else if (prefixDigit == "2") {
                prefixChild = 2;
            } else if (prefixDigit == "3") {
                prefixChild = 3;
            }
            var prefixMiddleLatitude = (minLatitude + maxLatitude) / 2.0;
            var prefixMiddleLongitude = (minLongitude + maxLongitude) / 2.0;
            if (prefixChild >= 2) {
                minLatitude = prefixMiddleLatitude;
            } else {
                maxLatitude = prefixMiddleLatitude;
            }
            if (prefixChild % 2 == 1) {
                minLongitude = prefixMiddleLongitude;
            } else {
                maxLongitude = prefixMiddleLongitude;
            }
            path += prefixChild.toString();
        }
        var searching = true;
        var depth = 0;

        while (searching && depth < 20) {
            var isSplit = false;
            var suffix = path.substring(_prefixPath.length(), path.length()) as String;
            for (var index = 0; index < _splitPaths.size(); index++) {
                if (_splitPaths[index] == suffix) {
                    isSplit = true;
                    break;
                }
            }
            if (!isSplit) {
                searching = false;
            } else {
                var middleLatitude = (minLatitude + maxLatitude) / 2.0;
                var middleLongitude = (minLongitude + maxLongitude) / 2.0;
                var child = 0;
                if (latitude >= middleLatitude) {
                    child += 2;
                    minLatitude = middleLatitude;
                } else {
                    maxLatitude = middleLatitude;
                }
                if (longitude >= middleLongitude) {
                    child += 1;
                    minLongitude = middleLongitude;
                } else {
                    maxLongitude = middleLongitude;
                }
                path += child.toString();
                depth++;
            }
        }
        return path;
    }

    private function parseTile(data as String) as Array<PubRecord>? {
        var lines = splitText(data, "\n");
        if (lines.size() < 3 || lines[0] != "T1") {
            return null;
        }
        var pubCount = lines[2].toNumber();
        if (pubCount == null || pubCount < 0 || pubCount > 40 ||
            lines.size() < pubCount + 3) {
            return null;
        }

        var pubs = [];
        for (var index = 0; index < pubCount; index++) {
            var fields = splitText(lines[index + 3], "\t");
            if (fields.size() != 4) {
                return null;
            }
            var latitudeValue = fields[1].toNumber();
            var longitudeValue = fields[2].toNumber();
            if (latitudeValue == null || longitudeValue == null) {
                return null;
            }
            var name = fields[0].length() == 0 ? null : fields[0];
            var latitude = (latitudeValue as Float) / 10000000.0;
            var longitude = (longitudeValue as Float) / 10000000.0;
            var hours = fields[3].length() == 0 ? null : fields[3];
            pubs.add(new PubRecord(name, latitude, longitude, hours));
        }
        return pubs;
    }

    private function splitText(value as String, delimiter as String) as Array<String> {
        var parts = [];
        var partStart = 0;
        for (var index = 0; index < value.length(); index++) {
            if (value.substring(index, index + 1) == delimiter) {
                parts.add(value.substring(partStart, index) as String);
                partStart = index + 1;
            }
        }
        parts.add(value.substring(partStart, value.length()) as String);
        return parts;
    }

    public function retryAfterBackoff() as Void {
        _waitingForPhone = false;
        if (_busy) {
            if (_loadingIndex) {
                requestIndex();
            } else {
                requestTile();
            }
        }
    }

    private function finish(pubs as Array<PubRecord>?, result as Number) as Void {
        _busy = false;
        var callback = _done;
        _done = null;
        if (callback != null) {
            callback.invoke(pubs, result);
        }
    }
}
