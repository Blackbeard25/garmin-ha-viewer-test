import Toybox.Application;
import Toybox.Communications;
import Toybox.Lang;
import Toybox.StringUtil;
import Toybox.Time;
import Toybox.Timer;
import Toybox.WatchUi;

// Talks to Home Assistant through the phone (Garmin Connect app).
//
// Everything the watch needs is fetched in ONE request to /api/template.
// Home Assistant renders the Jinja template server-side and returns a compact,
// pipe-delimited text payload. This keeps the response a few KB instead of the
// hundreds of KB that /api/states would return (which would not fit in watch
// memory).
//
// Output line formats:
//   H|lat|lon                                   home zone
//   L|p or d|name|lat|lon|state|updated_ts      person / device tracker
//   C|entity|name|mode|cur|target|min|max|step|action|mode1,mode2
//   O|count                                     # devices with unavailable entities
//   U|name                                      one unavailable device
//   B|name|pct                                  battery below 20%
//   T|now_ts                                    server time
function haTemplate() as String {
    return
    "{%- set z = states.zone.home -%}\n" +
    "H|{{ z.attributes.latitude }}|{{ z.attributes.longitude }}\n" +
    "{% set ns = namespace(own=[], d=[]) -%}\n" +
    "{%- for p in states.person -%}{% set ns.own = ns.own + (p.attributes.device_trackers | default([])) %}{%- endfor -%}\n" +
    "{%- for s in ((states.person | list) + (states.device_tracker | rejectattr('entity_id','in',ns.own) | list))[:20] if s.attributes.latitude is number -%}\n" +
    "L|{{ s.domain[0] }}|{{ s.name | replace('|','/') }}|{{ s.attributes.latitude | round(5) }}|{{ s.attributes.longitude | round(5) }}|{{ s.state }}|{{ as_timestamp(s.last_updated) | int }}\n" +
    "{% endfor -%}\n" +
    "{%- for s in states.climate -%}\n" +
    "C|{{ s.entity_id }}|{{ s.name | replace('|','/') }}|{{ s.state }}|{{ s.attributes.current_temperature }}|{{ s.attributes.temperature }}|{{ s.attributes.min_temp }}|{{ s.attributes.max_temp }}|{{ s.attributes.target_temp_step | default(0.5) }}|{{ s.attributes.hvac_action | default('') }}|{{ s.attributes.hvac_modes | join(',') }}\n" +
    "{% endfor -%}\n" +
    "{%- for s in states | selectattr('state','eq','unavailable') -%}\n" +
    "{%- set n = device_attr(s.entity_id,'name_by_user') or device_attr(s.entity_id,'name') or s.name -%}\n" +
    "{%- if n not in ns.d %}{% set ns.d = ns.d + [n] %}{% endif -%}\n" +
    "{%- endfor -%}\n" +
    "O|{{ ns.d | count }}\n" +
    "{% for n in ns.d[:25] %}U|{{ n | replace('|','/') }}\n" +
    "{% endfor -%}\n" +
    "{%- for s in states.sensor | selectattr('attributes.device_class','defined') | selectattr('attributes.device_class','eq','battery') if s.state | is_number and s.state | float < 20 -%}\n" +
    "B|{{ (device_attr(s.entity_id,'name_by_user') or device_attr(s.entity_id,'name') or s.name) | replace('|','/') }}|{{ s.state | float | round(0) | int }}\n" +
    "{% endfor -%}\n" +
    "T|{{ now().timestamp() | int }}";
}

class HaClient {
    // ---- parsed data ----
    var homeLat as Float? = null;
    var homeLon as Float? = null;
    var locations as Array<Dictionary> = [];   // {:type,:name,:lat,:lon,:state,:ts}
    var climates as Array<Dictionary> = [];    // see parseClimate()
    var offlineCount as Number = 0;
    var offline as Array<String> = [];
    var lowBattery as Array<Array> = [];       // [name, pct]
    var serverTime as Number = 0;

    // ---- status ----
    var loading as Boolean = false;
    var lastError as String? = null;
    var lastUpdate as Number? = null;          // watch time (epoch s) of last good fetch

    hidden var _refreshTimer as Timer.Timer?;

    function initialize() {
    }

    // ------------------------------------------------------------------
    // Settings
    // ------------------------------------------------------------------
    function baseUrl() as String? {
        var url = Application.Properties.getValue("haUrl");
        if (url == null || !(url instanceof String) || url.length() == 0) {
            return null;
        }
        while (url.length() > 0 && url.substring(url.length() - 1, url.length()).equals("/")) {
            url = url.substring(0, url.length() - 1);
        }
        return url;
    }

    function token() as String? {
        var t = Application.Properties.getValue("haToken");
        if (t == null || !(t instanceof String) || t.length() == 0) {
            return null;
        }
        return t;
    }

    function preferredClimate() as String? {
        var c = Application.Properties.getValue("climateEntity");
        if (c == null || !(c instanceof String) || c.length() == 0) {
            return null;
        }
        return c;
    }

    function isConfigured() as Boolean {
        return baseUrl() != null && token() != null;
    }

    hidden function headers() as Dictionary {
        return {
            "Authorization" => "Bearer " + token(),
            "Content-Type" => Communications.REQUEST_CONTENT_TYPE_JSON
        };
    }

    // ------------------------------------------------------------------
    // Fetch all state
    // ------------------------------------------------------------------
    function refresh() as Void {
        if (loading) {
            return;
        }
        if (!isConfigured()) {
            lastError = "Set URL + token in Garmin Connect app";
            WatchUi.requestUpdate();
            return;
        }
        loading = true;
        WatchUi.requestUpdate();
        Communications.makeWebRequest(
            baseUrl() + "/api/template",
            { "template" => haTemplate() },
            {
                :method => Communications.HTTP_REQUEST_METHOD_POST,
                :headers => headers(),
                :responseType => Communications.HTTP_RESPONSE_CONTENT_TYPE_TEXT_PLAIN
            },
            method(:onTemplate)
        );
    }

    function onTemplate(code as Number, data) as Void {
        loading = false;
        if (code == 200 && data instanceof String) {
            parse(data);
            lastError = null;
            lastUpdate = Time.now().value();
        } else {
            lastError = describeError(code);
        }
        WatchUi.requestUpdate();
    }

    // ------------------------------------------------------------------
    // Service calls
    // ------------------------------------------------------------------
    function callService(domain as String, service as String, body as Dictionary) as Void {
        if (!isConfigured()) {
            return;
        }
        Communications.makeWebRequest(
            baseUrl() + "/api/services/" + domain + "/" + service,
            body,
            {
                :method => Communications.HTTP_REQUEST_METHOD_POST,
                :headers => headers(),
                :responseType => Communications.HTTP_RESPONSE_CONTENT_TYPE_JSON
            },
            method(:onService)
        );
    }

    function onService(code as Number, data) as Void {
        if (code == 200) {
            lastError = null;
            // Give HA / the thermostat a moment, then pull fresh state.
            refreshSoon(2000);
        } else {
            lastError = "Action failed: " + describeError(code);
            WatchUi.requestUpdate();
        }
    }

    function refreshSoon(ms as Number) as Void {
        if (_refreshTimer == null) {
            _refreshTimer = new Timer.Timer();
        }
        _refreshTimer.stop();
        _refreshTimer.start(method(:refresh), ms, false);
    }

    function setTemperature(entityId as String, temp as Float) as Void {
        callService("climate", "set_temperature", { "entity_id" => entityId, "temperature" => temp });
    }

    function setHvacMode(entityId as String, mode as String) as Void {
        callService("climate", "set_hvac_mode", { "entity_id" => entityId, "hvac_mode" => mode });
    }

    // ------------------------------------------------------------------
    // Helpers
    // ------------------------------------------------------------------
    function describeError(code as Number) as String {
        if (code == 401) { return "401: bad token"; }
        if (code == 403) { return "403: forbidden"; }
        if (code == 404) { return "404: check URL"; }
        if (code == -104) { return "Phone not connected"; }
        if (code == -300) { return "Request timed out"; }
        if (code == -400) { return "Bad response"; }
        if (code == -402 || code == -403) { return "Response too large"; }
        if (code == -1001) { return "HTTPS required"; }
        if (code == -2 || code == -101) { return "Phone busy, retry"; }
        return "Error " + code;
    }

    // Climate to show: the one from settings, otherwise the first one found.
    function climateIndex() as Number {
        var pref = preferredClimate();
        if (pref != null) {
            for (var i = 0; i < climates.size(); i++) {
                if (pref.equals(climates[i][:id])) {
                    return i;
                }
            }
        }
        return 0;
    }

    function problemCount() as Number {
        return offlineCount + lowBattery.size();
    }

    // ------------------------------------------------------------------
    // Parsing
    // ------------------------------------------------------------------
    hidden function parse(text as String) as Void {
        var newLocs = [];
        var newClimates = [];
        var newOffline = [];
        var newBatt = [];
        var lines = split(text, "\n");
        for (var i = 0; i < lines.size(); i++) {
            var line = lines[i];
            if (line.length() < 2) {
                continue;
            }
            var f = split(line, "|");
            var t = f[0];
            if (t.equals("H") && f.size() >= 3) {
                homeLat = toF(f[1]);
                homeLon = toF(f[2]);
            } else if (t.equals("L") && f.size() >= 7) {
                var lat = toF(f[3]);
                var lon = toF(f[4]);
                if (lat != null && lon != null) {
                    newLocs.add({
                        :type => f[1], :name => f[2], :lat => lat, :lon => lon,
                        :state => f[5], :ts => f[6].toNumber()
                    });
                }
            } else if (t.equals("C") && f.size() >= 11) {
                newClimates.add({
                    :id => f[1], :name => f[2], :mode => f[3],
                    :cur => toF(f[4]), :target => toF(f[5]),
                    :min => toF(f[6]), :max => toF(f[7]), :step => toF(f[8]),
                    :action => f[9],
                    :modes => (f[10].length() > 0) ? split(f[10], ",") : []
                });
            } else if (t.equals("O") && f.size() >= 2) {
                var n = f[1].toNumber();
                offlineCount = (n == null) ? 0 : n;
            } else if (t.equals("U") && f.size() >= 2) {
                newOffline.add(f[1]);
            } else if (t.equals("B") && f.size() >= 3) {
                newBatt.add([f[1], f[2]]);
            } else if (t.equals("T") && f.size() >= 2) {
                var ts = f[1].toNumber();
                serverTime = (ts == null) ? 0 : ts;
            }
        }
        locations = newLocs;
        climates = newClimates;
        offline = newOffline;
        lowBattery = newBatt;
    }

    hidden function toF(s as String) as Float? {
        if (s.length() == 0 || s.equals("None")) {
            return null;
        }
        return s.toFloat();
    }
}

// Split a string on a separator (Monkey C has no built-in split).
function split(s as String, sep as String) as Array<String> {
    var out = [] as Array<String>;
    var idx = s.find(sep);
    while (idx != null) {
        out.add(s.substring(0, idx) as String);
        s = s.substring(idx + sep.length(), s.length()) as String;
        idx = s.find(sep);
    }
    out.add(s);
    return out;
}

// "3m", "2h", "5d"
function formatAge(seconds as Number) as String {
    if (seconds < 60) { return "now"; }
    if (seconds < 3600) { return (seconds / 60).toString() + "m"; }
    if (seconds < 86400) { return (seconds / 3600).toString() + "h"; }
    return (seconds / 86400).toString() + "d";
}

function formatTemp(t as Float?) as String {
    if (t == null) { return "--"; }
    return t.format("%.1f") + "°";
}

function upcaseFirst(s as String) as String {
    if (s.length() == 0) { return s; }
    var r = s.substring(0, 1).toUpper() + s.substring(1, s.length());
    // replace underscores (heat_cool -> Heat cool)
    var chars = r.toCharArray();
    for (var i = 0; i < chars.size(); i++) {
        if (chars[i] == '_') { chars[i] = ' '; }
    }
    return StringUtil.charArrayToString(chars);
}
