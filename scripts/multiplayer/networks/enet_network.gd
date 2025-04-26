extends Node

const SERVER_PORT = 8060
const SERVER_IP = " 192.168.2.78"
const SERVER_URL = "ws://192.168.2.78:8060"

var multiplayer_scene = preload("res://TPS.tscn")
var multiplayer_peer: WebSocketMultiplayerPeer = WebSocketMultiplayerPeer.new()
var _players_spawn_node
func _ready() -> void:
	var http := HTTPRequest.new()
	add_child(http)
func become_host():
	print("Starting WebSocket host")

	var err = multiplayer_peer.create_server(SERVER_PORT, "*")
	if err != OK:
		print("WebSocket server failed to start: ", err)
		return

	multiplayer.multiplayer_peer = multiplayer_peer

	multiplayer.peer_connected.connect(_add_player_to_game)
	multiplayer.peer_disconnected.connect(_del_player)

	if not OS.has_feature("dedicated_server"):
		_add_player_to_game(1)

	# Register to Glitch server
	var http = HTTPRequest.new()
	add_child(http)
	var body = {
		"playerId": str(multiplayer.get_unique_id()), # or use a username
		"ip": IP.get_local_addresses()[0] # or IP.get_global_ip()
	}
	http.request(
		"https://wary-scarce-meat.glitch.me/",
		["Content-Type: application/json"],
		HTTPClient.METHOD_POST,
		JSON.stringify(body)
	)

func join_as_client(lobby_id = 0):
	print("Joining WebSocket server...")

	var err = multiplayer_peer.create_client(SERVER_URL)
	if err != OK:
		print("WebSocket client failed: ", err)
		return

	multiplayer.multiplayer_peer = multiplayer_peer

func _add_player_to_game(id: int):
	print("Player %s joined the game!" % id)

	var player_to_add = multiplayer_scene.instantiate()
	player_to_add.player_id = id
	player_to_add.name = str(id)

	_players_spawn_node.add_child(player_to_add, true)

func _del_player(id: int):
	print("Player %s left the game!" % id)
	if not _players_spawn_node.has_node(str(id)):
		return
	_players_spawn_node.get_node(str(id)).queue_free()
