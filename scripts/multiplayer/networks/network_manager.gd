extends Node

enum MULTIPLAYER_NETWORK_TYPE { ENET, STEAM, WEBSOCKET }

@export var _players_spawn_node: Node3D

var active_network_type: MULTIPLAYER_NETWORK_TYPE = MULTIPLAYER_NETWORK_TYPE.ENET
var enet_network_scene := preload("res://scenes/multiplayer/networks/enet_network.tscn")
var steam_network_scene := preload("res://scenes/multiplayer/networks/steam_network.tscn")
var websocket_network_scene := preload("res://scenes/multiplayer/networks/enet_network.tscn")
var active_network

func _build_multiplayer_network():
	if not active_network:
		print("Setting active_network")
		
		MultiplayerManager.multiplayer_mode_enabled = true
		
		match active_network_type:
			MULTIPLAYER_NETWORK_TYPE.ENET:
				print("Setting network type to ENet")
				_set_active_network(enet_network_scene)
			MULTIPLAYER_NETWORK_TYPE.STEAM:
				print("Setting network type to Steam")
				_set_active_network(steam_network_scene)
			MULTIPLAYER_NETWORK_TYPE.WEBSOCKET:
				print("Setting network type to WebSocket")
				_set_active_network(websocket_network_scene)
			_:
				print("No match for network type!")

func _set_active_network(active_network_scene):
	var network_scene_initialized = active_network_scene.instantiate()
	active_network = network_scene_initialized
	active_network._players_spawn_node = _players_spawn_node
	add_child(active_network)

func become_host(is_dedicated_server = false):
	_build_multiplayer_network()
	MultiplayerManager.host_mode_enabled = true if is_dedicated_server == false else false
	active_network.become_host()
	
func join_as_client(lobby_id = 0):
	_build_multiplayer_network()
	active_network.join_as_client(lobby_id)

func _on_lobbies_fetched(result, response_code, headers, body):
	if response_code == 200:
		var data = JSON.parse_string(body.get_string_from_utf8())
		if typeof(data) == TYPE_DICTIONARY:
			for player_id in data:
				print("Lobby found: ", player_id, " IP: ", data[player_id])
		else:
			print("Failed to parse player list")
	else:
		print("Failed to fetch lobbies. Status code: ", response_code)
func list_lobbies():
	print("Fetching available lobbies...")
	var http = HTTPRequest.new()
	add_child(http)
	http.request_completed.connect(_on_lobbies_fetched)
	http.request("https://your-glitch-app.glitch.me/players")
