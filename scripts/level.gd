extends Node2D
## Level - multiplayer version.
## Uses the Player node already placed in level.tscn as the local player.
## Spawns a RemotePlayer (Node2D ghost) for the other player via Firebase.

const REMOTE_PLAYER_SCENE = preload("res://scenes/remote_player.tscn")

# Spawn positions - adjusted to be safely inside the level bounds
const SPAWN1_POS = Vector2(0, 0)
const SPAWN2_POS = Vector2(-50, 0)

const SYNC_INTERVAL = 0.1

# Disconnect detection: if the remote player's heartbeat (last_seen) value
# hasn't changed for this many consecutive polls, they are considered gone.
# At 4 polls/sec this means ~20 * 0.25s = 5 seconds of no new uploads.
const STALE_POLLS_THRESHOLD = 20

var _remote_player = null
var _local_player = null
var _sync_timer: float = 0.0
var _disconnected: bool = false

# Heartbeat tracking
var _remote_last_seen_value: float = 0.0   # the actual value from Firebase
var _stale_poll_count: int = 0             # how many polls with same value
var _got_first_remote_data: bool = false    # don't check until we've seen them

var _room_label: Label = null
var _disconnect_label: Label = null

var _boxes: Array[RigidBody2D] = []
var _doors: Array = []

func _ready() -> void:
	_setup_hud()
	_spawn_players()
	_find_boxes()
	_find_doors()
	
	# Game sync now happens via ENet RPCs
	NetworkManager.peer_disconnected.connect(_handle_disconnect)
	NetworkManager.server_disconnected.connect(_handle_disconnect)
	
	# We only poll for room cleanup (e.g. host deleting room)
	FirebaseClient.room_updated.connect(_on_room_updated)
	FirebaseClient.start_polling(GlobalData.room_code)

func _find_boxes() -> void:
	# Find all physics boxes in the level
	var boxes_node = get_node_or_null("Boxes")
	if boxes_node:
		for child in boxes_node.get_children():
			if child is RigidBody2D:
				_boxes.append(child)
	else:
		# Fallback in case there's no Boxes node
		for child in get_children():
			if child is RigidBody2D:
				_boxes.append(child)
	
	# If NOT host, we freeze boxes locally and let Host drive them
	if not GlobalData.is_host:
		for box in _boxes:
			box.freeze = true

func _find_doors() -> void:
	for child in get_children():
		if child.name.begins_with("Door") or child.has_method("_open_door"):
			_doors.append(child)
	
	# If NOT host, disable local trigger checking so Host solely controls the doors
	if not GlobalData.is_host:
		for door in _doors:
			if door.has_node("%Trigger"):
				door.get_node("%Trigger").monitoring = false

@rpc("any_peer", "call_local", "reliable")
func _host_apply_push(box_path: String, impulse: Vector2) -> void:
	if not GlobalData.is_host:
		return
	var box = get_node_or_null(box_path)
	if box is RigidBody2D:
		box.apply_central_impulse(impulse)

func guest_push_box(box_path: String, impulse: Vector2) -> void:
	if GlobalData.is_host:
		var box = get_node_or_null(box_path)
		if box is RigidBody2D:
			box.apply_central_impulse(impulse)
	else:
		rpc_id(1, "_host_apply_push", box_path, impulse)

func _setup_hud() -> void:
	var canvas = CanvasLayer.new()
	add_child(canvas)

	_room_label = Label.new()
	_room_label.text = "Room: " + GlobalData.room_code + " (P2P)"
	_room_label.position = Vector2(10, 10)
	_room_label.add_theme_font_size_override("font_size", 14)
	canvas.add_child(_room_label)

	_disconnect_label = Label.new()
	_disconnect_label.text = ""
	_disconnect_label.anchor_left = 0.5
	_disconnect_label.anchor_right = 0.5
	_disconnect_label.anchor_top = 0.3
	_disconnect_label.anchor_bottom = 0.3
	_disconnect_label.offset_left = -200.0
	_disconnect_label.offset_right = 200.0
	_disconnect_label.add_theme_color_override("font_color", Color(1, 0.3, 0.3))
	_disconnect_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_disconnect_label.add_theme_font_size_override("font_size", 18)
	canvas.add_child(_disconnect_label)

func _spawn_players() -> void:
	# Find the existing Player node placed in level.tscn
	_local_player = get_node_or_null("Player")
	if _local_player == null:
		_local_player = find_child("Player")
	
	if _local_player != null:
		if GlobalData.is_host:
			_local_player.global_position = SPAWN1_POS
		else:
			_local_player.global_position = SPAWN2_POS
	else:
		push_error("[Level] No local player found in scene!")

	# Spawn the remote player ghost
	_remote_player = REMOTE_PLAYER_SCENE.instantiate()
	add_child(_remote_player)
	if GlobalData.is_host:
		_remote_player.global_position = SPAWN2_POS
	else:
		_remote_player.global_position = SPAWN1_POS

	var other = GlobalData.other_player
	var other_char = str(other.get("character", "Ninja Frog"))
	var other_name = str(other.get("name", "Player 2"))
	_remote_player.init(other_char, other_name)

func _process(delta: float) -> void:
	if _local_player == null or _disconnected:
		return

	_sync_timer += delta
	# WebRTC sync can be much faster than Firebase!
	if _sync_timer >= 0.033: # ~30 times per second
		_sync_timer = 0.0
		_upload_local_state()

func _upload_local_state() -> void:
	if _local_player == null:
		return
	var sprite = _local_player.get_node_or_null("AnimatedSprite2D")
	var anim_name = "idle"
	var flip = false
	if sprite != null:
		anim_name = str(sprite.animation)
		flip = sprite.flip_h

	var packet = {
		"type": "state",
		"pos_x": _local_player.global_position.x,
		"pos_y": _local_player.global_position.y,
		"vel_x": _local_player.velocity.x,
		"vel_y": _local_player.velocity.y,
		"anim":  anim_name,
		"flip":  flip
	}

	# Host also uploads world object states
	if GlobalData.is_host and _boxes.size() > 0:
		var box_data = []
		for box in _boxes:
			box_data.append({
				"x": box.global_position.x,
				"y": box.global_position.y,
				"r": box.rotation
			})
		packet["boxes"] = box_data

	# Host also uploads door states
	if GlobalData.is_host and _doors.size() > 0:
		var door_data = []
		for door in _doors:
			door_data.append(door.is_open)
		packet["doors"] = door_data

	# Send high-speed state via RPC
	rpc("_apply_remote_state", packet)

@rpc("any_peer", "unreliable")
func _apply_remote_state(data: Dictionary) -> void:
	# Update remote player
	if _remote_player != null and _remote_player.has_method("apply_state"):
		_remote_player.apply_state(data)
	
	# Update boxes if Guest
	if not GlobalData.is_host and data.has("boxes"):
		var box_data = data["boxes"]
		for i in range(min(box_data.size(), _boxes.size())):
			var b = box_data[i]
			_boxes[i].global_position = Vector2(b["x"], b["y"])
			_boxes[i].rotation = b["r"]
			
	# Update doors if Guest
	if not GlobalData.is_host and data.has("doors"):
		var door_data = data["doors"]
		for i in range(min(door_data.size(), _doors.size())):
			var host_is_open = door_data[i]
			var d = _doors[i]
			if d.is_open != host_is_open:
				if host_is_open and d.has_method("_open_door"):
					d._open_door()
				elif not host_is_open and d.has_method("_close_door"):
					d._close_door()
				d.is_open = host_is_open

func _on_room_updated(data: Dictionary) -> void:
	var status = str(data.get("status", "playing"))
	if status == "ended":
		_cleanup_and_exit()

func _handle_disconnect() -> void:
	if _disconnected:
		return
	_disconnected = true
	if _disconnect_label != null:
		_disconnect_label.text = "P2P Connection Lost!\nReturning to menu in 5s..."
	await get_tree().create_timer(5.0).timeout
	_cleanup_and_exit()

func _cleanup_and_exit() -> void:
	FirebaseClient.stop_polling()
	NetworkManager.close_connection()
	if GlobalData.is_host:
		FirebaseClient.delete_room(GlobalData.room_code)
	GlobalData.room_code = ""
	GlobalData.is_host = false
	GlobalData.other_player = {}
	get_tree().change_scene_to_file("res://scenes/character_select.tscn")

func _notification(what: int) -> void:
	if what == NOTIFICATION_EXIT_TREE:
		FirebaseClient.stop_polling()
		NetworkManager.close_connection()
		if GlobalData.is_host and GlobalData.room_code != "":
			FirebaseClient.delete_room(GlobalData.room_code)
