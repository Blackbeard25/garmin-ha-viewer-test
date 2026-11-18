import Toybox.Application;
import Toybox.Lang;
import Toybox.Timer;
import Toybox.WatchUi;

class HomeAssistantApp extends Application.AppBase {
    var client as HaClient;
    hidden var _timer as Timer.Timer?;

    function initialize() {
        AppBase.initialize();
        client = new HaClient();
    }

    function onStart(state as Dictionary?) as Void {
        client.refresh();
        startAutoRefresh();
    }

    function onStop(state as Dictionary?) as Void {
        if (_timer != null) {
            _timer.stop();
        }
    }

    function getInitialView() as [WatchUi.Views] or [WatchUi.Views, WatchUi.InputDelegates] {
        return [new DashboardView(), new DashboardDelegate()];
    }

    // Called when settings are changed in the Garmin Connect app.
    function onSettingsChanged() as Void {
        startAutoRefresh();
        client.refresh();
    }

    hidden function startAutoRefresh() as Void {
        if (_timer == null) {
            _timer = new Timer.Timer();
        }
        _timer.stop();
        var sec = Application.Properties.getValue("refreshSec");
        if (sec instanceof Number && sec > 0) {
            if (sec < 15) { sec = 15; }
            _timer.start(method(:onAutoRefresh), sec * 1000, true);
        }
    }

    function onAutoRefresh() as Void {
        client.refresh();
    }
}

function getApp() as HomeAssistantApp {
    return Application.getApp() as HomeAssistantApp;
}

function getClient() as HaClient {
    return getApp().client;
}
