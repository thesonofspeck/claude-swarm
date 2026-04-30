# iOS pairing + APNs setup

The iOS companion (`ios/ClaudeSwarmRemote`) pairs to your Mac over a local
WebSocket and receives APNs pushes for events that need attention. There's
no relay server — the Mac talks directly to Apple's push endpoint.

## What you need

- Apple Developer account (free or paid)
- Mac and iPhone on the same network or VPN, with the iPhone able to
  reach the Mac on TCP/7321
- An APNs auth key (`.p8`) and the associated key id + team id

## One-time setup

### 1. Generate an APNs auth key

1. Sign in to [developer.apple.com/account/resources/authkeys](https://developer.apple.com/account/resources/authkeys/list)
2. Click the **+** button next to "Keys"
3. Tick **Apple Push Notifications service (APNs)**, give the key a name,
   click **Continue** then **Register**
4. **Download** the `.p8` file. Apple only lets you download it once.
5. Note the **Key ID** shown next to the key (10 chars).
6. Note your **Team ID** from the top right of the developer portal (10 chars).

### 2. Build the iOS app

```sh
brew install xcodegen
cd ios && xcodegen generate
open ClaudeSwarmRemote.xcodeproj
```

In Xcode:

1. Select the **ClaudeSwarmRemote** target.
2. **Signing & Capabilities** → set your Development Team and bundle id
   (defaults to `com.claudeswarm.remote` — change it to one you own).
3. Confirm **Push Notifications** capability is on.
4. Build and run on a real device (push doesn't work in the simulator).
5. Accept notification permissions on first launch.

### 3. Configure APNs on the Mac

1. In Claude Swarm on the Mac: **⌘,** (Settings) → **APNs** tab.
2. Enter your **Team ID**, **Key ID**, and the iOS app's **bundle id**
   (must match what you set in Xcode).
3. Click **Upload .p8 key…** and pick the file you downloaded from Apple.
   The key is stored in Keychain — never written to disk.
4. Pick **Production** unless you're using a sandboxed app build.
5. Toggle **Send pushes to paired devices** on.
6. Click **Save APNs settings**.

### 4. Pair the iPhone

1. On the Mac: Settings → **iPhone** tab → **Pair new iPhone…**.
2. A QR code appears with a 5-minute single-use code.
3. On the iPhone, open Claude Swarm Remote. If you've never paired
   before, you'll see the **Pair your Mac** screen — tap **Scan
   pairing QR**. Otherwise tap the iPhone-icon top-right of Sessions
   then **Scan pairing QR** in the new flow.
4. Point the camera at the Mac's QR. The app authenticates and you
   land on the Sessions list.

The pair record is stored in iOS Keychain on the device and in Mac
Keychain (`com.claudeswarm.pairings`) on the Mac. Either side can
unpair from Settings.

## How it works

- Transport: `wss://` over the user's LAN/VPN. The Mac generates a
  self-signed P-256 cert on first launch (via `/usr/bin/openssl`) and
  stores it in Keychain. The QR pairing invite carries the cert's
  SHA-256 thumbprint; the iOS client pins on it via a
  `URLSessionDelegate`, so a host reachable on the same network can't
  impersonate the Mac without also stealing the cert.
- Pairing exchange: iOS sends a `pair` WireMessage with the device id +
  APNs token; Mac mints a 32-byte bearer token and returns it in
  `paired`. Subsequent reconnects authenticate via `hello`.
- Live channel: WebSocket carries `ServerEvent`s (sessionsSnapshot,
  sessionUpdate, approvalRequest) Mac→iOS and `ClientCommand`s
  (approve, sendInput) iOS→Mac.
- Push: when a Notification hook fires on the Mac, the
  RemoteCoordinator (a) broadcasts an `approvalRequest` event over the
  live socket and (b) sends an APNs push to every paired device's
  token via the Mac's HTTP/2 client (`api.push.apple.com`). The push
  payload uses category `APPROVAL_REQUEST` so iOS shows Approve /
  Deny action buttons.

## Always-on Mac

When ≥1 device is paired, the Mac holds a `PreventUserIdleSystemSleep`
IOPM assertion so the agent + hook script keep running while you're
away.

- Default: assertion is held only on AC power. Toggle this in
  Settings → iPhone → "Allow sleep on battery."
- Lid-closed sleep: not overridden by default. If you want the Mac to
  stay running with the lid closed, run `caffeinate -d` separately or
  enable the system **"Prevent automatic sleeping when display is off"**
  in System Settings → Battery (Mac on power adapter).

## Troubleshooting

**iOS shows "Could not reach Mac"** — usually the iPhone can't reach
TCP/7321 on the Mac's IP. Verify with `nc -zv <mac-ip> 7321` from a
shell on the same VPN as the iPhone.

**Pushes never arrive** — check Settings → APNs:
- Team / Key ID match your Apple Developer portal exactly
- Bundle ID matches the Xcode-built app's bundle id (case-sensitive)
- Environment is `production` for App Store / TestFlight builds, and
  `sandbox` only for Xcode-direct development builds
- The `.p8` is the same one you downloaded from the portal

**iOS shows "Pairing failed: code expired"** — pairing codes are
single-use and last 5 minutes. Click **New code** in the Mac sheet.

**Session input doesn't reach Claude** — the Mac forwards
`ClaudeSwarm.RemoteInput` notifications to the running PTY, but only
sessions started after the v0.1 with-iOS build will pick up the new
listener. Restart any pre-existing session.
