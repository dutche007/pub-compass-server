import Toybox.Lang;
import Toybox.Math;

class Compass {
    private var _x as Float = 0.0;
    private var _y as Float = 0.0;
    private var _heading as Float? = null;
    private var _erraticSamples as Number = 0;

    public function update(radians as Float) as Float {
        var degrees = GeoMath.normalizeDegrees(radians * 180.0 / GeoMath.PI);
        var angle = degrees * GeoMath.PI / 180.0;
        var sampleX = Math.cos(angle) as Float;
        var sampleY = Math.sin(angle) as Float;

        if (_heading != null) {
            var delta = GeoMath.normalizeDegrees(degrees - _heading);
            if (delta > 180.0) {
                delta = 360.0 - delta;
            }

            if (delta > 110.0) {
                _erraticSamples++;
            } else if (_erraticSamples > 0) {
                _erraticSamples--;
            }

            _x = (_x * 0.75 + sampleX * 0.25) as Float;
            _y = (_y * 0.75 + sampleY * 0.25) as Float;
        } else {
            _x = sampleX;
            _y = sampleY;
        }

        _heading = GeoMath.normalizeDegrees((Math.atan2(_y, _x) * 180.0 / GeoMath.PI) as Float);
        return _heading;
    }

    public function getHeading() as Float? {
        return _heading;
    }

    public function needsCalibration() as Boolean {
        return _erraticSamples >= 3;
    }
}
