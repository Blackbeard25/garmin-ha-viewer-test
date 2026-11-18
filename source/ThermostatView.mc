import Toybox.Graphics;
import Toybox.Lang;
import Toybox.Timer;
import Toybox.WatchUi;

// Thermostat control.
//   UP / DOWN : raise / lower the target (sent 1.5 s after the last press)
//   START     : choose HVAC mode (off / heat / cool / ...)
//   MENU      : (hold UP) switch thermostat, if you have more than one
//   BACK      : exit
class ThermostatView extends WatchUi.View {
    var index as Number;
    var pendingTarget as Float? = null;   // local edit not yet sent
    var sending as Boolean = false;
    hidden var _timer as Timer.Timer;

    function initialize() {
        View.initialize();
        index = getClient().climateIndex();
        _timer = new Timer.Timer();
    }

    function onHide() as Void {
        // Leaving the screen? Send any edit right away rather than dropping it.
        if (pendingTarget != null) {
            _timer.stop();
            sendTarget();
        }
    }

    function current() as Dictionary? {
        var cl = getClient().climates;
        if (cl.size() == 0) { return null; }
        if (index >= cl.size()) { index = 0; }
        return cl[index];
    }

    function onUpdate(dc as Dc) as Void {
        var w = dc.getWidth();
        var h = dc.getHeight();
        var cx = w / 2;
        var J = Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER;

        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_BLACK);
        dc.clear();

        var t = current();
        if (t == null) {
            var c = getClient();
            dc.drawText(cx, h / 2, Graphics.FONT_SMALL,
                c.loading ? "Loading..." : "No thermostat\nfound in HA", J);
            return;
        }

        // ---- sub-window: HVAC mode ----
        var sub = (WatchUi has :getSubscreen) ? WatchUi.getSubscreen() : null;
        var mode = (t[:mode] as String).toUpper();
        var leftCx = cx;
        if (sub != null) {
            var sx = sub.x + sub.width / 2;
            var sy = sub.y + sub.height / 2;
            dc.fillCircle(sx, sy, sub.width / 2);
            dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_TRANSPARENT);
            dc.drawText(sx, sy - 8, Graphics.FONT_XTINY, "MODE", J);
            dc.drawText(sx, sy + 9, Graphics.FONT_SMALL, mode.length() > 5 ? mode.substring(0, 5) : mode, J);
            dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
            leftCx = sub.x / 2 + 8;
        }

        var target = (pendingTarget != null) ? pendingTarget : t[:target];
        if (target != null) {
            dc.drawText(leftCx, 34, Graphics.FONT_XTINY, pendingTarget != null ? "SET TO" : "TARGET", J);
            dc.drawText(cx, 80, Graphics.FONT_LARGE, formatTemp(target), J);
            // up/down arrows hint on the left edge (where the UP/DOWN buttons are)
            dc.fillPolygon([[16, 70], [11, 78], [21, 78]]);
            dc.fillPolygon([[16, 104], [11, 96], [21, 96]]);
        } else {
            dc.drawText(cx, 80, Graphics.FONT_MEDIUM, "OFF", J);
        }

        var action = t[:action] as String;
        var nowLine = "Now " + formatTemp(t[:cur]);
        if (action.length() > 0) { nowLine += "  " + upcaseFirst(action); }
        dc.drawText(cx, 108, Graphics.FONT_XTINY, nowLine, J);

        var name = t[:name] as String;
        if (name.length() > 18) { name = name.substring(0, 18); }
        dc.drawText(cx, 128, Graphics.FONT_XTINY, name, J);
        if (sub == null) {
            dc.drawText(cx, 30, Graphics.FONT_XTINY, mode, J);
        }

        var c2 = getClient();
        var foot = "START: mode";
        if (sending) { foot = "Sending..."; }
        else if (c2.lastError != null) { foot = c2.lastError; }
        else if (c2.climates.size() > 1) { foot = (index + 1).toString() + "/" + c2.climates.size() + " MENU: next"; }
        dc.drawText(cx, 150, Graphics.FONT_XTINY, foot, J);
    }

    function adjust(dir as Number) as Void {
        var t = current();
        if (t == null || t[:target] == null) { return; }
        var step = t[:step] != null ? t[:step] as Float : 0.5;
        if (step <= 0) { step = 0.5; }
        var base = pendingTarget != null ? pendingTarget : t[:target] as Float;
        var v = base + dir * step;
        if (t[:min] != null && v < t[:min]) { v = t[:min] as Float; }
        if (t[:max] != null && v > t[:max]) { v = t[:max] as Float; }
        pendingTarget = v;
        _timer.stop();
        _timer.start(method(:sendTarget), 1500, false);
        WatchUi.requestUpdate();
    }

    function sendTarget() as Void {
        var t = current();
        if (t == null || pendingTarget == null) { return; }
        var v = pendingTarget as Float;
        t[:target] = v;   // optimistic update
        pendingTarget = null;
        sending = true;
        getClient().setTemperature(t[:id] as String, v);
        // clear the "sending" note after the follow-up refresh has had time to land
        _timer.start(method(:clearSending), 4000, false);
        WatchUi.requestUpdate();
    }

    function clearSending() as Void {
        sending = false;
        WatchUi.requestUpdate();
    }

    function nextThermostat() as Void {
        var n = getClient().climates.size();
        if (n > 1) {
            if (pendingTarget != null) { _timer.stop(); sendTarget(); }
            index = (index + 1) % n;
            WatchUi.requestUpdate();
        }
    }
}

class ThermostatDelegate extends WatchUi.BehaviorDelegate {
    hidden var _view as ThermostatView;

    function initialize(view as ThermostatView) {
        BehaviorDelegate.initialize();
        _view = view;
    }

    function onPreviousPage() as Boolean {   // UP
        _view.adjust(1);
        return true;
    }

    function onNextPage() as Boolean {       // DOWN
        _view.adjust(-1);
        return true;
    }

    function onMenu() as Boolean {           // hold UP
        _view.nextThermostat();
        return true;
    }

    function onSelect() as Boolean {         // START -> mode menu
        var t = _view.current();
        if (t == null) { return true; }
        var modes = t[:modes] as Array<String>;
        if (modes.size() == 0) { return true; }
        var menu = new WatchUi.Menu2({ :title => "Mode" });
        var focus = 0;
        for (var i = 0; i < modes.size(); i++) {
            menu.addItem(new WatchUi.MenuItem(upcaseFirst(modes[i]), null, modes[i], null));
            if (modes[i].equals(t[:mode])) { focus = i; }
        }
        menu.setFocus(focus);
        WatchUi.pushView(menu, new ModeMenuDelegate(t), WatchUi.SLIDE_UP);
        return true;
    }
}

class ModeMenuDelegate extends WatchUi.Menu2InputDelegate {
    hidden var _t as Dictionary;

    function initialize(t as Dictionary) {
        Menu2InputDelegate.initialize();
        _t = t;
    }

    function onSelect(item as WatchUi.MenuItem) as Void {
        var mode = item.getId() as String;
        _t[:mode] = mode;   // optimistic
        getClient().setHvacMode(_t[:id] as String, mode);
        WatchUi.popView(WatchUi.SLIDE_DOWN);
    }
}
