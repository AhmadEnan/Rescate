# BitChat-Style Offline Messaging Feature Design

## 1. Technology Analysis & Recommendation

### Option A: Off-the-shelf Mesh SDKs
*   **Bridgefy Flutter SDK**: 
    *   **Pros**: Highly mature, robust, commercial-grade routing, decent cross-platform support.
    *   **Cons**: Proprietary, commercial licensing required, vendor lock-in. Requires API key initialization (even if it works offline later, setup requires internet).
*   **`flutter_mesh_network`**:
    *   **Pros**: Free, open-source, uses BLE, Wi-Fi Direct (Android), and MultipeerConnectivity (iOS). Built-in flood routing, store-and-forward, loop prevention, and TTL.
    *   **Cons**: Less battle-tested in massive crowds compared to commercial solutions, community-supported.

### Option B: Lower-level P2P (`flutter_p2p_connection`, `flutter_blue_plus`)
*   **Pros**: Maximum control over the stack, free.
*   **Cons**: You must implement the *entire* mesh layer yourself: neighbor tables, multi-hop routing, packet fragmentation (BLE MTU limits), message deduplication, and connection state machines. Huge effort. iOS/Android P2P APIs are notoriously fragmented.

### Option C: Native Platform Channels (Nearby Connections / MultipeerConnectivity)
*   **Pros**: Native performance, official Google/Apple APIs.
*   **Cons**: You have to write the routing logic twice (Kotlin and Swift), maintain native code, and Google's Nearby Connections isn't naturally a multi-hop *mesh* out of the box (it's star/cluster).

### **Recommendation: Option A (`flutter_mesh_network`)**
I highly recommend `flutter_mesh_network`. It completely satisfies your "no internet, mesh-like, offline" constraints while handling the heavy lifting of multi-hop flood routing, transport selection, and iOS/Android compatibility out of the box. It fits perfectly into your existing `p2p_mesh` package structure without requiring a commercial license like Bridgefy.

---

## 2. Architecture & Data Model

We will build this within your existing `p2p_mesh` and `security_crypto` local packages, integrated into the app via a `ChangeNotifier` (matching your current `AppState` pattern).

### Data Model (SQLite via `sqflite` or `sqflite_sqlcipher`)

**Table: `identity`** (Stored securely or via `flutter_secure_storage`)
*   `nodeId` (TEXT, PK): UUID of this device.
*   `displayName` (TEXT): User-chosen name.
*   `privateKey` (TEXT): Encoded private key (Ed25519).
*   `publicKey` (TEXT): Encoded public key.

**Table: `peers`**
*   `nodeId` (TEXT, PK): UUID of the peer.
*   `displayName` (TEXT)
*   `publicKey` (TEXT): For E2EE.
*   `lastSeen` (INTEGER): Epoch timestamp.
*   `inRange` (INTEGER): Boolean flag based on mesh discovery.

**Table: `messages`**
*   `messageId` (TEXT, PK)
*   `senderId` (TEXT)
*   `recipientId` (TEXT): Nullable. If null, it's a public broadcast.
*   `isOutgoing` (INTEGER): Boolean.
*   `encryptedPayload` (BLOB): The cipher text.
*   `nonce` (BLOB): Initialization vector.
*   `timestamp` (INTEGER)
*   `ttl` (INTEGER): Remaining hops.
*   `status` (TEXT): 'queued', 'sent', 'delivered', 'failed'.

---

## 3. Security and E2EE Design

We will use the **`cryptography`** package (implemented inside your `security_crypto` module) which provides robust cross-platform primitives.

*   **Algorithms**: 
    *   **Identity & Signatures**: `Ed25519`
    *   **Key Agreement (ECDH)**: `X25519`
    *   **Symmetric Encryption**: `ChaCha20.poly1305Aead` (excellent for mobile CPUs).

*   **Public Channel**: 
    *   Since true group E2EE without a server is complex (requires pairwise ratcheting like Signal), for a *public* channel in a mesh, we use a fixed, app-wide symmetric key embedded in the app (obfuscated) or simply rely on transport-layer encryption if the channel is meant to be truly public. 
    *   *Recommendation*: Just sign public messages with Ed25519 to prove sender identity, but leave them unencrypted (since everyone in the mesh is meant to read them).

*   **Private 1:1 Messages**:
    *   When sending a message to a node, derive a shared secret using ECDH: `senderPrivateKey` + `recipientPublicKey` = `SharedSecret`.
    *   Encrypt the payload using `ChaCha20.poly1305Aead` with the `SharedSecret` and a randomly generated nonce.
    *   Prepend/attach the nonce and the sender's public key to the payload so the recipient can decrypt it.

```dart
// Pseudo-code for E2EE Private Messaging
import 'package:cryptography/cryptography.dart';

Future<List<int>> encryptMessage(String text, KeyPair senderKey, PublicKey recipientKey) async {
  final algorithm = X25519();
  final sharedSecret = await algorithm.sharedSecretKey(
    keyPair: senderKey, 
    remotePublicKey: recipientKey
  );
  
  final cipher = Chacha20.poly1305Aead();
  final secretBox = await cipher.encrypt(
    utf8.encode(text),
    secretKey: sharedSecret,
  );
  
  // Return concatenation of nonce + mac + cipherText
  return secretBox.concatenation();
}
```

---

## 4. Mesh Routing and Store-and-Forward

The `flutter_mesh_network` handles the physical multi-hop flood routing. 
*   **Routing**: We configure `MeshConfig(maxHops: 10, messageTtl: Duration(hours: 6))`. 
*   **Store-and-Forward Logic (Dart side)**:
    1. User taps "Send".
    2. Message is saved to local SQLite with status `queued`.
    3. We check if the recipient (or any peer for broadcasts) is currently `inRange` via the mesh plugin's `onNodeChanged` stream.
    4. If in range, call `mesh.sendText(encryptedBytes)`. Update status to `sent`.
    5. If offline, keep it `queued`.
    6. **Background/Event Loop**: Whenever a new peer is discovered via the mesh stream, query the DB for `queued` messages destined for them (or broadcasts), and transmit them.

---

## 5. UI/UX & State Management

We will use `ChangeNotifier` to create a `MeshProvider` that wraps the mesh network and DB logic, fitting nicely with your existing `AppStateProvider`.

**a) Nearby Chat Home (Replaces `CommunityScreen`)**
*   **State**: `MeshProvider` (holds `List<Peer>`, `isMeshEnabled`, `myNodeId`).
*   **Layout**: 
    *   Top card: "Enable Nearby Chat" Switch. Displays current user's profile icon and editable display name.
    *   List Tile: "Public Channel Broadcast" (Fixed at top).
    *   ListView of discovered nearby nodes. Green dot if currently in-range, grey if "Last seen 2 hrs ago".

**b) Public Channel Chat**
*   **State**: Subscribes to `MeshProvider.publicMessages`.
*   **Layout**: Standard chat UI. If `mesh.connectedPeers.isEmpty`, show a subtle banner: *"No peers in range. Messages will be queued."*

**c) Private 1:1 Chat**
*   **State**: `MeshProvider.getMessagesForPeer(peerId)`.
*   **Layout**: Standard chat UI. App bar shows a padlock icon indicating E2EE.

**d) Settings/Permissions**
*   Add a section in your existing `SettingsScreen` for "Mesh Networking".
*   Allow clearing queued messages, changing display name, and completely disabling the background mesh service.

---

## 6. Integration Points

*   **Initialization**: Do not initialize the mesh automatically in `main.dart` to save battery. Initialize it only when the user toggles "Enable Nearby Chat" in the UI.
*   **Service Locator**: Instantiate `MeshNetwork` as a singleton or within `MeshProvider`.
*   **App Lifecycle**: Use `WidgetsBindingObserver`. When the app goes to the background, Android will allow BLE advertising/scanning to continue (with proper Foreground Service if required by OS, or just background BLE modes). iOS handles `bluetooth-central` background modes automatically if configured.
*   **Permissions**:
    *   **Android (`AndroidManifest.xml`)**: `BLUETOOTH_SCAN`, `BLUETOOTH_ADVERTISE`, `BLUETOOTH_CONNECT`, `ACCESS_FINE_LOCATION`, `NEARBY_WIFI_DEVICES`.
    *   **iOS (`Info.plist`)**: `NSBluetoothAlwaysUsageDescription`, `NSLocalNetworkUsageDescription`, `UIBackgroundModes` -> `bluetooth-central`, `bluetooth-peripheral`.

---

## 7. Testing Plan

Testing mesh networks on emulators is impossible. You need physical hardware.

**Environment Setup**
*   Minimum **three** physical devices (e.g., 3 Androids, or 2 Androids and 1 iOS).
*   Ensure Wi-Fi is turned **OFF**, Cellular Data is **OFF**, and Bluetooth is **ON** for all devices.
*   Deploy via `flutter run -d <deviceID> --release` (Release mode is crucial for accurate timing/performance of crypto and BLE).

**Phase 1: Unit Tests (No radios needed)**
*   Test `security_crypto` logic: Ensure `encryptMessage` and `decryptMessage` round-trip perfectly.
*   Test `p2p_mesh` DB logic: Queue a message, ensure it retrieves correctly when queried by status.

**Phase 2: Discovery & 1:1 (2 Devices: A and B)**
1.  Open app on A and B. Enable "Nearby Chat".
2.  Verify A sees B's display name, and B sees A's.
3.  Send Private Message A -> B. Verify B receives it instantly.
4.  Kill app on B. Send A -> B. Verify message stays "Queued" on A.
5.  Reopen app on B. Verify A automatically flushes the queue and B receives the message.

**Phase 3: Multi-Hop Mesh Routing (3 Devices: A, B, C)**
1.  Place A, B, and C in a line. 
2.  Ensure A and C are physically out of Bluetooth range of each other (e.g., opposite ends of a large house), but both are in range of B (in the middle).
3.  *Verification*: Check UI. A should see B (in range) and C (multi-hop/last seen). 
4.  A sends a message to C. 
5.  *Success Criteria*: The message jumps A -> B -> C. C receives the message.

**Phase 4: Permissions & Edge Cases**
*   Deny Bluetooth permission on first launch. Verify app handles it gracefully (shows disabled state, prompts user to open OS settings).
*   Turn off Bluetooth via OS quick-settings while app is open. Ensure UI updates to show mesh is inactive.
