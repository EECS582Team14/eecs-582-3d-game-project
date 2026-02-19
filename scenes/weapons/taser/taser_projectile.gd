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
	# Collision shape
	var col_shape = CollisionShape3D.new()
	var sphere_shape = SphereShape3D.new()
	sphere_shape.radius = 0.05
	col_shape.shape = sphere_shape
	add_child(col_shape)

	# Mesh
	var mesh_inst = MeshInstance3D.new()
	var sphere_mesh = SphereMesh.new()
	sphere_mesh.radius = 0.05
	sphere_mesh.height = 0.1
	var mat = StandardMaterial3D.new()
	mat.emission_enabled = true
	mat.emission = Color(0.2, 0.9, 1.0)  # bright cyan
	mat.emission_energy_multiplier = 3.0
	mat.albedo_color = Color(0.2, 0.9, 1.0)
	sphere_mesh.material = mat
	mesh_inst.mesh = sphere_mesh
	add_child(mesh_inst)

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
		# Deal damage
		if "current_health" in body:
			body.current_health -= damage
			if body.current_health < 0:
				body.current_health = 0
			# Update health bar if the hit player is local
			if body.is_local_player:
				if body.health_bar:
					body.health_bar.value = body.current_health
				body.health_changed.emit(body.current_health)
				NetworkManager.send_health_update(body.current_health)
		queue_free()
