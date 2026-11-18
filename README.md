# Home Assistant for Garmin Instinct 3 Solar

Run `python3 tools/preview.py` (needs Pillow) to draw a mock-up of every screen to `preview.png`. The script copies the watch app's drawing code; the menu screens approximate Garmin's built-in menus.

A Connect IQ watch app for the Instinct 3 Solar that shows your Home Assistant data:

- **Dashboard**: current indoor temperature, setpoint and mode, how many people are home or away, and a count of problems in the round sub-window (top right).
- **Map**: a radar-style map of every `person` and every `device_tracker` that isn't linked to a person. North is up. The centre is your watch's GPS position, or Home. People show as dots, other devices as squares, and Home as a house. Anything off the scale sits on the outer ring as a hollow dot.
- **Thermostat**: raise or lower the setpoint and change the HVAC mode (off, heat, cool, …).
- **Problems**: devices with unavailable entities, and battery sensors under 20%.

> Why not a real map? Connect IQ's `MapView` and map tiles aren't available on the Instinct series, which has a monochrome screen and no maps. The radar view shows the true bearing and distance to each tracker, and that stays readable on a 176×176 black-and-white screen.

## Buttons

| Screen     | UP              | DOWN            | START (GPS)        | MENU (hold UP)      | BACK |
|------------|-----------------|-----------------|--------------------|---------------------|------|
| Dashboard  | refresh         | refresh         | open menu          | –                   | exit |
| Map        | zoom in         | zoom out / auto | next person/device | centre: Me ↔ Home   | back |
| Thermostat | setpoint +step  | setpoint −step  | choose mode        | next thermostat     | back |

A setpoint change is sent 1.5 s after your last button press, so several presses become one call.

## How it talks to Home Assistant

The watch makes **one** request through your phone: `POST /api/template`. Home Assistant renders a Jinja template (in `source/HaClient.mc`) and sends back a compact text payload of about 1 KB. The app doesn't use `/api/states` because that response is far too large for watch memory. Thermostat changes call `climate.set_temperature` and `climate.set_hvac_mode`.

Requirements:
- An **HTTPS** URL for HA with a valid certificate that your phone can reach, e.g. your Nabu Casa `https://xxxx.ui.nabu.casa` URL or another public HTTPS URL. Garmin rejects plain HTTP and self-signed certificates.
- A **long-lived access token**: in HA, open Profile → Security → Long-lived access tokens → Create token.

## Build

1. Install [VS Code](https://code.visualstudio.com/) and the **Monkey C** extension.
2. Install the [Connect IQ SDK Manager](https://developer.garmin.com/connect-iq/sdk/). Use it to download the latest SDK and the **Instinct 3 Solar** device.
3. In VS Code, run `Monkey C: Generate a Developer Key` once.
4. Run `python3 tools/make_icon.py` once to create the launcher icon (`resources/drawables/launcher_icon.png`).
5. Open this folder and run `Monkey C: Build for Device` → `instinct3solar45mm`. This produces a `.prg` file.
6. To try it first: `Monkey C: Run` opens the simulator. Use *File → Edit Persistent Storage → Edit Application.Properties* to enter your URL and token.

If the SDK lists your watch under another ID (e.g. a 50 mm or Tactical variant), add that `<iq:product>` to `manifest.xml`.

## Install and configure

**Option A: sideload (quickest, just for you)**
1. Before building, put your URL and token as the default values in `resources/settings/properties.xml`:
   ```xml
   <property id="haUrl" type="string">https://xxxx.ui.nabu.casa</property>
   <property id="haToken" type="string">eyJhbGciOi...</property>
   ```
   **Don't commit that file with your token in it.** Run `git update-index --skip-worktree resources/settings/properties.xml` to keep git from picking up the change.
2. Build, connect the watch over USB and copy the `.prg` into `GARMIN/APPS/`.

The Garmin Connect phone app can only edit settings for store-installed apps, so a sideloaded app has to get its values this way.

**Option B: private beta in the Connect IQ store**
Upload the exported `.iq` file (`Monkey C: Export Project`) as a *beta app* in the Connect IQ developer dashboard. Only you can see it. After installing it from Connect IQ on your phone, set the URL, token, optional thermostat entity and refresh interval under Garmin Connect → your watch → Activities & Apps → Home Assistant → Settings.

## Settings

| Setting        | Meaning |
|----------------|---------|
| `haUrl`        | Base URL, e.g. `https://xxxx.ui.nabu.casa` (no trailing `/api`) |
| `haToken`      | Long-lived access token |
| `climateEntity`| Optional. Which thermostat to show first; defaults to the first `climate.*` |
| `refreshSec`   | Auto-refresh while the app is open (default 60, 0 = off, min 15) |

## Customising what counts as a "problem"

Edit the `U|` and `B|` sections of the template in `source/HaClient.mc`. For example, change `< 20` to raise the low-battery threshold, or add a `rejectattr('entity_id', ...)` to ignore devices you know are offline. You can test changes in HA under **Developer tools → Template** before rebuilding.

## Limitations

- Thermostats in `heat_cool` mode that use a low/high range (`target_temp_low`/`high`) show their mode but can't have the range adjusted, only a single setpoint.
- The map shows at most 20 trackers; the problems list shows the first 25 offline devices plus a "+N more" line.
