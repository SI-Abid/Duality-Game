# Changelog

All notable changes to Duality are documented here.

---

## [v1.2.0] - 2026-03-19

### Added
- **Internet multiplayer** — players can now connect from different networks worldwide, not just the same LAN
  - Replaced ENet P2P with WebRTC (via `godot-webrtc-native` GDExtension v1.1.0)
  - Firebase Realtime Database repurposed as WebRTC signaling channel (SDP offer/answer + ICE candidates)
  - STUN support via Google's public servers for NAT traversal (works for most home routers)
  - Optional TURN relay server support via `config.cfg [turn]` section for users behind strict NAT
- **WebRTC GDExtension** — bundled `addons/webrtc/` for Linux, Windows, macOS, Android, and iOS

### Fixed
- Duplicate Firebase polling — `start_polling` now no-ops if already polling the same room
- ICE candidates now applied after SDP remote description is set (correct WebRTC handshake order)

### Changed
- Arena sync rate increased from 10 Hz to 30 Hz — boxes and player movement are significantly smoother
- TURN server URL field supports comma-separated values for multi-port fallback (port 80 + 443)

---

## [v1.1.0] - 2026-03-16

### Added
- **Arena (Multiplayer)** — new dedicated scene with two coloured scoring zones
  - Red zone (left wall) belongs to the Host; Blue zone (right wall) belongs to the Guest
  - Push boxes into your zone to score; most boxes at time-up wins
  - Live score HUD: `Red: N | Blue: N` with countdown timer
  - Win / Lose / Draw result screen shown to both players at end of match
  - Scores synced host → guest in real-time via ENet RPC
- **Team identity indicator** — coloured bar + name label so each player always knows their team
- **Practice (Singleplayer)** — renamed `level.tscn` → `practice.tscn`; singleplayer now has its own dedicated scene
- **Shelter zone visual** — semi-transparent green overlay marks the shelter area in practice mode
- **Live practice HUD** — shows `Time: N | Boxes: X/N` progress during singleplayer

### Fixed
- Room code is now only shown after Firebase confirms room creation (eliminates "Room not found" race condition when joining too quickly)
- Polling emits `room_not_found` signal when Firebase returns null — waiting room now returns to lobby automatically if the host cancels instead of hanging forever
- Graceful error message when `config.cfg` is missing or `DB_URL` is empty instead of a silent hang
- `GlobalData.is_single_player` and `is_host` are now reset when returning to lobby from practice mode (prevented state corruption on replay)
- Win condition check efficiency — `get_overlapping_bodies()` is now called once per frame instead of once per box

### Changed
- Multiplayer now loads `arena.tscn`; singleplayer/practice loads `practice.tscn`
- HUD in practice mode shows "Single Player Mode" instead of the room code / P2P label

---

## [v1.0.0] - Initial Release

- Singleplayer practice mode with shelter mechanics
- Multiplayer room creation and joining via Firebase Realtime Database
- P2P gameplay over ENet (low-latency box and player sync)
- Character selection screen
- Touch controls for mobile
