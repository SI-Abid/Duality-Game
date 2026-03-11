extends Node2D
## RemotePlayer: visual ghost of the other player, driven by Firebase state.
## No physics - just lerps toward the last known position.

const LERP_SPEED = 15.0

var target_pos: Vector2 = Vector2.ZERO
var target_vel: Vector2 = Vector2.ZERO
var target_anim: String = "idle"
var target_flip: bool = false
var _initialized: bool = false

@onready var sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var name_label: Label = $NameLabel

func _ready() -> void:
	set_process(false)

func init(char_name: String, pname: String) -> void:
	name_label.text = pname
	_load_sprites(char_name)
	target_pos = global_position
	_initialized = true
	set_process(true)
	sprite.play("idle")

func apply_state(data: Dictionary) -> void:
	target_pos.x = float(data.get("pos_x", target_pos.x))
	target_pos.y = float(data.get("pos_y", target_pos.y))
	target_vel.x = float(data.get("vel_x", 0.0))
	target_vel.y = float(data.get("vel_y", 0.0))
	target_anim = str(data.get("anim", "idle"))
	target_flip = bool(data.get("flip", false))

func _process(delta: float) -> void:
	if not _initialized:
		return
	
	# Basic prediction - move target forward by its velocity
	# This helps counteract the small network delay
	var predicted_target = target_pos + (target_vel * delta)
	
	# Smooth interpolation toward predicted position
	global_position = global_position.lerp(predicted_target, LERP_SPEED * delta)
	
	# Sync animation
	if sprite.sprite_frames != null:
		var anim = str(target_anim)
		if sprite.sprite_frames.has_animation(anim) and sprite.animation != anim:
			sprite.play(anim)
	sprite.flip_h = target_flip

func _load_sprites(char_name: String) -> void:
	var anim_map = {
		"idle":      "Idle (32x32).png",
		"run":       "Run (32x32).png",
		"jump":      "Jump (32x32).png",
		"fall":      "Fall (32x32).png",
		"air_jump":  "Double Jump (32x32).png",
		"wall_jump": "Wall Jump (32x32).png",
	}
	var frames = SpriteFrames.new()
	for anim_name in anim_map.keys():
		var tex_path = "res://assets/images/Main Characters/%s/%s" % [char_name, anim_map[anim_name]]
		var tex = load(tex_path)
		if tex == null:
			continue
		frames.add_animation(anim_name)
		frames.set_animation_loop(anim_name, true)
		frames.set_animation_speed(anim_name, 20.0)
		var frame_count = int(tex.get_width() / 32)
		for i in range(frame_count):
			var atlas = AtlasTexture.new()
			atlas.atlas = tex
			atlas.region = Rect2(i * 32, 0, 32, 32)
			frames.add_frame(anim_name, atlas)
	sprite.sprite_frames = frames
