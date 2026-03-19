extends Control
## Waiting Room — shown after room is full, before game starts.
## Handles WebRTC signaling via Firebase: SDP offer/answer + ICE candidate exchange.

@onready var player1_name: Label   = $VBox/PlayersBox/Player1/NameLabel
@onready var player1_char: Label   = $VBox/PlayersBox/Player1/CharLabel
@onready var player2_name: Label   = $VBox/PlayersBox/Player2/NameLabel
@onready var player2_char: Label   = $VBox/PlayersBox/Player2/CharLabel
@onready var start_btn: Button     = $VBox/StartButton
@onready var status_label: Label   = $VBox/StatusLabel
@onready var room_code_lbl: Label  = $VBox/RoomCodeLabel

var _network_started: bool = false
var _peer_connected: bool = false
var _answer_applied: bool = false

# Local ICE candidates collected before or after signaling completes.
var _local_ice: Array = []
# How many of the remote side's ICE candidates we've already applied.
var _applied_remote_ice_count: int = 0

func _ready() -> void:
	room_code_lbl.text = "Room: %s" % GlobalData.room_code
	start_btn.visible = GlobalData.is_host
	start_btn.disabled = true
	status_label.text = "Syncing with Firebase..."

	start_btn.pressed.connect(_on_start_pressed)
	FirebaseClient.room_updated.connect(_on_room_updated)
	FirebaseClient.room_not_found.connect(_on_room_not_found)
	FirebaseClient.start_polling(GlobalData.room_code)

	NetworkManager.peer_connected.connect(_on_peer_connected)
	NetworkManager.connection_succeeded.connect(_on_connection_succeeded)
	NetworkManager.sdp_created.connect(_on_sdp_created)
	NetworkManager.ice_candidate_ready.connect(_on_ice_candidate_ready)

# ─────────────────────────────────────────────────────────────────────────────
# NetworkManager signal handlers
# ─────────────────────────────────────────────────────────────────────────────

func _on_peer_connected(_id: int) -> void:
	if GlobalData.is_host:
		_peer_connected = true
		start_btn.disabled = false
		status_label.text = "Connected! Press Start."

func _on_connection_succeeded() -> void:
	if not GlobalData.is_host:
		_peer_connected = true
		status_label.text = "Connected! Waiting for host..."

func _on_sdp_created(type: String, sdp: String) -> void:
	# Upload our local SDP to Firebase so the other side can read it.
	if type == "offer":
		FirebaseClient.set_room_field(GlobalData.room_code, {"sdp_offer": sdp})
		status_label.text = "Offer sent — waiting for guest..."
		print("[WaitingRoom] Uploaded SDP offer")
	elif type == "answer":
		FirebaseClient.set_room_field(GlobalData.room_code, {"sdp_answer": sdp})
		status_label.text = "Answer sent — connecting..."
		print("[WaitingRoom] Uploaded SDP answer")

func _on_ice_candidate_ready(media: String, index: int, name: String) -> void:
	# Collect locally and push as a JSON string — Firebase won't mangle strings
	# into dicts the way it does with nested arrays/objects.
	_local_ice.append({"media": media, "index": index, "name": name})
	var field_key: String = "ice_host" if GlobalData.is_host else "ice_guest"
	FirebaseClient.set_room_field(GlobalData.room_code, {field_key: JSON.stringify(_local_ice)})
	print("[WaitingRoom] Uploaded %d local ICE candidate(s)" % _local_ice.size())

# ─────────────────────────────────────────────────────────────────────────────
# Firebase polling handler
# ─────────────────────────────────────────────────────────────────────────────

func _on_room_updated(data: Dictionary) -> void:
	var players: Dictionary = data.get("players", {})
	var status: String = data.get("status", "waiting")

	# 1. Populate player name/character cards
	var host_p = null
	var guest_p = null
	for pid in players.keys():
		var p = players[pid]
		if p.get("is_host", false):
			host_p = p
		else:
			guest_p = p
		if pid != GlobalData.player_id:
			GlobalData.other_player = p

	if host_p != null:
		player1_name.text = host_p.get("name", "???")
		player1_char.text = host_p.get("character", "")
	if guest_p != null:
		player2_name.text = guest_p.get("name", "???")
		player2_char.text = guest_p.get("character", "")

	# 2. Host: start WebRTC as soon as both players are present (generates offer).
	if GlobalData.is_host and guest_p != null and not _network_started:
		_network_started = true
		status_label.text = "Generating connection offer..."
		NetworkManager.setup_host_webrtc()

	# 3. Guest: start WebRTC once the host's SDP offer has arrived in Firebase.
	if not GlobalData.is_host and not _network_started:
		var offer: String = data.get("sdp_offer", "")
		if not offer.is_empty():
			_network_started = true
			status_label.text = "Received offer — generating answer..."
			NetworkManager.setup_client_webrtc(offer)

	# 4. Host: apply guest's SDP answer when it arrives
	if GlobalData.is_host and not _answer_applied:
		var answer: String = data.get("sdp_answer", "")
		if not answer.is_empty():
			_answer_applied = true
			NetworkManager.apply_answer(answer)
			status_label.text = "Answer received — finalizing connection..."

	# 5. Apply remote ICE candidates we haven't seen yet.
	# Stored as a JSON string to survive Firebase's array→dict mangling.
	# Host must wait for the answer SDP to be applied first (WebRTC spec order).
	var remote_ice_key: String = "ice_guest" if GlobalData.is_host else "ice_host"
	var raw = data.get(remote_ice_key, "")
	var remote_ice: Array = JSON.parse_string(raw) if raw is String and not raw.is_empty() else []
	var ready_for_ice: bool = _network_started and (not GlobalData.is_host or _answer_applied)
	if ready_for_ice and remote_ice.size() > _applied_remote_ice_count:
		for i in range(_applied_remote_ice_count, remote_ice.size()):
			var c: Dictionary = remote_ice[i]
			NetworkManager.add_ice_candidate(
				c.get("media", ""),
				c.get("index", 0),
				c.get("name", "")
			)
		_applied_remote_ice_count = remote_ice.size()
		print("[WaitingRoom] Applied %d remote ICE candidate(s)" % _applied_remote_ice_count)

	# 6. Host clicked start — transition to game
	if status == "playing":
		FirebaseClient.stop_polling()
		get_tree().change_scene_to_file("res://scenes/arena.tscn")

func _on_room_not_found(_code: String) -> void:
	FirebaseClient.stop_polling()
	status_label.text = "Room no longer exists. Returning to lobby..."
	await get_tree().create_timer(2.0).timeout
	get_tree().change_scene_to_file("res://scenes/lobby.tscn")

func _on_start_pressed() -> void:
	start_btn.disabled = true
	status_label.text = "Starting game..."
	FirebaseClient.set_room_field(GlobalData.room_code, {"status": "playing"})
