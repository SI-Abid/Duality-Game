extends Node

## NetworkManager — Handles pure LAN Peer-to-Peer synchronization using ENet.
## This replaces WebRTCManager and uses Godot's built in High Level Multiplayer API.

signal peer_connected(id: int)
signal peer_disconnected(id: int)
signal connection_failed
signal connection_succeeded
signal server_disconnected

var peer: ENetMultiplayerPeer
var is_host: bool = false
const DEFAULT_PORT = 8910

func _ready() -> void:
    # Connect standard multiplayer signals
    multiplayer.peer_connected.connect(_on_peer_connected)
    multiplayer.peer_disconnected.connect(_on_peer_disconnected)
    multiplayer.connection_failed.connect(_on_connection_failed)
    multiplayer.connected_to_server.connect(_on_connection_succeeded)
    multiplayer.server_disconnected.connect(_on_server_disconnected)

func setup_host() -> bool:
    is_host = true
    peer = ENetMultiplayerPeer.new()
    var err = peer.create_server(DEFAULT_PORT, 2) # Max 2 players
    if err != OK:
        push_error("[NetworkManager] Failed to create server on port %d: %d" % [DEFAULT_PORT, err])
        return false
    multiplayer.multiplayer_peer = peer
    print("[NetworkManager] Server started on port ", DEFAULT_PORT)
    return true

func setup_client(host_ip: String) -> bool:
    is_host = false
    peer = ENetMultiplayerPeer.new()
    var err = peer.create_client(host_ip, DEFAULT_PORT)
    if err != OK:
        push_error("[NetworkManager] Failed to create client to %s:%d: %d" % [host_ip, DEFAULT_PORT, err])
        return false
    multiplayer.multiplayer_peer = peer
    print("[NetworkManager] Connecting to server at ", host_ip, ":", DEFAULT_PORT)
    return true

func close_connection() -> void:
    if peer != null:
        peer.close()
    multiplayer.multiplayer_peer = null
    peer = null
    is_host = false
    print("[NetworkManager] Connection closed")

func get_local_ip() -> String:
    var ip_addresses = IP.get_local_addresses()
    # Prefer IPv4 address on typical local subnet
    for ip in ip_addresses:
        if ip.begins_with("192.168.") or ip.begins_with("10.") or (ip.begins_with("172.") and float(ip.split(".")[1]) >= 16 and float(ip.split(".")[1]) <= 31):
            return ip
    
    # Fallback to local loopback if no LAN IP found (extremely unlikely)
    for ip in ip_addresses:
        if ip == "127.0.0.1":
            return ip
            
    return "127.0.0.1"

# ─────────────────────────────────────────────────────────────────────────────
# Multiplayer Signals
# ─────────────────────────────────────────────────────────────────────────────

func _on_peer_connected(id: int) -> void:
    print("[NetworkManager] Peer connected: ", id)
    peer_connected.emit(id)

func _on_peer_disconnected(id: int) -> void:
    print("[NetworkManager] Peer disconnected: ", id)
    peer_disconnected.emit(id)

func _on_connection_failed() -> void:
    print("[NetworkManager] Connection failed!")
    connection_failed.emit()

func _on_connection_succeeded() -> void:
    print("[NetworkManager] Connection succeeded!")
    connection_succeeded.emit()

func _on_server_disconnected() -> void:
    print("[NetworkManager] Server disconnected!")
    server_disconnected.emit()
