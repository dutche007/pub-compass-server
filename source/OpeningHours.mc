import Toybox.Lang;
import Toybox.Time;
import Toybox.Time.Gregorian;
import Toybox.Math;

class OpeningHours {
    private static const DAY_CODES = ["Mo", "Tu", "We", "Th", "Fr", "Sa", "Su"];

    public static function describe(value as String?) as String {
        if (value == null || value.length() == 0) {
            return "Hours unknown";
        }

        var text = trimText(value);
        if (text == "24/7") {
            return "Open 24/7";
        }
        if (text == "off") {
            return "Closed today";
        }

        var nowInfo = Gregorian.info(Time.now(), Time.FORMAT_SHORT);
        var day = (nowInfo.day_of_week as Number) - 1;
        var minuteOfDay = (nowInfo.hour as Number) * 60 + (nowInfo.min as Number);
        var rules = splitText(text, ";");
        var intervals = [];

        for (var ruleIndex = 0; ruleIndex < rules.size(); ruleIndex++) {
            var rawRule = rules[ruleIndex] as String;
            var rule = trimText(rawRule);
            if (rule.length() == 0) {
                continue;
            }

            var parts = splitRule(rule);
            if (parts.size() != 2) {
                return "Hours unknown";
            }

            var days = parseDays(parts[0]);
            if (days == null) {
                return "Hours unknown";
            }
            if (parts[1] == "off") {
                continue;
            }

            var timeRanges = splitText(parts[1], ",");
            for (var timeIndex = 0; timeIndex < timeRanges.size(); timeIndex++) {
                var timeRange = trimText(timeRanges[timeIndex] as String);
                var times = splitText(timeRange, "-");
                if (times.size() != 2) {
                    return "Hours unknown";
                }

                var openMinute = parseTime(trimText(times[0] as String));
                var closeMinute = parseTime(trimText(times[1] as String));
                if (openMinute == null || closeMinute == null || openMinute >= 1440 || closeMinute > 1440) {
                    return "Hours unknown";
                }

                for (var dayIndex = 0; dayIndex < days.size(); dayIndex++) {
                    var intervalDay = days[dayIndex];
                    intervals.add({
                        "day" => intervalDay,
                        "open" => openMinute,
                        "close" => closeMinute
                    });
                }
            }
        }

        if (intervals.size() == 0) {
            return "Closed today";
        }

        var nextOpening = 1441;
        for (var intervalIndex = 0; intervalIndex < intervals.size(); intervalIndex++) {
            var interval = intervals[intervalIndex] as Dictionary;
            var intervalDay = interval["day"] as Number;
            var openMinute = interval["open"] as Number;
            var closeMinute = interval["close"] as Number;

            if (intervalDay == day) {
                var overnight = closeMinute < openMinute || closeMinute == 0;
                if (minuteOfDay >= openMinute && (overnight || minuteOfDay < closeMinute)) {
                    return "Open til " + formatTime(closeMinute);
                }
                if (minuteOfDay < openMinute && openMinute < nextOpening) {
                    nextOpening = openMinute;
                }
            }

            var yesterday = (day + 6) % 7;
            if (intervalDay == yesterday) {
                var previousOvernight = closeMinute < openMinute || closeMinute == 0;
                if (previousOvernight && minuteOfDay < closeMinute) {
                    return "Open til " + formatTime(closeMinute);
                }
            }
        }

        if (nextOpening <= 1440) {
            return "Opens " + formatTime(nextOpening);
        }
        return "Closed today";
    }

    private static function parseDays(value as String) as Array<Number>? {
        var result = [];
        var dayParts = splitText(value, ",");

        for (var partIndex = 0; partIndex < dayParts.size(); partIndex++) {
            var part = trimText(dayParts[partIndex] as String);
            if (part.length() == 2) {
                var singleDay = dayIndex(part);
                if (singleDay == null) {
                    return null;
                }
                addUnique(result, singleDay as Number);
            } else if (part.length() == 5 && part.substring(2, 3) == "-") {
                var startValue = dayIndex(part.substring(0, 2) as String);
                var endValue = dayIndex(part.substring(3, 5) as String);
                if (startValue == null || endValue == null) {
                    return null;
                }
                var start = startValue as Number;
                var end = endValue as Number;
                var current = start;
                while (true) {
                    addUnique(result, current);
                    if (current == end) {
                        break;
                    }
                    current = (current + 1) % 7;
                }
            } else {
                return null;
            }
        }

        return result;
    }

    private static function dayIndex(value as String) as Number? {
        for (var index = 0; index < DAY_CODES.size(); index++) {
            if (DAY_CODES[index] == value) {
                return (index + 1) % 7;
            }
        }
        return null;
    }

    private static function addUnique(values as Array<Number>, value as Number) as Void {
        for (var index = 0; index < values.size(); index++) {
            if (values[index] == value) {
                return;
            }
        }
        values.add(value);
    }

    private static function parseTime(value as String) as Number? {
        var parts = splitText(value, ":");
        if (parts.size() != 2 || parts[0].length() != 2 || parts[1].length() != 2) {
            return null;
        }

        var hour = parts[0].toNumber();
        var minute = parts[1].toNumber();
        if (hour == null || minute == null || minute < 0 || minute > 59 || hour < 0 || hour > 24) {
            return null;
        }
        if (hour == 24 && minute != 0) {
            return null;
        }

        return hour * 60 + minute;
    }

    private static function formatTime(totalMinutes as Number) as String {
        var minute = totalMinutes % 60;
        var hour = Math.floor(totalMinutes / 60.0).toNumber();
        return twoDigits(hour) + ":" + twoDigits(minute);
    }

    private static function twoDigits(value as Number) as String {
        if (value < 10) {
            return "0" + value.toString();
        }
        return value.toString();
    }

    private static function splitRule(value as String) as Array<String> {
        var parts = [];
        var token = "";
        for (var index = 0; index < value.length(); index++) {
            var character = value.substring(index, index + 1);
            if (character == " " || character == "\t") {
                if (token.length() > 0) {
                    parts.add(token);
                    token = "";
                }
            } else {
                token += character;
            }
        }
        if (token.length() > 0) {
            parts.add(token);
        }
        return parts;
    }

    private static function trimText(value as String) as String {
        var start = 0;
        var end = value.length();
        while (start < end) {
            var first = value.substring(start, start + 1);
            if (first != " " && first != "\t") {
                break;
            }
            start++;
        }
        while (end > start) {
            var last = value.substring(end - 1, end);
            if (last != " " && last != "\t") {
                break;
            }
            end--;
        }
        return value.substring(start, end) as String;
    }

    private static function splitText(value as String, delimiter as String) as Array<String> {
        var result = [];
        var segmentStart = 0;
        for (var index = 0; index < value.length(); index++) {
            if (value.substring(index, index + 1) == delimiter) {
                result.add(value.substring(segmentStart, index) as String);
                segmentStart = index + 1;
            }
        }
        result.add(value.substring(segmentStart, value.length()) as String);
        return result;
    }
}
