extends Area2D

var box_count := 0

signal occupancy_changed

func _ready():
	connect("body_entered", Callable(self, "_on_body_entered"))
	connect("body_exited", Callable(self, "_on_body_exited"))

func _on_body_entered(body):
	if body is RigidBody2D:
		box_count += 1
		emit_signal("occupancy_changed")

func _on_body_exited(body):
	if body is RigidBody2D:
		box_count -= 1
		emit_signal("occupancy_changed")
