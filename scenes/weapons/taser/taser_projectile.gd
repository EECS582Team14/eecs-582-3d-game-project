extends Area3D

## Taser Projectile
##
## A small glowing sphere that travels forward and damages players on contact.
## Builds its own mesh and collision shape in _ready() — no .tscn needed.

var speed: float = 40.0
var max_distance: float = 50.0
var damage: int = 25

var _direction: Vector3 = Vector3.FORWARD
var _distance_traveled: float = 0.0
var shooter_steam_id: int = 0
var _start_origin: Vector3 = Vector3.ZERO

func setup(origin: Vector3, direction: Vector3, shooter_id: int) -> void:
	_start_origin = origin
	_direction = direction.normalized()
	shooter_steam_id = shooter_id

func _ready() -> void:
	global_position = _start_origin
	# Orient the node to face the travel direction
	look_at(global_position + _direction, Vector3.UP)
	# Collision shape (capsule aligned to travel direction)
	var col_shape = CollisionShape3D.new()
	var capsule_shape = CapsuleShape3D.new()
	capsule_shape.radius = 0.04
	capsule_shape.height = 0.35
	col_shape.shape = capsule_shape
	col_shape.rotation_degrees.x = 90.0
	add_child(col_shape)

	# --- Star Wars-style laser bolt ---
	# Bright inner core (narrow elongated capsule)
	var core = MeshInstance3D.new()
	var core_mesh = CapsuleMesh.new()
	core_mesh.radius = 0.02
	core_mesh.height = 0.35
	var core_mat = StandardMaterial3D.new()
	core_mat.emission_enabled = true
	core_mat.emission = Color(0.7, 0.95, 1.0)  # white-cyan hot core
	core_mat.emission_energy_multiplier = 6.0
	core_mat.albedo_color = Color(0.9, 1.0, 1.0)
	core_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	core_mat.albedo_color.a = 0.95
	core_mesh.material = core_mat
	core.mesh = core_mesh
	core.rotation_degrees.x = 90.0  # align along forward axis
	add_child(core)

	# Outer glow (larger, semi-transparent capsule)
	var glow = MeshInstance3D.new()
	var glow_mesh = CapsuleMesh.new()
	glow_mesh.radius = 0.045
	glow_mesh.height = 0.4
	var glow_mat = StandardMaterial3D.new()
	glow_mat.emission_enabled = true
	glow_mat.emission = Color(0.1, 0.6, 1.0)  # blue glow
	glow_mat.emission_energy_multiplier = 4.0
	glow_mat.albedo_color = Color(0.1, 0.6, 1.0, 0.35)
	glow_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glow_mat.no_depth_test = true
	glow_mesh.material = glow_mat
	glow.mesh = glow_mesh
	glow.rotation_degrees.x = 90.0
	add_child(glow)

	# Point light for dynamic illumination on surroundings
	var light = OmniLight3D.new()
	light.light_color = Color(0.2, 0.7, 1.0)
	light.light_energy = 2.0
	light.omni_range = 3.0
	light.omni_attenuation = 2.0
	add_child(light)

	# Collision settings — layer 2 (projectile), detect layer 1 (players)
	collision_layer = 2
	collision_mask = 1

	body_entered.connect(_on_body_entered)

func _physics_process(delta: float) -> void:
	var movement = _direction * speed * delta
	global_position += movement
	_distance_traveled += movement.length()
	if _distance_traveled >= max_distance:
		queue_free()

func _on_body_entered(body: Node3D) -> void:
	if body is CharacterBody3D and body.has_method("setup"):
		# It's a player — check it's not the shooter
		if body.steam_id == shooter_steam_id:
			return
		# Send damage to the victim via network
		NetworkManager.send_taser_hit(body.steam_id, damage)
		queue_free()
