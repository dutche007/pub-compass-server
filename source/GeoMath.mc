import Toybox.Lang;
import Toybox.Math;

class GeoMath {
    static const EARTH_RADIUS_METRES = 6371000.0;
    static const PI = 3.141592653589793;

    public static function distanceMeters(lat1 as Float, lon1 as Float, lat2 as Float, lon2 as Float) as Float {
        var latitude1 = lat1 * PI / 180.0;
        var latitude2 = lat2 * PI / 180.0;
        var deltaLatitude = (lat2 - lat1) * PI / 180.0;
        var deltaLongitude = (lon2 - lon1) * PI / 180.0;
        var sinLatitude = Math.sin(deltaLatitude / 2.0);
        var sinLongitude = Math.sin(deltaLongitude / 2.0);
        var a = sinLatitude * sinLatitude +
            Math.cos(latitude1) * Math.cos(latitude2) * sinLongitude * sinLongitude;

        if (a > 1.0) {
            a = 1.0;
        }

        return (EARTH_RADIUS_METRES * 2.0 * Math.atan2(Math.sqrt(a), Math.sqrt(1.0 - a))) as Float;
    }

    public static function initialBearing(lat1 as Float, lon1 as Float, lat2 as Float, lon2 as Float) as Float {
        var latitude1 = lat1 * PI / 180.0;
        var latitude2 = lat2 * PI / 180.0;
        var deltaLongitude = (lon2 - lon1) * PI / 180.0;
        var y = Math.sin(deltaLongitude) * Math.cos(latitude2);
        var x = Math.cos(latitude1) * Math.sin(latitude2) -
            Math.sin(latitude1) * Math.cos(latitude2) * Math.cos(deltaLongitude);
        var bearing = Math.atan2(y, x) * 180.0 / PI;

        if (bearing < 0.0) {
            bearing += 360.0;
        }

        return bearing as Float;
    }

    public static function normalizeDegrees(angle as Float) as Float {
        while (angle < 0.0) {
            angle += 360.0;
        }
        while (angle >= 360.0) {
            angle -= 360.0;
        }
        return angle;
    }
}
