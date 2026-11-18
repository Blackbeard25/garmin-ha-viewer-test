import Toybox.Graphics;
import Toybox.Lang;
import Toybox.Math;
import Toybox.Position;
import Toybox.Time;
import Toybox.WatchUi;

// Radar-style map. The Instinct 3 Solar has no map support in Connect IQ,
// so tracked people/devices are plotted by true bearing + distance from the
// centre (your watch's GPS position, or Home). North is up.
//
//   UP / DOWN : zoom in / out (first level = auto-fit)
//   START     : select next person / device (details at the bottom)
//   MENU      : (hold UP) toggle centre between Me (GPS) and Home
//   BACK      : exit
class MapView extends WatchUi.View {
    // radius of the outer ring in metres; 0 = auto fit
    const ZOOMS = [0, 200, 1000, 5000, 20000, 100000, 500000] as Array<Number>;

    var zoom as Number = 0;
    var selected as Number = 0;
    var centerOnMe as Boolean = true;
    hidden var _autoScale as Double = 1000.0d;
    hidden var _myLat as Double? = null;
    hidden var _myLon as Double? = null;

    function initialize() {
        View.initialize();
    }

    function onShow() as Void {
        // Use the last known fix right away, then ask for a fresh one.
        var info = Position.getInfo();
        if (info != null && info.position != null && info.accuracy != Position.QUALITY_NOT_AVAILABLE) {
            setPos(info.position);
        }
        Position.enableLocationEvents(Position.LOCATION_ONE_SHOT, method(:onPosition));
    }

    function onHide() as Void {
        Position.enableLocationEvents(Position.LOCATION_DISABLE, method(:onPosition));
    }

    function onPosition(info as Position.Info) as Void {
        if (info.position != null) {
            setPos(info.position);
            WatchUi.requestUpdate();
        }
    }

    hidden function setPos(p as Position.Location) as Void {
        var d = p.toDegrees();
        // (0,0) means "no fix" on some devices
        if (d[0] != 0 || d[1] != 0) {
            _myLat = d[0].toDouble();
            _myLon = d[1].toDouble();
        }
    }

    // Returns [lat, lon, label] of the current centre, or null.
    function center() as Array? {
        var c = getClient();
        if (centerOnMe && _myLat != null) {
            return [_myLat, _myLon, "ME"];
        }
        if (c.homeLat != null && c.homeLon != null) {
            return [c.homeLat.toDouble(), c.homeLon.toDouble(), "HOME"];
        }
        if (_myLat != null) {
            return [_myLat, _myLon, "ME"];
        }
        return null;
    }

    // Offset of (lat, lon) from centre in metres: [east, north]
    hidden function offset(c as Array, lat as Double, lon as Double) as Array<Double> {
        var lat0 = c[0] as Double;
        var lon0 = c[1] as Double;
        var east = (lon - lon0) * 111320.0d * Math.cos(Math.toRadians(lat0));
        var north = (lat - lat0) * 110574.0d;
        return [east, north];
    }

    hidden function dist(o as Array<Double>) as Double {
        return Math.sqrt(o[0] * o[0] + o[1] * o[1]);
    }

    function onUpdate(dc as Dc) as Void {
        var client = getClient();
        var w = dc.getWidth();
        var h = dc.getHeight();
        var cx = w / 2;
        var cy = 66;
        var r = 58;

        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_BLACK);
        dc.clear();

        var c = center();
        if (c == null) {
            dc.drawText(cx, cy, Graphics.FONT_SMALL, client.loading ? "Loading..." : "No location",
                Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
            return;
        }

        var locs = client.locations;
        var n = locs.size();
        if (selected >= n) { selected = 0; }

        // Pre-compute offsets
        var offs = new [n];
        var maxD = 0.0d;
        for (var i = 0; i < n; i++) {
            offs[i] = offset(c, (locs[i][:lat] as Float).toDouble(), (locs[i][:lon] as Float).toDouble());
            var d = dist(offs[i]);
            if (d > maxD) { maxD = d; }
        }
        var homeOff = null;
        if (client.homeLat != null && !(c[2] as String).equals("HOME")) {
            homeOff = offset(c, client.homeLat.toDouble(), client.homeLon.toDouble());
            var dh = dist(homeOff);
            if (dh > maxD) { maxD = dh; }
        }

        var scale = ZOOMS[zoom].toDouble();
        if (zoom == 0) {
            scale = niceScale(maxD * 1.1d);
            _autoScale = scale;
        }

        // ---- rings + north tick ----
        dc.setPenWidth(1);
        dc.drawCircle(cx, cy, r);
        dc.drawCircle(cx, cy, r / 2);
        dc.drawLine(cx, cy - r - 4, cx, cy - r + 4);
        dc.drawText(cx + r / 2 + 2, cy, Graphics.FONT_XTINY, formatDist(scale / 2),
            Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER);

        // ---- centre marker ----
        if ((c[2] as String).equals("HOME")) {
            drawHouse(dc, cx, cy);
        } else {
            dc.fillPolygon([[cx, cy - 5], [cx - 4, cy + 4], [cx + 4, cy + 4]]);
        }

        // ---- home (when centred on me) ----
        if (homeOff != null) {
            var hp = toScreen(homeOff, scale, cx, cy, r);
            drawHouse(dc, hp[0], hp[1]);
        }

        // ---- people / devices ----
        for (var i = 0; i < n; i++) {
            var p = toScreen(offs[i], scale, cx, cy, r);
            var x = p[0];
            var y = p[1];
            var clipped = p[2];
            if (clipped) {
                dc.drawCircle(x, y, 4);         // off the scale: hollow dot on the rim
            } else if ((locs[i][:type] as String).equals("p")) {
                dc.fillCircle(x, y, 4);         // person
            } else {
                dc.fillRectangle(x - 3, y - 3, 7, 7);   // device tracker
            }
            if (i == selected) {
                dc.drawCircle(x, y, 8);
            }
            var initial = (locs[i][:name] as String).substring(0, 1);
            dc.drawText(x + 7, y - 9, Graphics.FONT_XTINY, initial, Graphics.TEXT_JUSTIFY_LEFT);
        }

        // ---- info for selected ----
        if (n > 0) {
            var sel = locs[selected];
            var name = sel[:name] as String;
            if (name.length() > 16) { name = name.substring(0, 16); }
            var state = upcaseFirst(sel[:state] as String);
            if (state.length() > 14) { state = state.substring(0, 14); }
            // Three short lines: the screen narrows quickly towards the bottom.
            var JC = Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER;
            dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
            dc.fillRectangle(0, 126, w, h - 126);
            dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_TRANSPARENT);
            dc.drawText(cx, 135, Graphics.FONT_XTINY, name, JC);
            dc.drawText(cx, 149, Graphics.FONT_XTINY, state, JC);
            dc.drawText(cx, 163, Graphics.FONT_XTINY,
                formatDist(dist(offs[selected])) + " " + bearingName(offs[selected]), JC);
        } else {
            dc.drawText(cx, h - 30, Graphics.FONT_XTINY, "Nothing tracked", Graphics.TEXT_JUSTIFY_CENTER);
        }

        // ---- sub-window: centre + zoom ----
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        var sub = (WatchUi has :getSubscreen) ? WatchUi.getSubscreen() : null;
        var JV = Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER;
        if (sub != null) {
            var sx = sub.x + sub.width / 2;
            var sy = sub.y + sub.height / 2;
            dc.fillCircle(sx, sy, sub.width / 2);
            dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_TRANSPARENT);
            dc.drawText(sx, sy - 9, Graphics.FONT_XTINY, c[2] as String, JV);
            dc.drawText(sx, sy + 9, Graphics.FONT_XTINY, zoomLabel(), JV);
        } else {
            dc.drawText(28, 18, Graphics.FONT_XTINY, (c[2] as String) + " " + zoomLabel(),
                Graphics.TEXT_JUSTIFY_LEFT);
        }
    }

    // Returns [x, y, clipped]
    hidden function toScreen(o as Array<Double>, scale as Double, cx as Number, cy as Number, r as Number) as Array {
        var px = o[0] / scale * r;
        var py = o[1] / scale * r;
        var d = Math.sqrt(px * px + py * py);
        var clipped = false;
        if (d > r) {
            px = px * r / d;
            py = py * r / d;
            clipped = true;
        }
        return [cx + px.toNumber(), cy - py.toNumber(), clipped];
    }

    hidden function drawHouse(dc as Dc, x as Number, y as Number) as Void {
        dc.fillPolygon([[x, y - 7], [x - 6, y - 1], [x + 6, y - 1]]);
        dc.fillRectangle(x - 4, y - 1, 9, 6);
    }

    // Round up to 1/2/5 x 10^n metres
    hidden function niceScale(m as Double) as Double {
        if (m < 100) { return 100.0d; }
        var p = Math.pow(10, Math.floor(Math.log(m, 10))).toDouble();
        var steps = [1, 2, 5, 10];
        for (var i = 0; i < steps.size(); i++) {
            if (m <= steps[i] * p) { return steps[i] * p; }
        }
        return 10 * p;
    }

    hidden function bearingName(o as Array<Double>) as String {
        if (dist(o) < 30) { return ""; }
        var deg = Math.toDegrees(Math.atan2(o[0], o[1]));
        if (deg < 0) { deg += 360; }
        var names = ["N", "NE", "E", "SE", "S", "SW", "W", "NW"];
        return names[((deg + 22.5) / 45).toNumber() % 8];
    }

    // UP: smaller radius. From auto, jump to the next fixed level below the auto scale.
    function zoomIn() as Void {
        if (zoom == 0) {
            zoom = 1;
            for (var i = ZOOMS.size() - 1; i >= 1; i--) {
                if (ZOOMS[i] < _autoScale) { zoom = i; break; }
            }
        } else if (zoom > 1) {
            zoom--;
        }
        WatchUi.requestUpdate();
    }

    // DOWN: larger radius. Past the largest level, wrap back to auto-fit.
    function zoomOut() as Void {
        if (zoom == 0) {
            zoom = ZOOMS.size() - 1;
            for (var i = 1; i < ZOOMS.size(); i++) {
                if (ZOOMS[i] > _autoScale) { zoom = i; break; }
            }
        } else if (zoom < ZOOMS.size() - 1) {
            zoom++;
        } else {
            zoom = 0;
        }
        WatchUi.requestUpdate();
    }

    function zoomLabel() as String {
        return zoom == 0 ? "AUTO" : formatDist(ZOOMS[zoom].toDouble());
    }
}

function formatDist(m as Double) as String {
    if (m < 1000) { return m.toNumber().toString() + "m"; }
    if (m < 10000) { return (m / 1000).format("%.1f") + "km"; }
    return (m / 1000).toNumber().toString() + "km";
}

class MapDelegate extends WatchUi.BehaviorDelegate {
    hidden var _view as MapView;

    function initialize(view as MapView) {
        BehaviorDelegate.initialize();
        _view = view;
    }

    function onPreviousPage() as Boolean {   // UP
        _view.zoomIn();
        return true;
    }

    function onNextPage() as Boolean {       // DOWN
        _view.zoomOut();
        return true;
    }

    function onSelect() as Boolean {         // START
        var n = getClient().locations.size();
        if (n > 0) {
            _view.selected = (_view.selected + 1) % n;
            WatchUi.requestUpdate();
        }
        return true;
    }

    function onMenu() as Boolean {           // hold UP
        _view.centerOnMe = !_view.centerOnMe;
        WatchUi.requestUpdate();
        return true;
    }
}
