extends Node

# ── Player identity ──────────────────────────────────────────────────────────
var player_name: String = "Player"
var selected_character: String = "Ninja Frog"
var player_id: String = ""        # Random UUID assigned on first launch

# ── Room state ───────────────────────────────────────────────────────────────
var room_code: String = ""
var is_host: bool = false

# ── Other player snapshot (updated by FirebaseClient polling) ─────────────────
var other_player: Dictionary = {}

func _ready() -> void:
	player_id = _generate_id()

func _generate_id() -> String:
	var base = "abcdefghijklmnopqrstuvwxyz0123456789"
	var result = ""
	for i in 12:
		result += base[randi() % base.length()]
	return result
