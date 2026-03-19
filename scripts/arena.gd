extends Node2D
## Arena — competitive multiplayer scene.
## Host = Red zone (left). Guest = Blue zone (right).
## Push boxes into your zone to score. Most boxes at time-up wins.

const REMOTE_PLAYER_SCENE = preload("res://scenes/remote_player.tscn")

const SPAWN1_POS = Vector2(0, 0)
const SPAWN2_POS = Vector2(-50, 0)
const SYNC_INTERVAL = 0.033  # ~30 Hz, matches level.gd
const STALE_POLLS_THRESHOLD = 20

# ── Zone geometry (matches the two CollisionShape2D positions in arena.tscn) ──
const ZONE_SIZE     := Vector2(193.5, 79.0)
const ZONE_RED_POS  := Vector2(-735.75, 72.0)  # Host zone — left side
const ZONE_BLUE_POS := Vector2(776.0,   72.5)  # Guest zone — right side

# ── Nodes ─────────────────────────────────────────────────────────────────────
var _local_player = null
var _remote_player = null
var _boxes: Array[RigidBody2D] = []

# ── Zones ─────────────────────────────────────────────────────────────────────
var _zone_red:  Area2D = null
var _zone_blue: Area2D = null
var _score_red:  int = 0
var _score_blue: int = 0

# ── HUD ───────────────────────────────────────────────────────────────────────
var _score_label:  Label = null
var _timer_label:  Label = null
var _result_label: Label = null

# ── Game state ────────────────────────────────────────────────────────────────
var _time_left: float = 0.0
var _game_over: bool  = false

# ── Networking ────────────────────────────────────────────────────────────────
var _sync_timer: float = 0.0
var _disconnected: bool = false
var _remote_last_seen: float = 0.0
var _stale_count: int = 0
var _got_first_remote: bool = false

# ─────────────────────────────────────────────────────────────────────────────
# Init
# ─────────────────────────────────────────────────────────────────────────────

func _ready() -> void:
	_collect_boxes()
	_spawn_players()
	_setup_scoring_zones()
	_setup_hud()

	_time_left = GlobalData.match_duration

	# Guest does not drive box physics — host is authoritative
	if not GlobalData.is_host:
		for box in _boxes:
			box.freeze = true

	NetworkManager.peer_disconnected.connect(_handle_disconnect)
	NetworkManager.server_disconnected.connect(_handle_disconnect)
	FirebaseClient.room_updated.connect(_on_room_updated)
	FirebaseClient.start_polling(GlobalData.room_code)

func _collect_boxes() -> void:
	var boxes_node = get_node_or_null("Boxes")
	if boxes_node:
		for child in boxes_node.get_children():
			if child is RigidBody2D:
				_boxes.append(child)

func _spawn_players() -> void:
	_local_player = get_node_or_null("Player") if get_node_or_null("Player") else find_child("Player")
	if _local_player:
		_local_player.global_position = SPAWN1_POS if GlobalData.is_host else SPAWN2_POS
	else:
		push_error("[Arena] No local Player node found in scene!")

	_remote_player = REMOTE_PLAYER_SCENE.instantiate()
	add_child(_remote_player)
	_remote_player.global_position = SPAWN2_POS if GlobalData.is_host else SPAWN1_POS
	var other = GlobalData.other_player
	_remote_player.init(str(other.get("character", "Ninja Frog")), str(other.get("name", "Player 2")))

# ─────────────────────────────────────────────────────────────────────────────
# Scoring zones
# ─────────────────────────────────────────────────────────────────────────────

func _setup_scoring_zones() -> void:
	# Replace the existing Trigger node (single area with two shapes) with two
	# separate, coloured zones that can be scored independently.
	var old = get_node_or_null("Trigger")
	if old:
		old.queue_free()

	_zone_red  = _make_zone(ZONE_RED_POS,  Color(1.0, 0.2, 0.2, 0.3), "RED")
	_zone_blue = _make_zone(ZONE_BLUE_POS, Color(0.2, 0.4, 1.0, 0.3), "BLUE")

	# Only the host re-counts on each physics overlap event
	_zone_red.body_entered.connect(_recount_scores)
	_zone_red.body_exited.connect(_recount_scores)
	_zone_blue.body_entered.connect(_recount_scores)
	_zone_blue.body_exited.connect(_recount_scores)

func _make_zone(world_pos: Vector2, color: Color, label_text: String) -> Area2D:
	var area = Area2D.new()
	area.monitoring  = true
	area.monitorable = true
	area.position    = world_pos

	var col   = CollisionShape2D.new()
	var shape = RectangleShape2D.new()
	shape.size = ZONE_SIZE
	col.shape  = shape
	area.add_child(col)

	var rect = ColorRect.new()
	rect.color    = color
	rect.size     = ZONE_SIZE
	rect.position = -ZONE_SIZE / 2.0
	area.add_child(rect)

	var lbl = Label.new()
	lbl.text = label_text
	lbl.add_theme_font_size_override("font_size", 16)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.size     = Vector2(80, 24)
	lbl.position = Vector2(-40, -ZONE_SIZE.y / 2.0 - 26)
	area.add_child(lbl)

	add_child(area)
	return area

func _recount_scores(_body = null) -> void:
	if not GlobalData.is_host:
		return
	var red_bodies  = _zone_red.get_overlapping_bodies()
	var blue_bodies = _zone_blue.get_overlapping_bodies()
	_score_red  = 0
	_score_blue = 0
	for box in _boxes:
		if box in red_bodies:  _score_red  += 1
		if box in blue_bodies: _score_blue += 1
	_refresh_score_hud()

# ─────────────────────────────────────────────────────────────────────────────
# HUD
# ─────────────────────────────────────────────────────────────────────────────

func _setup_hud() -> void:
	var canvas = CanvasLayer.new()
	add_child(canvas)

	# Top-left: player name + team colour indicator
	var team_color = Color(1.0, 0.2, 0.2) if GlobalData.is_host else Color(0.2, 0.5, 1.0)
	var zone_name  = "RED"                 if GlobalData.is_host else "BLUE"

	var team_box = ColorRect.new()
	team_box.color    = team_color
	team_box.size     = Vector2(8, 36)
	team_box.position = Vector2(10, 10)
	canvas.add_child(team_box)

	var player_lbl = Label.new()
	player_lbl.position = Vector2(24, 10)
	player_lbl.add_theme_font_size_override("font_size", 14)
	player_lbl.add_theme_color_override("font_color", team_color)
	player_lbl.text = "%s  [%s TEAM]" % [GlobalData.player_name, zone_name]
	canvas.add_child(player_lbl)

	# Top-centre: live score
	_score_label = Label.new()
	_score_label.anchor_left   = 0.5
	_score_label.anchor_right  = 0.5
	_score_label.anchor_top    = 0.0
	_score_label.anchor_bottom = 0.0
	_score_label.offset_left   = -160.0
	_score_label.offset_right  =  160.0
	_score_label.offset_top    =  10.0
	_score_label.offset_bottom =  38.0
	_score_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_score_label.add_theme_font_size_override("font_size", 18)
	canvas.add_child(_score_label)

	# Top-right: timer
	_timer_label = Label.new()
	_timer_label.anchor_left   = 1.0
	_timer_label.anchor_right  = 1.0
	_timer_label.anchor_top    = 0.0
	_timer_label.anchor_bottom = 0.0
	_timer_label.offset_left   = -120.0
	_timer_label.offset_right  =  -10.0
	_timer_label.offset_top    =   10.0
	_timer_label.offset_bottom =   36.0
	_timer_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_timer_label.add_theme_font_size_override("font_size", 16)
	canvas.add_child(_timer_label)

	# Centre: win/lose result (hidden until game ends)
	_result_label = Label.new()
	_result_label.anchor_left   = 0.5
	_result_label.anchor_right  = 0.5
	_result_label.anchor_top    = 0.45
	_result_label.anchor_bottom = 0.45
	_result_label.offset_left   = -220.0
	_result_label.offset_right  =  220.0
	_result_label.offset_top    =  -20.0
	_result_label.offset_bottom =   20.0
	_result_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_result_label.add_theme_font_size_override("font_size", 24)
	canvas.add_child(_result_label)

	_refresh_score_hud()

func _refresh_score_hud() -> void:
	if _score_label:
		_score_label.text = "Red: %d   |   Blue: %d" % [_score_red, _score_blue]

# ─────────────────────────────────────────────────────────────────────────────
# Game loop
# ─────────────────────────────────────────────────────────────────────────────

func _process(delta: float) -> void:
	if _local_player == null or _disconnected or _game_over:
		return

	_time_left -= delta
	if _time_left <= 0.0:
		_time_left = 0.0
		_end_game()
		return

	_timer_label.text = "Time: %d" % int(ceil(_time_left))

	_sync_timer += delta
	if _sync_timer >= SYNC_INTERVAL:
		_sync_timer = 0.0
		_upload_state()

# ─────────────────────────────────────────────────────────────────────────────
# Networking — ENet RPC sync
# ─────────────────────────────────────────────────────────────────────────────

func _upload_state() -> void:
	if _local_player == null:
		return
	var sprite = _local_player.get_node_or_null("AnimatedSprite2D")
	var packet: Dictionary = {
		"type":    "state",
		"pos_x":   _local_player.global_position.x,
		"pos_y":   _local_player.global_position.y,
		"vel_x":   _local_player.velocity.x,
		"vel_y":   _local_player.velocity.y,
		"anim":    str(sprite.animation) if sprite else "idle",
		"flip":    sprite.flip_h if sprite else false,
		"last_seen": Time.get_unix_time_from_system(),
	}

	if GlobalData.is_host and _boxes.size() > 0:
		var box_data = []
		for box in _boxes:
			box_data.append({"x": box.global_position.x, "y": box.global_position.y, "r": box.rotation})
		packet["boxes"]      = box_data
		packet["score_red"]  = _score_red
		packet["score_blue"] = _score_blue

	rpc("_apply_remote_state", packet)

@rpc("any_peer", "unreliable")
func _apply_remote_state(data: Dictionary) -> void:
	if _remote_player and _remote_player.has_method("apply_state"):
		_remote_player.apply_state(data)

	# Guest syncs box positions and scores from host
	if not GlobalData.is_host:
		if data.has("boxes"):
			var bd = data["boxes"]
			for i in range(mini(bd.size(), _boxes.size())):
				_boxes[i].global_position = Vector2(bd[i]["x"], bd[i]["y"])
				_boxes[i].rotation        = bd[i]["r"]
		if data.has("score_red"):
			_score_red  = int(data["score_red"])
			_score_blue = int(data["score_blue"])
			_refresh_score_hud()

	# Heartbeat / stale-peer detection
	if _got_first_remote:
		var seen = float(data.get("last_seen", _remote_last_seen))
		if seen == _remote_last_seen:
			_stale_count += 1
			if _stale_count >= STALE_POLLS_THRESHOLD:
				_handle_disconnect()
		else:
			_stale_count = 0
			_remote_last_seen = seen
	else:
		_got_first_remote    = true
		_remote_last_seen    = float(data.get("last_seen", 0.0))

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

# ─────────────────────────────────────────────────────────────────────────────
# End game
# ─────────────────────────────────────────────────────────────────────────────

func _end_game() -> void:
	if _game_over:
		return
	_game_over = true

	var my_score = _score_red  if GlobalData.is_host else _score_blue
	var op_score = _score_blue if GlobalData.is_host else _score_red

	var msg: String
	var color: Color
	if my_score > op_score:
		msg   = "YOU WIN!  %d – %d" % [my_score, op_score]
		color = Color(0.3, 1.0, 0.3)
	elif my_score < op_score:
		msg   = "YOU LOSE  %d – %d" % [my_score, op_score]
		color = Color(1.0, 0.3, 0.3)
	else:
		msg   = "DRAW  %d – %d" % [my_score, op_score]
		color = Color(1.0, 1.0, 0.3)

	_result_label.text = msg
	_result_label.add_theme_color_override("font_color", color)

	if GlobalData.is_host:
		FirebaseClient.set_room_field(GlobalData.room_code, {"status": "ended"})

	await get_tree().create_timer(4.0).timeout
	_cleanup_and_exit()

func _on_room_updated(data: Dictionary) -> void:
	if str(data.get("status", "playing")) == "ended":
		_end_game()

func _handle_disconnect(_id: int = 0) -> void:
	if _disconnected or _game_over:
		return
	_disconnected = true
	if _result_label:
		_result_label.text = "Opponent disconnected."
		_result_label.add_theme_color_override("font_color", Color(1.0, 0.6, 0.2))
	await get_tree().create_timer(3.0).timeout
	_cleanup_and_exit()

func _cleanup_and_exit() -> void:
	FirebaseClient.stop_polling()
	NetworkManager.close_connection()
	if GlobalData.is_host:
		FirebaseClient.delete_room(GlobalData.room_code)
	GlobalData.room_code   = ""
	GlobalData.is_host     = false
	GlobalData.other_player = {}
	get_tree().change_scene_to_file("res://scenes/lobby.tscn")

func _notification(what: int) -> void:
	if what == NOTIFICATION_EXIT_TREE:
		FirebaseClient.stop_polling()
		NetworkManager.close_connection()
		if GlobalData.is_host and GlobalData.room_code != "":
			FirebaseClient.delete_room(GlobalData.room_code)
