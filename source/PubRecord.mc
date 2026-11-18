import Toybox.Lang;
import Toybox.Math;

class PubRecord {
    private var _name as String?;
    private var _latitude as Float;
    private var _longitude as Float;
    private var _openingHours as String?;
    private var _distance as Float = 0.0;
    private var _bearing as Float = 0.0;
    private var _lastDisplayedDistance as Float = -1.0;
    private var _distanceText as String = "";
    private var _openingText as String = "Hours unknown";

    public function initialize(name as String?, latitude as Float, longitude as Float, openingHours as String?) {
        _name = name;
        _latitude = latitude;
        _longitude = longitude;
        _openingHours = openingHours;
    }

    public function updatePosition(latitude as Float, longitude as Float) as Void {
        _distance = GeoMath.distanceMeters(latitude, longitude, _latitude, _longitude);
        _bearing = GeoMath.initialBearing(latitude, longitude, _latitude, _longitude);

        var distanceDelta = _distance - _lastDisplayedDistance;
        if (distanceDelta < 0.0) {
            distanceDelta = -distanceDelta;
        }
        if (_lastDisplayedDistance < 0.0 || distanceDelta > 5.0) {
            _lastDisplayedDistance = _distance;
            _distanceText = formatDistance(_distance);
        }
    }

    public function updateOpeningText() as Void {
        _openingText = OpeningHours.describe(_openingHours);
    }

    public function getName() as String {
        if (_name == null || _name.length() == 0) {
            return "Unnamed pub";
        }
        return _name as String;
    }

    public function getDisplayName(maxCharacters as Number) as String {
        var displayName = getName();
        if (displayName.length() > maxCharacters) {
            return displayName.substring(0, maxCharacters) as String;
        }
        return displayName;
    }

    public function getDistance() as Float {
        return _distance;
    }

    public function getLatitude() as Float {
        return _latitude;
    }

    public function getLongitude() as Float {
        return _longitude;
    }

    public function getRawName() as String? {
        return _name;
    }

    public function getOpeningHours() as String? {
        return _openingHours;
    }

    public function getDistanceText() as String {
        return _distanceText;
    }

    public function getBearing() as Float {
        return _bearing;
    }

    public function getOpeningText() as String {
        return _openingText;
    }

    private function formatDistance(distance as Float) as String {
        if (distance < 1000.0) {
            return Math.round(distance).toString() + " m";
        }

        if (distance < 10000.0) {
            var tenths = Math.round(distance / 100.0) as Number;
            var whole = Math.floor(tenths / 10.0) as Number;
            var fraction = (tenths % 10).toString();
            return whole.toString() + "." + fraction + " km";
        }

        return Math.round(distance / 1000.0).toString() + " km";
    }
}
