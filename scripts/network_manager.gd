extends Node

## NetworkManager — Internet-capable P2P using WebRTC.
## Uses WebRTCMultiplayerPeer + WebRTCPeerConnection so two players can connect
## over the internet via STUN/TURN NAT traversal.
## Firebase (via waiting_room.gd) acts as the signaling channel for SDP and ICE exchange.
##
## Peer IDs:
##   Host (server) = 1
##   Guest (client) = 2

signal peer_connected(id: int)
signal peer_disconnected(id: int)
signal connection_failed
signal connection_succeeded
signal server_disconnected

## Emitted when a local SDP offer or answer is ready to send via Firebase.
signal sdp_created(type: String, sdp: String)
## Emitted for each local ICE candidate to send via Firebase.
signal ice_candidate_ready(media: String, index: int, name: String)

var _rtc_mp: WebRTCMultiplayerPeer
var _rtc_conn: WebRTCPeerConnection
var is_host: bool = false

const DEFAULT_ICE_SERVERS = [
	{"urls": ["stun:stun.l.google.com:19302"]},
	{"urls": ["stun:stun1.l.google.com:19302"]}
]

func _ready() -> void:
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.connected_to_server.connect(_on_connection_succeeded)
	multiplayer.server_disconnected.connect(_on_server_disconnected)

func _process(_delta: float) -> void:
	# WebRTCPeerConnection must be polled every frame to advance its state machine.
	if _rtc_conn != null:
		_rtc_conn.poll()

# ─────────────────────────────────────────────────────────────────────────────
# Public API
# ─────────────────────────────────────────────────────────────────────────────

## Host calls this. Creates a WebRTC server and generates an SDP offer.
## Listen for sdp_created(type, sdp) to get the offer to upload to Firebase.
func setup_host_webrtc() -> void:
	is_host = true
	_rtc_mp = WebRTCMultiplayerPeer.new()
	_rtc_mp.create_server()

	_rtc_conn = _make_peer_connection()
	_rtc_mp.add_peer(_rtc_conn, 2)  # Guest will have peer ID 2
	multiplayer.multiplayer_peer = _rtc_mp

	_rtc_conn.create_offer()
	print("[NetworkManager] WebRTC host setup — awaiting SDP offer...")

## Guest calls this with the SDP offer from Firebase.
## Automatically generates an answer; listen for sdp_created("answer", sdp).
func setup_client_webrtc(offer_sdp: String) -> void:
	is_host = false
	_rtc_mp = WebRTCMultiplayerPeer.new()
	_rtc_mp.create_client(2)  # Client is peer 2; server/host is always peer 1

	_rtc_conn = _make_peer_connection()
	_rtc_mp.add_peer(_rtc_conn, 1)  # Host has peer ID 1
	multiplayer.multiplayer_peer = _rtc_mp

	_rtc_conn.set_remote_description("offer", offer_sdp)
	print("[NetworkManager] WebRTC client setup — set remote offer, awaiting answer SDP...")

## Host calls this once the guest's SDP answer arrives from Firebase.
func apply_answer(answer_sdp: String) -> void:
	if _rtc_conn == null:
		push_error("[NetworkManager] apply_answer called but no connection exists")
		return
	_rtc_conn.set_remote_description("answer", answer_sdp)
	print("[NetworkManager] Applied remote answer SDP")

## Call this for each ICE candidate received from the remote side via Firebase.
func add_ice_candidate(media: String, index: int, name: String) -> void:
	if _rtc_conn == null:
		push_error("[NetworkManager] add_ice_candidate called but no connection exists")
		return
	_rtc_conn.add_ice_candidate(media, index, name)

func close_connection() -> void:
	if _rtc_conn != null:
		_rtc_conn.close()
		_rtc_conn = null
	if _rtc_mp != null:
		_rtc_mp.close()
	multiplayer.multiplayer_peer = null
	_rtc_mp = null
	is_host = false
	print("[NetworkManager] Connection closed")

# ─────────────────────────────────────────────────────────────────────────────
# Internal
# ─────────────────────────────────────────────────────────────────────────────

func _make_peer_connection() -> WebRTCPeerConnection:
	var conn := WebRTCPeerConnection.new()
	conn.initialize({"iceServers": _build_ice_servers()})
	conn.session_description_created.connect(_on_sdp_created)
	conn.ice_candidate_created.connect(_on_ice_candidate_created)
	return conn

func _build_ice_servers() -> Array:
	var servers: Array = DEFAULT_ICE_SERVERS.duplicate()
	# Append optional TURN servers from config.cfg if configured.
	# Supports a comma-separated list of urls for multi-port fallback.
	var cfg := ConfigFile.new()
	if cfg.load("res://config.cfg") == OK:
		var urls_raw: String = cfg.get_value("turn", "url", "")
		var username: String = cfg.get_value("turn", "username", "")
		var credential: String = cfg.get_value("turn", "credential", "")
		if not urls_raw.is_empty():
			var urls: Array = []
			for u in urls_raw.split(","):
				var trimmed = u.strip_edges()
				if not trimmed.is_empty():
					urls.append(trimmed)
			var turn_entry := {"urls": urls}
			if not username.is_empty():
				turn_entry["username"] = username
			if not credential.is_empty():
				turn_entry["credential"] = credential
			servers.append(turn_entry)
			print("[NetworkManager] TURN servers configured: ", urls)
	return servers

func _on_sdp_created(type: String, sdp: String) -> void:
	_rtc_conn.set_local_description(type, sdp)
	print("[NetworkManager] SDP created (type=%s)" % type)
	sdp_created.emit(type, sdp)

func _on_ice_candidate_created(media: String, index: int, name: String) -> void:
	print("[NetworkManager] ICE candidate ready (media=%s index=%d)" % [media, index])
	ice_candidate_ready.emit(media, index, name)

# ─────────────────────────────────────────────────────────────────────────────
# Multiplayer Signals
# ─────────────────────────────────────────────────────────────────────────────

func _on_peer_connected(id: int) -> void:
	print("[NetworkManager] Peer connected: ", id)
	peer_connected.emit(id)

func _on_peer_disconnected(id: int) -> void:
	print("[NetworkManager] Peer disconnected: ", id)
	peer_disconnected.emit(id)

func _on_connection_failed() -> void:
	print("[NetworkManager] Connection failed!")
	connection_failed.emit()

func _on_connection_succeeded() -> void:
	print("[NetworkManager] Connection succeeded!")
	connection_succeeded.emit()

func _on_server_disconnected() -> void:
	print("[NetworkManager] Server disconnected!")
	server_disconnected.emit()
