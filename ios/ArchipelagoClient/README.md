# Applepelago

Native Swift/SwiftUI Archipelago text client ([`CommonClient.py`](../../CommonClient.py) `run_as_textclient` + [`kvui.py`](../../kvui.py)).

## Requirements

- macOS with Xcode 15+
- iOS 17+ device or simulator
- An Archipelago multiworld server to connect to

## Open the Project

1. Open [`ArchipelagoClient.xcodeproj`](ArchipelagoClient.xcodeproj) in Xcode.
2. Select your development team under **Signing & Capabilities** for the `ArchipelagoClient` target.
3. Choose an iOS simulator or connected device.
4. Build and run (`Cmd+R`).

## Connecting

Enter a server address in the connect bar, for example:

- `archipelago.gg:38281`
- `localhost:38281` (local server)
- `archipelago://SlotName:password@host:38281`

The client uses **Starscream** with `permessage-deflate` compression, which Archipelago servers require. If a plain `ws://` connection fails, the app automatically retries with `wss://`.

After connecting, enter your slot name and password when prompted.

## Features

- WebSocket connection to Archipelago servers (ws/wss)
- Chat and server `PrintJSON` messages
- Client commands: `/connect`, `/disconnect`, `/received`, `/missing`, `/ready`, `/items`, `/locations`, `/help`
- Server commands via chat: `!hint`, `!release`, etc. (sent with `Say`)
- Hints tab with status updates and `!hint` item search
- Data package download/cache for games in the session
- Auto-reconnect with exponential backoff
- Death Link toggle in Settings

## Protocol Version

Client reports Archipelago protocol version **0.6.8**, matching the Python repo.

## Project Structure

```
ArchipelagoClient/
  App/           App entry + view model
  Core/          APContext (CommonContext port)
  Network/       WebSocket, codec, server message handler
  Models/        Protocol types
  Commands/      /command processor
  DataPackage/   Checksum, cache, name lookups
  UI/            SwiftUI views
  Resources/     Bundled Archipelago datapackage
```

## Running Tests

In Xcode: **Product → Test** (`Cmd+U`)

Tests cover JSON codec round-trips, URL parsing, and datapackage checksum generation.

## Manual Verification

1. Start a local server from the Python repo root:
   ```bash
   python MultiServer.py
   ```
2. Generate/host a multiworld or connect to an existing session.
3. Launch the iOS app and connect to `localhost:38281` (simulator) or your machine's LAN IP (device).
4. Verify chat, `/received`, `!hint`, hints tab, and reconnect after backgrounding.

## Notes

- This is a **text/tracker client** only. It does not integrate with game ROMs or emulators.
- `NSAllowsArbitraryLoads` is enabled in `Info.plist` to allow `ws://` connections to local/LAN servers. For production, restrict this to specific domains.
