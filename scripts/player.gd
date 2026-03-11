extends CharacterBody2D

const SPEED = 300.0
const JUMP_VELOCITY = -400.0
const MAX_AIR_JUMPS = 3
@onready var sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var push_zone = $PushZone

# Constants for respawning (matches level.gd)
const SPAWN1_POS = Vector2(0, 0)
const SPAWN2_POS = Vector2(-50, 0)

var air_jumps_left = MAX_AIR_JUMPS

func _ready() -> void:
	# Apply character selection from lobby
	var char_name = GlobalData.selected_character
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
		var frame_count = tex.get_width() / 32
		for i in frame_count:
			var atlas = AtlasTexture.new()
			atlas.atlas = tex
			atlas.region = Rect2(i * 32, 0, 32, 32)
			frames.add_frame(anim_name, atlas)
	sprite.sprite_frames = frames
	sprite.play("idle")

	# Show player name above character
	var name_label = Label.new()
	name_label.text = GlobalData.player_name
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.position = Vector2(-40, -30)
	name_label.custom_minimum_size = Vector2(80, 20)
	name_label.add_theme_font_size_override("font_size", 10)
	add_child(name_label)

func _process(_delta: float) -> void:
	if position.y > 500:
		# In multiplayer, don't reload scene! Just respawn or teleport back
		global_position = SPAWN1_POS if GlobalData.is_host else SPAWN2_POS
		velocity = Vector2.ZERO
	

func _physics_process(delta: float) -> void:
	# Reset air jump when grounded
	if is_on_floor():
		air_jumps_left = MAX_AIR_JUMPS
		
	# Add the gravity.
	if not is_on_floor():
		velocity += get_gravity() * delta

	# Handle jump.
	if Input.is_action_just_pressed("jump"):
		if is_on_floor():
			velocity.y = JUMP_VELOCITY
			sprite.animation = "jump"
		elif air_jumps_left > 0:
			air_jumps_left -= 1
			velocity.y = JUMP_VELOCITY
			sprite.animation = "air_jump"

	# Get the input direction and handle the movement/deceleration.
	# As good practice, you should replace UI actions with custom gameplay actions.
	var direction := Input.get_axis("move_left", "move_right")
	
	# Flip sprite based on direction
	if direction != 0:
		sprite.flip_h = direction < 0
		if sprite.animation != "air_jump" or is_on_floor(): 
			sprite.animation = "run"

	if is_on_floor() and direction == 0:
			sprite.animation = "idle"
	
	if direction:
		velocity.x = direction * SPEED
	else:
		velocity.x = move_toward(velocity.x, 0, SPEED)
		
	move_and_slide()

	# Push box manually if inside PushZone
	for body in push_zone.get_overlapping_bodies():
		if body is RigidBody2D:
			var impulse = Vector2.ZERO
			# Check if box is above player
			if body.global_position.y + body.shape_owner_get_shape(0, 0).get_rect().size.y / 2 < global_position.y:
				# Apply upward impulse
				impulse = Vector2(0, -50)  # tweak force
			else:
				# Apply regular horizontal push
				impulse = Vector2(direction * 50, 0)
				
			var level = get_parent()
			if level and level.has_method("guest_push_box"):
				level.guest_push_box(str(body.get_path()), impulse)
			else:
				body.apply_central_impulse(impulse)
