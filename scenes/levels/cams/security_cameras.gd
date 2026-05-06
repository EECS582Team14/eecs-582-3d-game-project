extends Node3D

## Security Camera System
##
## Spawns cameras at key locations around the ship and displays their feeds
## on monitor screens inside the Cams room. Players can walk in and see
## live views of different areas.

# Camera locations: name -> { position, rotation_y (degrees), deck }
const CAMERA_LOCATIONS = {
	"Nexus": {"pos": Vector3(0, 2.2, 0), "rot": -90.0, "deck": "upper"},
	"Nav Bridge": {"pos": Vector3(0, 2.2, -20), "rot": 180.0, "deck": "upper"},
	"Reactor Upper": {"pos": Vector3(0, 2.2, 38), "rot": 0.0, "deck": "upper"},
	"Armory": {"pos": Vector3(-18, 2.2, 18), "rot": 0.0, "deck": "upper"},
	"Electrical": {"pos": Vector3(15, 2.2, 20), "rot": 180.0, "deck": "lower"},
	"Fab Lab": {"pos": Vector3(2, 2.2, -17), "rot": 0.0, "deck": "lower"},
}

# Monitor layout in Cams room
const MONITOR_SIZE = Vector2(1.8, 1.2)
const MONITOR_SPACING = 0.3
const VIEWPORT_SIZE = Vector2i(240, 180)  # was 320x240, dropped for perf

# Cams room world-space center, used to gate viewport rendering by distance.
# Players outside this range get UPDATE_DISABLED on every camera viewport,
# which removes 6 full-scene renders per frame.
const CAMS_ROOM_CENTER: Vector3 = Vector3(11.0, 0.0, -18.0)
const CAMS_ROOM_ACTIVE_DISTANCE: float = 14.0  # meters from cams room center
const CAMS_ROOM_ACTIVE_DISTANCE_SQ: float = CAMS_ROOM_ACTIVE_DISTANCE * CAMS_ROOM_ACTIVE_DISTANCE
const CAMS_DISTANCE_CHECK_INTERVAL: float = 0.5

var _cameras: Dictionary = {}  # name -> Camera3D
var _viewports: Dictionary = {}  # name -> SubViewport
var _monitors: Dictionary = {}  # name -> MeshInstance3D
var _cameras_active: bool = false
var _distance_check_timer: float = 0.0

func _ready() -> void:
	# Wait for the scene tree to be fully loaded
	await get_tree().process_frame
	await get_tree().process_frame
	_setup_cameras()
	_setup_monitors()

func _process(delta: float) -> void:
	# Cheap proximity check — runs at 2 Hz, just compares squared distance.
	_distance_check_timer += delta
	if _distance_check_timer < CAMS_DISTANCE_CHECK_INTERVAL:
		return
	_distance_check_timer = 0.0
	_update_camera_activation()

func _update_camera_activation() -> void:
	# Find the local player's position. If we can't, leave cameras off.
	var local_id := Steam.getSteamID()
	var local_player = NetworkManager.get_player(local_id)
	if not local_player or not is_instance_valid(local_player):
		_set_cameras_active(false)
		return
	var dist_sq: float = local_player.global_position.distance_squared_to(CAMS_ROOM_CENTER)
	_set_cameras_active(dist_sq <= CAMS_ROOM_ACTIVE_DISTANCE_SQ)

func _set_cameras_active(active: bool) -> void:
	if active == _cameras_active:
		return
	_cameras_active = active
	var mode = SubViewport.UPDATE_ALWAYS if active else SubViewport.UPDATE_DISABLED
	for cam_name in _viewports:
		var vp: SubViewport = _viewports[cam_name]
		if vp and is_instance_valid(vp):
			vp.render_target_update_mode = mode

func _setup_cameras() -> void:
	var scene_root = get_tree().current_scene
	var upper_deck = scene_root.get_node_or_null("UpperDeck")
	var lower_deck = scene_root.get_node_or_null("LowerDeck")

	for cam_name in CAMERA_LOCATIONS:
		var info = CAMERA_LOCATIONS[cam_name]

		# Create SubViewport for this camera
		# It must share the main scene's World3D to see the same geometry
		var viewport = SubViewport.new()
		viewport.name = "CamViewport_" + cam_name.replace(" ", "_")
		viewport.size = VIEWPORT_SIZE
		# Default to DISABLED; the distance-gated _process below flips this
		# to ALWAYS only when a player is near the cams room. UPDATE_WHEN_VISIBLE
		# is unreliable with 3D-mesh-attached viewport textures and was leaving
		# the cameras rendering full scenes (6×) every frame regardless.
		viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
		viewport.own_world_3d = false
		# Manually assign the world so the camera sees the game level
		viewport.world_3d = get_viewport().world_3d
		add_child(viewport)
		_viewports[cam_name] = viewport

		# Create Camera3D inside the viewport
		var cam = Camera3D.new()
		cam.name = "SecurityCam_" + cam_name.replace(" ", "_")
		cam.fov = 75.0
		cam.position = info["pos"]
		cam.rotation_degrees.y = info["rot"]
		# Tilt slightly downward
		cam.rotation_degrees.x = -15.0
		viewport.add_child(cam)
		_cameras[cam_name] = cam

func _setup_monitors() -> void:
	# Find the Cams room node
	var scene_root = get_tree().current_scene
	var cams_room = scene_root.get_node_or_null("UpperDeck/Cams")
	if not cams_room:
		print("SecurityCameras: Cams room not found")
		return

	# Cams room is at world (10, 0, -20)
	# Door is at local (-0.3, 0, 5) — player enters from south heading -Z
	# Light is at local (1, 2.3, 2) — room center is roughly (1, 0, 2)
	# Place monitors facing the entrance (+Z), near the back of the room
	# Layout: top 3 on back wall (Z=0.5, facing +Z toward door)
	#         bottom 3 on door-side wall (Z=4.0, facing -Z toward back wall)
	# Player stands in the middle and can see both walls
	var cols = 3
	var total_width = cols * MONITOR_SIZE.x + (cols - 1) * MONITOR_SPACING
	var center_x = 1.0
	var start_x = center_x - total_width / 2.0
	var cam_names = CAMERA_LOCATIONS.keys()

	for i in range(cam_names.size()):
		var cam_name = cam_names[i]
		var col = i % cols
		var is_back_wall = i < 3  # first 3 on back wall, last 3 on door wall

		var x = start_x + col * (MONITOR_SIZE.x + MONITOR_SPACING) + MONITOR_SIZE.x / 2.0
		var y = 1.6  # single row height on each wall

		var z: float
		var rot_y: float
		if is_back_wall:
			z = 0.5      # back wall
			rot_y = 0.0   # facing +Z (toward door)
		else:
			z = 4.0       # door-side wall
			rot_y = 180.0  # facing -Z (toward back wall)

		# Create monitor screen
		var monitor = MeshInstance3D.new()
		monitor.name = "Monitor_" + cam_name.replace(" ", "_")
		var quad = QuadMesh.new()
		quad.size = MONITOR_SIZE
		monitor.mesh = quad
		monitor.position = Vector3(x, y, z)
		monitor.rotation_degrees.y = rot_y

		# Unshaded material so the image isn't affected by room lighting
		var mat = StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.albedo_texture = _viewports[cam_name].get_texture()
		monitor.material_override = mat

		cams_room.add_child(monitor)
		_monitors[cam_name] = monitor

		# Label below monitor
		var label = Label3D.new()
		label.text = cam_name
		label.font_size = 48
		label.pixel_size = 0.005
		label.position = Vector3(x, y - MONITOR_SIZE.y / 2.0 - 0.1, z + (0.01 if is_back_wall else -0.01))
		label.rotation_degrees.y = rot_y
		label.billboard = BaseMaterial3D.BILLBOARD_DISABLED
		label.modulate = Color(0.0, 0.9, 0.0, 1.0)
		cams_room.add_child(label)

	# Dark frame behind each monitor
	for cam_name in _monitors:
		var mon = _monitors[cam_name]
		var frame = MeshInstance3D.new()
		var frame_quad = QuadMesh.new()
		frame_quad.size = MONITOR_SIZE + Vector2(0.15, 0.15)
		frame.mesh = frame_quad
		frame.position = mon.position
		frame.rotation_degrees.y = mon.rotation_degrees.y
		# Offset slightly behind the monitor
		var behind = Vector3(0, 0, -0.005) if mon.rotation_degrees.y == 0.0 else Vector3(0, 0, 0.005)
		frame.position += behind
		var frame_mat = StandardMaterial3D.new()
		frame_mat.albedo_color = Color(0.08, 0.08, 0.08, 1.0)
		frame.material_override = frame_mat
		cams_room.add_child(frame)
