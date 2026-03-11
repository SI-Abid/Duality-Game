extends Control

const CHARACTERS = ["Mask Dude", "Ninja Frog", "Pink Man", "Virtual Guy"]
const CHARACTER_COLORS = [
	Color(0.3, 0.6, 1.0),   # Mask Dude - blue
	Color(0.2, 0.8, 0.4),   # Ninja Frog - green
	Color(1.0, 0.4, 0.6),   # Pink Man - pink
	Color(0.6, 0.4, 1.0),   # Virtual Guy - purple
]

var selected_index: int = 1  # Default: Ninja Frog
var _frames: Array = []
var _frame_index: int = 0
var _anim_timer: float = 0.0
const FRAME_DURATION: float = 0.06

@onready var name_input: LineEdit = $VBoxContainer/NameSection/NameInput
@onready var char_label: Label = $VBoxContainer/CharacterName
@onready var char_preview: TextureRect = $VBoxContainer/CharacterSection/PreviewBox/CharacterPreview
@onready var next_button: Button = $VBoxContainer/NextButton
@onready var left_btn: Button = $VBoxContainer/CharacterSection/LeftButton
@onready var right_btn: Button = $VBoxContainer/CharacterSection/RightButton
@onready var preview_box: Panel = $VBoxContainer/CharacterSection/PreviewBox

func _ready() -> void:
	_update_character_display()
	next_button.pressed.connect(_on_next_pressed)
	left_btn.pressed.connect(_on_left_pressed)
	right_btn.pressed.connect(_on_right_pressed)
	name_input.text_changed.connect(_on_name_changed)

func _process(delta: float) -> void:
	if _frames.is_empty():
		return
	_anim_timer += delta
	if _anim_timer >= FRAME_DURATION:
		_anim_timer = 0.0
		_frame_index = (_frame_index + 1) % _frames.size()
		char_preview.texture = _frames[_frame_index]

func _on_left_pressed() -> void:
	selected_index = (selected_index - 1 + CHARACTERS.size()) % CHARACTERS.size()
	_update_character_display()

func _on_right_pressed() -> void:
	selected_index = (selected_index + 1) % CHARACTERS.size()
	_update_character_display()

func _update_character_display() -> void:
	var char_name = CHARACTERS[selected_index]
	char_label.text = char_name

	var tex_path = "res://assets/images/Main Characters/%s/Idle (32x32).png" % char_name
	var texture = load(tex_path)
	if texture == null:
		return

	_frames.clear()
	_frame_index = 0
	_anim_timer = 0.0
	var frame_count = texture.get_width() / 32
	for i in frame_count:
		var atlas = AtlasTexture.new()
		atlas.atlas = texture
		atlas.region = Rect2(i * 32, 0, 32, 32)
		_frames.append(atlas)
	if not _frames.is_empty():
		char_preview.texture = _frames[0]

	var col = CHARACTER_COLORS[selected_index]
	preview_box.self_modulate = col.lightened(0.3)

func _on_name_changed(text: String) -> void:
	next_button.disabled = text.strip_edges().is_empty()

func _on_next_pressed() -> void:
	var entered_name = name_input.text.strip_edges()
	if entered_name.is_empty():
		return
	GlobalData.player_name = entered_name
	GlobalData.selected_character = CHARACTERS[selected_index]
	get_tree().change_scene_to_file("res://scenes/lobby.tscn")
