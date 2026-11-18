import Toybox.Lang;
import Toybox.WatchUi;

// Scrollable list of things wrong in Home Assistant:
//  - devices that have one or more "unavailable" entities (offline)
//  - battery sensors under 20%
function pushProblemsMenu() as Void {
    var c = getClient();
    var menu = new WatchUi.Menu2({ :title => "Problems (" + c.problemCount() + ")" });

    for (var i = 0; i < c.lowBattery.size(); i++) {
        var b = c.lowBattery[i];
        menu.addItem(new WatchUi.MenuItem(b[0] as String, "Battery " + b[1] + "%", "b" + i, null));
    }
    for (var i = 0; i < c.offline.size(); i++) {
        menu.addItem(new WatchUi.MenuItem(c.offline[i], "Unavailable", "u" + i, null));
    }
    var extra = c.offlineCount - c.offline.size();
    if (extra > 0) {
        menu.addItem(new WatchUi.MenuItem("+" + extra + " more", "offline devices", "more", null));
    }
    if (c.lastError != null) {
        menu.addItem(new WatchUi.MenuItem("Connection", c.lastError, "err", null));
    }
    if (c.problemCount() == 0 && c.lastError == null) {
        menu.addItem(new WatchUi.MenuItem("All good", "Nothing offline", "ok", null));
    }

    WatchUi.pushView(menu, new ProblemsMenuDelegate(), WatchUi.SLIDE_LEFT);
}

class ProblemsMenuDelegate extends WatchUi.Menu2InputDelegate {
    function initialize() {
        Menu2InputDelegate.initialize();
    }

    function onSelect(item as WatchUi.MenuItem) as Void {
        // Read-only list; nothing to do.
    }
}
