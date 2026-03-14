extends Node
## FirebaseClient — REST wrapper for Firebase Realtime Database.
## Uses TWO separate HTTPRequest nodes: one for the request queue (writes)
## and one dedicated to polling (reads), so they never block each other.

signal room_updated(data: Dictionary)
signal request_failed(code: int, error: String)

var DB_URL: String = ""  # Loaded from config.cfg (not committed to version control)

# ── Queue HTTP (for writes / one-off reads) ───────────────────────────────────
var _http_queue: HTTPRequest
var _pending: Array = []
var _queue_busy: bool = false
var _current_callback: Callable

# ── Poll HTTP (dedicated, never blocked by writes) ────────────────────────────
var _http_poll: HTTPRequest
var _poll_timer: Timer
var _poll_room_code: String = ""
var _polling: bool = false
var _poll_busy: bool = false

func _ready() -> void:
	_load_config()
	_http_queue = HTTPRequest.new()
	_http_queue.timeout = 10.0
	add_child(_http_queue)
	_http_queue.request_completed.connect(_on_queue_completed)

	_http_poll = HTTPRequest.new()
	_http_poll.timeout = 10.0
	add_child(_http_poll)
	_http_poll.request_completed.connect(_on_poll_completed)

	_poll_timer = Timer.new()
	_poll_timer.wait_time = 0.25
	_poll_timer.one_shot = false
	_poll_timer.timeout.connect(_do_poll)
	add_child(_poll_timer)

func _load_config() -> void:
	var cfg = ConfigFile.new()
	var err = cfg.load("res://config.cfg")
	if err != OK:
		push_error("[Firebase] config.cfg not found! Copy config.cfg.example to config.cfg and fill in your Firebase DB URL.")
		return
	DB_URL = cfg.get_value("firebase", "db_url", "")
	if DB_URL.is_empty():
		push_error("[Firebase] db_url is empty in config.cfg")

# ─────────────────────────────────────────────────────────────────────────────
# Public API
# ─────────────────────────────────────────────────────────────────────────────

func generate_room_code() -> String:
	var chars = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
	var code = ""
	for i in 6:
		code += chars[randi() % chars.length()]
	return code

func create_room(room_code: String, player_data: Dictionary) -> void:
	var url = "%s/rooms/%s.json" % [DB_URL, room_code]
	var body = JSON.stringify({
		"host_id": GlobalData.player_id,
		"status": "waiting",
		"created_at": Time.get_unix_time_from_system(),
		"players": {
			GlobalData.player_id: player_data
		}
	})
	_enqueue("PUT", url, body, func(ok, _data):
		if ok:
			print("[Firebase] Room created: ", room_code)
		else:
			emit_signal("request_failed", -1, "Failed to create room"))

func join_room(room_code: String, player_data: Dictionary, callback: Callable) -> void:
	var url = "%s/rooms/%s/players/%s.json" % [DB_URL, room_code, GlobalData.player_id]
	var body = JSON.stringify(player_data)
	_enqueue("PUT", url, body, func(ok, data):
		callback.call(ok, data))

func check_room(room_code: String, callback: Callable) -> void:
	var url = "%s/rooms/%s.json" % [DB_URL, room_code]
	_enqueue("GET", url, "", callback)

func update_player_state(room_code: String, player_id: String, data: Dictionary) -> void:
	var url = "%s/rooms/%s/players/%s.json" % [DB_URL, room_code, player_id]
	var body = JSON.stringify(data)
	_enqueue("PATCH", url, body, func(ok, _d):
		if not ok:
			push_warning("[Firebase] update_player_state failed"))

func set_room_field(room_code: String, data: Dictionary) -> void:
	var url = "%s/rooms/%s.json" % [DB_URL, room_code]
	var body = JSON.stringify(data)
	_enqueue("PATCH", url, body, func(ok, _d):
		if not ok:
			push_warning("[Firebase] set_room_field failed"))



func get_room(room_code: String, callback: Callable) -> void:
	var url = "%s/rooms/%s.json" % [DB_URL, room_code]
	_enqueue("GET", url, "", callback)

func delete_room(room_code: String) -> void:
	var url = "%s/rooms/%s.json" % [DB_URL, room_code]
	_enqueue("DELETE", url, "", func(_ok, _d):
		print("[Firebase] Room deleted"))

func start_polling(room_code: String) -> void:
	_poll_room_code = room_code
	_polling = true
	_poll_timer.start()
	print("[Firebase] Polling started for room: ", room_code)

func stop_polling() -> void:
	_polling = false
	_poll_timer.stop()
	_poll_room_code = ""

# ─────────────────────────────────────────────────────────────────────────────
# Internal — Request Queue (writes)
# ─────────────────────────────────────────────────────────────────────────────

func _enqueue(method: String, url: String, body: String, callback: Callable) -> void:
	_pending.append({"method": method, "url": url, "body": body, "callback": callback})
	_flush()

func _flush() -> void:
	if _queue_busy or _pending.is_empty():
		return
	_queue_busy = true
	var req = _pending[0]
	_pending.remove_at(0)
	var methods = {
		"GET": HTTPClient.METHOD_GET,
		"PUT": HTTPClient.METHOD_PUT,
		"PATCH": HTTPClient.METHOD_PATCH,
		"DELETE": HTTPClient.METHOD_DELETE
	}
	var http_method = methods.get(req["method"], HTTPClient.METHOD_GET)
	var headers: PackedStringArray = ["Content-Type: application/json"]
	var body_str = str(req.get("body", ""))
	_current_callback = req["callback"]
	if body_str.is_empty():
		_http_queue.request(req["url"], headers, http_method)
	else:
		_http_queue.request(req["url"], headers, http_method, body_str)

func _on_queue_completed(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	_queue_busy = false
	var text = body.get_string_from_utf8()
	var ok = (result == HTTPRequest.RESULT_SUCCESS and response_code >= 200 and response_code < 300)
	var data = null
	if not text.is_empty() and text != "null":
		data = JSON.parse_string(text)
	if _current_callback.is_valid():
		_current_callback.call(ok, data)
	_flush()

# ─────────────────────────────────────────────────────────────────────────────
# Internal — Polling (dedicated HTTP node, never blocked by writes)
# ─────────────────────────────────────────────────────────────────────────────

func _do_poll() -> void:
	if not _polling or _poll_room_code.is_empty():
		return
	if _poll_busy:
		return
	_poll_busy = true
	var url = "%s/rooms/%s.json" % [DB_URL, _poll_room_code]
	var headers: PackedStringArray = ["Content-Type: application/json"]
	_http_poll.request(url, headers, HTTPClient.METHOD_GET)

func _on_poll_completed(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	_poll_busy = false
	var text = body.get_string_from_utf8()
	var ok = (result == HTTPRequest.RESULT_SUCCESS and response_code >= 200 and response_code < 300)
	if ok and not text.is_empty() and text != "null":
		var parsed = JSON.parse_string(text)
		if parsed is Dictionary:
			emit_signal("room_updated", parsed)
