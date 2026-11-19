# Pub Compass

## Build

Garmin Connect IQ watch app for the Instinct 2 (`instinct2`) and Instinct 2X (`instinct2x`) device profiles. Open this folder in VS Code and run **Monkey C: Build Current Project**. Select `instinct2x` with SDK 9.3.0 for an Instinct 2X, or `instinct2` for an Instinct 2. Configure `monkeyC.developerKeyPath` to point to a local Garmin developer key. The app requires Positioning, Communications and Sensor permissions.

Pub data comes from a prebuilt OpenStreetMap UK snapshot published as versioned UTF-8 data files by GitHub Pages; the watch never contacts Overpass. Files use the `.bin` extension and are requested as octet-stream to avoid content-type parameters that the Connect IQ phone bridge rejects. The phone must still be connected to Garmin Connect Mobile for web requests. The UK is split into one-degree roots and fixed 1/8-degree cells. On entering a new cell, the watch downloads that cell's compact quadtree index, then its selected pub tile. It fetches another pub tile only after entering a different leaf tile. The watch sorts returned candidates by distance and keeps the nearest ten. A missing map file returns “No pubs found”; network failures keep the existing cache and show “Offline”. Tile/root keys and error codes are written to the Connect IQ log. The current Pages URL is `https://dutche007.github.io/pub-compass-server/`.

The tile builder and monthly/manual Pages workflow are under [server/](server/README.md) and `.github/workflows/publish-pages.yml`. The workflow downloads Geofabrik's United Kingdom extract, which includes Great Britain and Northern Ireland, filters pub features, creates compact tiles, checks the nearest-ten guarantee, and deploys a Pages artifact. Tile files are generated artifacts and are not committed. The service contains only a snapshot and does not request live map data. The site and watch UI credit © OpenStreetMap contributors; the data is subject to the ODbL.

Opening-hours strings are interpreted only for the documented subset; unsupported syntax displays “Hours unknown”.

On the compass screen, Up/Down changes the target, Start opens the list, Menu refreshes, and Back exits. On no-pubs and no-phone screens, Start retries.

## Device validation

SDK 9.3.0 provides the `instinct2x` profile for Instinct 2X variants, including Solar Tactical. SDK 8.1.1 exposes `instinct2` as the 176×176 monochrome Instinct 2 / Solar profile. The simulator cannot verify phone-bridged networking, magnetometer calibration or real-world battery and memory use.
