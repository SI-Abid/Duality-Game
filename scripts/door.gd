extends StaticBody2D  # Or use StaticBody2D / AnimatedSprite2D depending on your door

@onready var zone: Area2D = %Trigger
@onready var boxes: Node = %Boxes
var is_open = false

func _ready():
	zone.connect("occupancy_changed", Callable(self, "_on_trigger_zone_changed"))
	_check_all_zones()

func _on_trigger_zone_changed():
	_check_all_zones()

func _check_all_zones():
	if zone.box_count == boxes.get_child_count() and not is_open:
		_open_door()
		is_open = true
	elif is_open:
		_close_door()
		is_open = false

func _open_door():
	print("✅ Door opened!")
	$AnimationPlayer.play("open")

func _close_door():
	print("❌ Door closed!")
	$AnimationPlayer.play_backwards("open")
