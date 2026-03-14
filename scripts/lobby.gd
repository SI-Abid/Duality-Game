extends Control
## Lobby — Main Menu for Game Mode Selection and Room Management

enum Mode { MENU, MULTI_MENU, CREATE, JOIN, SINGLE }
var _mode: Mode = Mode.MENU

@onready var menu_panel: Control      = $Content/MenuPanel
@onready var multi_menu_panel: Control= $Content/MultiMenuPanel
@onready var create_panel: Control    = $Content/CreatePanel
@onready var join_panel: Control      = $Content/JoinPanel
@onready var single_panel: Control    = $Content/SinglePanel
@onready var status_label: Label      = $Content/StatusLabel

# Menu panel (Game Mode Select)
@onready var single_player_btn: Button  = $Content/MenuPanel/VBox/SinglePlayerBtn
@onready var multiplayer_btn: Button    = $Content/MenuPanel/VBox/MultiplayerBtn
@onready var back_btn_main: Button      = $Content/MenuPanel/VBox/BackBtn

# Multi Menu panel (Create/Join)
@onready var create_btn: Button         = $Content/MultiMenuPanel/VBox/CreateBtn
@onready var join_btn: Button           = $Content/MultiMenuPanel/VBox/JoinBtn
@onready var back_btn_multi: Button     = $Content/MultiMenuPanel/VBox/BackBtn

# Create panel
@onready var room_code_label: Label     = $Content/CreatePanel/VBox/RoomCodeLabel
@onready var waiting_label: Label       = $Content/CreatePanel/VBox/WaitingLabel
@onready var cancel_create_btn: Button  = $Content/CreatePanel/VBox/CancelBtn

# Join panel
@onready var code_input: LineEdit       = $Content/JoinPanel/VBox/CodeInput
@onready var join_confirm_btn: Button   = $Content/JoinPanel/VBox/JoinConfirmBtn
@onready var cancel_join_btn: Button    = $Content/JoinPanel/VBox/CancelBtn

# Single panel
@onready var start_single_btn: Button   = $Content/SinglePanel/VBox/StartSingleBtn
@onready var cancel_single_btn: Button  = $Content/SinglePanel/VBox/CancelSingleBtn

var _timeout_select: OptionButton

func _ready() -> void:
	_show_panel(Mode.MENU)
	
	# Main menu connections
	single_player_btn.pressed.connect(_on_single_menu_pressed)
	multiplayer_btn.pressed.connect(_on_multi_menu_pressed)
	back_btn_main.pressed.connect(_on_back_to_char_select)
	
	# Multi menu connections
	create_btn.pressed.connect(_on_create_pressed)
	join_btn.pressed.connect(_on_join_pressed)
	back_btn_multi.pressed.connect(_on_back_to_main_menu)
	
	# Create/Join flow connections
	cancel_create_btn.pressed.connect(_on_cancel_create)
	cancel_join_btn.pressed.connect(_on_cancel_join)
	join_confirm_btn.pressed.connect(_on_join_confirm)
	code_input.text_changed.connect(func(t): join_confirm_btn.disabled = t.strip_edges().length() < 4)
	join_confirm_btn.disabled = true
	
	# Single player connections
	start_single_btn.pressed.connect(_on_start_single)
	cancel_single_btn.pressed.connect(_on_back_to_main_menu)
	
	_setup_timeout_select()

	FirebaseClient.room_updated.connect(_on_room_updated)

func _show_panel(mode: Mode) -> void:
	_mode = mode
	menu_panel.visible       = (mode == Mode.MENU)
	multi_menu_panel.visible = (mode == Mode.MULTI_MENU)
	create_panel.visible     = (mode == Mode.CREATE)
	join_panel.visible       = (mode == Mode.JOIN)
	single_panel.visible     = (mode == Mode.SINGLE)
	status_label.text        = ""

# ── NAVIGATION ───────────────────────────────────────────────────────────────

func _on_back_to_char_select() -> void:
	get_tree().change_scene_to_file("res://scenes/character_select.tscn")

func _on_back_to_main_menu() -> void:
	_show_panel(Mode.MENU)

func _on_multi_menu_pressed() -> void:
	_show_panel(Mode.MULTI_MENU)

# ── SINGLE PLAYER ────────────────────────────────────────────────────────────

func _on_single_menu_pressed() -> void:
	_show_panel(Mode.SINGLE)

func _on_start_single() -> void:
	GlobalData.is_single_player = true
	GlobalData.is_host = true
	
	var timeout = 90.0
	if _timeout_select:
		timeout = _timeout_select.get_item_metadata(_timeout_select.selected)
	GlobalData.match_duration = timeout
	
	get_tree().change_scene_to_file("res://scenes/level.tscn")

# ── CREATE ROOM ───────────────────────────────────────────────────────────────

func _on_create_pressed() -> void:
	var code := FirebaseClient.generate_room_code()
	GlobalData.room_code = code
	GlobalData.is_host   = true
	GlobalData.is_single_player = false

	var player_data := _build_player_data()
	room_code_label.text = "Room Code:\n%s" % code
	waiting_label.text   = "Waiting for another player..."
	_show_panel(Mode.CREATE)
	status_label.text = "Creating room..."
	
	var timeout = 90.0
	if _timeout_select:
		timeout = _timeout_select.get_item_metadata(_timeout_select.selected)
	GlobalData.match_duration = timeout

	FirebaseClient.create_room(code, player_data, timeout)
	await get_tree().create_timer(0.5).timeout
	FirebaseClient.start_polling(code)
	status_label.text = "Share your room code!"

func _on_cancel_create() -> void:
	FirebaseClient.stop_polling()
	if GlobalData.room_code != "":
		FirebaseClient.delete_room(GlobalData.room_code)
	GlobalData.room_code = ""
	GlobalData.is_host   = false
	_show_panel(Mode.MULTI_MENU)

# ── JOIN ROOM ─────────────────────────────────────────────────────────────────

func _on_join_pressed() -> void:
	_show_panel(Mode.JOIN)
	code_input.text = ""
	join_confirm_btn.disabled = true

func _on_join_confirm() -> void:
	var code := code_input.text.strip_edges().to_upper()
	if code.length() < 4:
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
		GlobalData.is_single_player = false
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
	_show_panel(Mode.MULTI_MENU)

# ── POLLING HANDLER ───────────────────────────────────────────────────────────

func _on_room_updated(data: Dictionary) -> void:
	var status: String = data.get("status", "waiting")
	var players: Dictionary = data.get("players", {})

	if _mode == Mode.CREATE:
		var count := players.size()
		waiting_label.text = "Players connected: %d / 2\nWaiting for another player..." % count if count < 2 else "Players connected: %d / 2\nReady!" % count
		if count >= 2:
			FirebaseClient.stop_polling()
			get_tree().change_scene_to_file("res://scenes/waiting_room.tscn")

	elif _mode == Mode.JOIN:
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
		"is_host":   GlobalData.is_host,
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

func _setup_timeout_select() -> void:
	var vbox = $Content/CreatePanel/VBox
	var label = Label.new()
	label.text = "Match Duration:"
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(label)
	vbox.move_child(label, 2)
	
	_timeout_select = OptionButton.new()
	_timeout_select.add_item("60 Seconds", 0)
	_timeout_select.set_item_metadata(0, 60.0)
	_timeout_select.add_item("90 Seconds", 1)
	_timeout_select.set_item_metadata(1, 90.0)
	_timeout_select.add_item("120 Seconds", 2)
	_timeout_select.set_item_metadata(2, 120.0)
	_timeout_select.selected = 1
	
	vbox.add_child(_timeout_select)
	vbox.move_child(_timeout_select, 3)
	
	# Also add to single player panel
	var sp_vbox = $Content/SinglePanel/VBox
	var sp_label = label.duplicate()
	sp_vbox.add_child(sp_label)
	sp_vbox.move_child(sp_label, 2)
	
	var sp_select = _timeout_select.duplicate()
	sp_vbox.add_child(sp_select)
	sp_vbox.move_child(sp_select, 3)
	
	sp_select.item_selected.connect(func(idx): _timeout_select.selected = idx)
	_timeout_select.item_selected.connect(func(idx): sp_select.selected = idx)
