extends Control
## Waiting Room — shown after room is full, before game starts

@onready var player1_name: Label   = $VBox/PlayersBox/Player1/NameLabel
@onready var player1_char: Label   = $VBox/PlayersBox/Player1/CharLabel
@onready var player2_name: Label   = $VBox/PlayersBox/Player2/NameLabel
@onready var player2_char: Label   = $VBox/PlayersBox/Player2/CharLabel
@onready var start_btn: Button     = $VBox/StartButton
@onready var status_label: Label   = $VBox/StatusLabel
@onready var room_code_lbl: Label  = $VBox/RoomCodeLabel

var _network_started: bool = false
var _peer_connected: bool = false

func _ready() -> void:
	room_code_lbl.text = "Room: %s" % GlobalData.room_code
	start_btn.visible = GlobalData.is_host
	start_btn.disabled = true
	status_label.text = "Syncing with Firebase..."

	start_btn.pressed.connect(_on_start_pressed)
	FirebaseClient.room_updated.connect(_on_room_updated)
	FirebaseClient.start_polling(GlobalData.room_code)
	
	NetworkManager.peer_connected.connect(_on_peer_connected)
	NetworkManager.connection_succeeded.connect(_on_connection_succeeded)

func _on_peer_connected(_id: int) -> void:
	if GlobalData.is_host:
		_peer_connected = true
		start_btn.disabled = false
		status_label.text = "P2P Connected! Press Start."

func _on_connection_succeeded() -> void:
	if not GlobalData.is_host:
		_peer_connected = true
		status_label.text = "P2P Connected! Waiting for host..."

func _on_room_updated(data: Dictionary) -> void:
	var players: Dictionary = data.get("players", {})
	var status: String = data.get("status", "waiting")
	var host_ip: String = data.get("host_ip", "")

	# 1. Populate player cards
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
		
		# 2. Start Network initialization if not done
		if not _network_started:
			if GlobalData.is_host:
				_network_started = true
				if NetworkManager.setup_host():
					var ip = NetworkManager.get_local_ip()
					FirebaseClient.set_room_field(GlobalData.room_code, { "host_ip": ip })
					status_label.text = "Hosting on " + ip + "... waiting for peer."
				else:
					status_label.text = "Failed to start Host."
			else:
				if host_ip != "":
					_network_started = true
					status_label.text = "Connecting to Host at " + host_ip + "..."
					NetworkManager.setup_client(host_ip)

	# 4. Success — Host clicked start
	if status == "playing":
		FirebaseClient.stop_polling()
		get_tree().change_scene_to_file("res://scenes/level.tscn")

func _on_start_pressed() -> void:
	start_btn.disabled = true
	status_label.text = "Starting game..."
	FirebaseClient.set_room_field(GlobalData.room_code, { "status": "playing" })
