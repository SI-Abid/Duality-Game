extends Control
## Lobby — Create Room or Join Room with a code

enum Mode { MENU, CREATE, JOIN }
var _mode: Mode = Mode.MENU

@onready var menu_panel: Control     = $Content/MenuPanel
@onready var create_panel: Control   = $Content/CreatePanel
@onready var join_panel: Control     = $Content/JoinPanel
@onready var status_label: Label     = $Content/StatusLabel

# Menu panel
@onready var create_btn: Button      = $Content/MenuPanel/VBox/CreateBtn
@onready var join_btn: Button        = $Content/MenuPanel/VBox/JoinBtn
@onready var back_btn_menu: Button   = $Content/MenuPanel/VBox/BackBtn

# Create panel
@onready var room_code_label: Label  = $Content/CreatePanel/VBox/RoomCodeLabel
@onready var waiting_label: Label    = $Content/CreatePanel/VBox/WaitingLabel
@onready var cancel_create_btn: Button = $Content/CreatePanel/VBox/CancelBtn

# Join panel
@onready var code_input: LineEdit    = $Content/JoinPanel/VBox/CodeInput
@onready var join_confirm_btn: Button = $Content/JoinPanel/VBox/JoinConfirmBtn
@onready var cancel_join_btn: Button = $Content/JoinPanel/VBox/CancelBtn

func _ready() -> void:
	_show_panel(Mode.MENU)
	create_btn.pressed.connect(_on_create_pressed)
	join_btn.pressed.connect(_on_join_pressed)
	back_btn_menu.pressed.connect(_on_back_to_menu)
	cancel_create_btn.pressed.connect(_on_cancel_create)
	cancel_join_btn.pressed.connect(_on_cancel_join)
	join_confirm_btn.pressed.connect(_on_join_confirm)
	code_input.text_changed.connect(func(t): join_confirm_btn.disabled = t.strip_edges().length() < 6)
	join_confirm_btn.disabled = true

	FirebaseClient.room_updated.connect(_on_room_updated)

func _show_panel(mode: Mode) -> void:
	_mode = mode
	menu_panel.visible   = (mode == Mode.MENU)
	create_panel.visible = (mode == Mode.CREATE)
	join_panel.visible   = (mode == Mode.JOIN)
	status_label.text    = ""

# ── CREATE ROOM ───────────────────────────────────────────────────────────────

func _on_create_pressed() -> void:
	var code := FirebaseClient.generate_room_code()
	GlobalData.room_code = code
	GlobalData.is_host   = true

	var player_data := _build_player_data()
	room_code_label.text = "Room Code:\n%s" % code
	waiting_label.text   = "Waiting for another player..."
	_show_panel(Mode.CREATE)
	status_label.text = "Creating room..."

	FirebaseClient.create_room(code, player_data)
	await get_tree().create_timer(0.5).timeout
	FirebaseClient.start_polling(code)
	status_label.text = "Share your room code!"

func _on_cancel_create() -> void:
	FirebaseClient.stop_polling()
	if GlobalData.room_code != "":
		FirebaseClient.delete_room(GlobalData.room_code)
	GlobalData.room_code = ""
	GlobalData.is_host   = false
	_show_panel(Mode.MENU)

# ── JOIN ROOM ─────────────────────────────────────────────────────────────────

func _on_join_pressed() -> void:
	_show_panel(Mode.JOIN)

func _on_join_confirm() -> void:
	var code := code_input.text.strip_edges().to_upper()
	if code.length() < 6:
		return
	status_label.text = "Looking for room..."
	join_confirm_btn.disabled = true

	FirebaseClient.check_room(code, func(ok, data):
		if not ok or data == null:
			status_label.text = "Room not found. Check the code."
			join_confirm_btn.disabled = false
			return
		if data.get("status", "") != "waiting":
			status_label.text = "Room is already in progress."
			join_confirm_btn.disabled = false
			return
		# Room exists — join it
		GlobalData.room_code = code
		GlobalData.is_host   = false
		var player_data := _build_player_data()
		status_label.text = "Joining room..."
		FirebaseClient.join_room(code, player_data, func(ok2, _d):
			if not ok2:
				status_label.text = "Failed to join. Try again."
				join_confirm_btn.disabled = false
				return
			FirebaseClient.start_polling(code)
	))

func _on_cancel_join() -> void:
	FirebaseClient.stop_polling()
	GlobalData.room_code = ""
	GlobalData.is_host   = false
	_show_panel(Mode.MENU)

func _on_back_to_menu() -> void:
	get_tree().change_scene_to_file("res://scenes/character_select.tscn")

# ── POLLING HANDLER ───────────────────────────────────────────────────────────

func _on_room_updated(data: Dictionary) -> void:
	# Check for status changes
	var status: String = data.get("status", "waiting")
	var players: Dictionary = data.get("players", {})

	if _mode == Mode.CREATE:
		var count := players.size()
		waiting_label.text = "Players connected: %d / 2\nWaiting for another player..." % count if count < 2 else "Players connected: %d / 2\nReady!" % count
		# If someone joined, move to waiting room
		if count >= 2:
			FirebaseClient.stop_polling()
			get_tree().change_scene_to_file("res://scenes/waiting_room.tscn")

	elif _mode == Mode.JOIN:
		# Successfully joined — go to waiting room
		FirebaseClient.stop_polling()
		get_tree().change_scene_to_file("res://scenes/waiting_room.tscn")

	if status == "playing":
		FirebaseClient.stop_polling()
		get_tree().change_scene_to_file("res://scenes/level.tscn")

# ── Helpers ───────────────────────────────────────────────────────────────────

func _build_player_data() -> Dictionary:
	return {
		"name":      GlobalData.player_name,
		"character": GlobalData.selected_character,
		"ready":     false,
		"pos_x":     0.0,
		"pos_y":     0.0,
		"vel_x":     0.0,
		"vel_y":     0.0,
		"anim":      "idle",
		"flip":      false,
		"alive":     true,
		"last_seen": Time.get_unix_time_from_system()
	}
