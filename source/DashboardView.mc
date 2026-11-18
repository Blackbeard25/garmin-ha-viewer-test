import Toybox.Graphics;
import Toybox.Lang;
import Toybox.Time;
import Toybox.WatchUi;

// Home screen: thermostat summary, who's home, problem count.
// The Instinct's round sub-window (top right) shows the problem count.
class DashboardView extends WatchUi.View {

    function initialize() {
        View.initialize();
    }

    function onUpdate(dc as Dc) as Void {
        var c = getClient();
        var w = dc.getWidth();
        var h = dc.getHeight();
        var cx = w / 2;

        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_BLACK);
        dc.clear();

        // ---- sub-window: problem count ----
        var sub = null;
        if (WatchUi has :getSubscreen) {
            sub = WatchUi.getSubscreen();
        }
        var leftCx = cx;
        if (sub != null) {
            var sx = sub.x + sub.width / 2;
            var sy = sub.y + sub.height / 2;
            var n = c.problemCount();
            dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
            if (n > 0) {
                dc.fillCircle(sx, sy, sub.width / 2);
                dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_TRANSPARENT);
                dc.drawText(sx, sy - 4, Graphics.FONT_MEDIUM, n.toString(),
                    Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
                dc.drawText(sx, sy + 16, Graphics.FONT_XTINY, "ISSUES",
                    Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
            } else {
                dc.drawText(sx, sy, Graphics.FONT_SMALL, "OK",
                    Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
            }
            dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
            leftCx = sub.x / 2 + 8;
        }

        // ---- title ----
        dc.drawText(leftCx, 34, Graphics.FONT_SMALL, "HOME",
            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);

        if (!c.isConfigured()) {
            drawCentered(dc, cx, h / 2 + 10, Graphics.FONT_XTINY,
                "Open Garmin Connect\n> this app > Settings\nand enter your HA\nURL and token");
            return;
        }

        if (c.lastUpdate == null) {
            var msg = c.loading ? "Loading..." : (c.lastError != null ? c.lastError : "No data");
            drawCentered(dc, cx, h / 2 + 10, Graphics.FONT_SMALL, msg);
            return;
        }

        // ---- thermostat ----
        if (c.climates.size() > 0) {
            var t = c.climates[c.climateIndex()];
            dc.drawText(cx, 76, Graphics.FONT_LARGE, formatTemp(t[:cur]),
                Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
            var sub2 = upcaseFirst(t[:mode] as String);
            if (t[:target] != null) {
                sub2 = "Set " + formatTemp(t[:target]) + "  " + sub2;
            }
            dc.drawText(cx, 104, Graphics.FONT_XTINY, sub2,
                Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
        }

        // ---- people ----
        var home = 0;
        var away = 0;
        for (var i = 0; i < c.locations.size(); i++) {
            var l = c.locations[i];
            if ((l[:type] as String).equals("p")) {
                if ((l[:state] as String).equals("home")) { home++; } else { away++; }
            }
        }
        dc.drawText(cx, 126, Graphics.FONT_XTINY, home.toString() + " home  " + away + " away",
            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);

        // ---- footer: status ----
        var foot;
        if (c.loading) {
            foot = "Updating...";
        } else if (c.lastError != null) {
            foot = c.lastError;
        } else {
            foot = "Updated " + formatAge(Time.now().value() - c.lastUpdate);
        }
        dc.drawText(cx, 148, Graphics.FONT_XTINY, foot,
            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
    }

    hidden function drawCentered(dc as Dc, x as Number, y as Number, font, text as String) as Void {
        dc.drawText(x, y, font, text, Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
    }
}

class DashboardDelegate extends WatchUi.BehaviorDelegate {
    function initialize() {
        BehaviorDelegate.initialize();
    }

    function onSelect() as Boolean {
        var menu = new WatchUi.Menu2({ :title => "Home Assistant" });
        var c = getClient();
        menu.addItem(new WatchUi.MenuItem("Map", c.locations.size().toString() + " tracked", :map, null));
        var tLabel = "none found";
        if (c.climates.size() > 0) {
            var t = c.climates[c.climateIndex()];
            tLabel = formatTemp(t[:cur]) + " > " + formatTemp(t[:target]);
        }
        menu.addItem(new WatchUi.MenuItem("Thermostat", tLabel, :thermo, null));
        menu.addItem(new WatchUi.MenuItem("Problems",
            c.offlineCount.toString() + " offline, " + c.lowBattery.size() + " low batt", :errors, null));
        menu.addItem(new WatchUi.MenuItem("Refresh", null, :refresh, null));
        WatchUi.pushView(menu, new MainMenuDelegate(), WatchUi.SLIDE_UP);
        return true;
    }

    // UP / DOWN on the dashboard also refresh.
    function onNextPage() as Boolean {
        getClient().refresh();
        return true;
    }

    function onPreviousPage() as Boolean {
        getClient().refresh();
        return true;
    }
}

class MainMenuDelegate extends WatchUi.Menu2InputDelegate {
    function initialize() {
        Menu2InputDelegate.initialize();
    }

    function onSelect(item as WatchUi.MenuItem) as Void {
        var id = item.getId();
        if (id == :map) {
            var v = new MapView();
            WatchUi.pushView(v, new MapDelegate(v), WatchUi.SLIDE_LEFT);
        } else if (id == :thermo) {
            var tv = new ThermostatView();
            WatchUi.pushView(tv, new ThermostatDelegate(tv), WatchUi.SLIDE_LEFT);
        } else if (id == :errors) {
            pushProblemsMenu();
        } else if (id == :refresh) {
            getClient().refresh();
            WatchUi.popView(WatchUi.SLIDE_DOWN);
        }
    }
}
