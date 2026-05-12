extends CharacterBody3D

# AI Impostor Bot. Host-authoritative: host runs the AI in _physics_process and
# broadcasts position to clients, who interpolate. Duck-typed to look enough
# like a player_controller node that GameManager.players_container iteration,
# win-condition checks, and the taser projectile's "is this a player" test all
# work without changes elsewhere.

const BOT_STEAM_ID: int = 1  # sentinel — not a valid Steam ID
const _PROJECTILE_SCRIPT = preload("res://scenes/weapons/taser/taser_projectile.gd")
const _TASER_MODEL_SCENE: PackedScene = preload("res://scenes/weapons/taser/gun_model.glb")
# Rifle (taser-holding) animations. Same FBX files the player uses so we
# share the static animation cache across both classes.
const _RIFLE_IDLE_SCENE: PackedScene = preload("res://scenes/player/Rifle Aiming Idle.fbx")
const _SHOOT_RIFLE_SCENE: PackedScene = preload("res://scenes/player/Shoot Rifle.fbx")
const _RIFLE_WALK_BACK_SCENE: PackedScene = preload("res://scenes/player/Backwards Rifle Walk.fbx")
const _RIFLE_STRAFE_SCENE: PackedScene = preload("res://scenes/player/Strafe.fbx")
const _RIFLE_STRAFE_MIRROR_SCENE: PackedScene = preload("res://scenes/player/Strafe_mirror.fbx")
const _ANIM_BLEND: float = 0.2
const _MOVE_ANIM_THRESHOLD: float = 0.5  # m/s — below this the bot's "idle"

# Per-class cache: extracting an animation from an FBX is expensive, so we keep
# the parsed Animation resources around and share them across bot instances.
static var _bot_anim_cache: Dictionary = {}

# --- Duck-typed player fields the rest of the codebase reads ---
var steam_id: int = BOT_STEAM_ID
var is_local_player: bool = false
var is_impostor: bool = true
var is_dead: bool = false
var current_health: int = 100
var max_health: int = 100

# --- Networked target state (clients lerp toward) ---
var _target_position: Vector3 = Vector3.ZERO
var _target_rotation_y: float = 0.0

# --- Host AI tuning ---
@export var move_speed: float = 3.2
@export var taser_range: float = 13.0
@export var taser_cooldown: float = 2.0
@export var sight_range: float = 30.0
@export var taser_damage: int = 25

var _taser_timer: float = 0.0
var _state_send_timer: float = 0.0
var _stuck_timer: float = 0.0
var _last_position: Vector3 = Vector3.ZERO
var _retarget_timer: float = 0.0
var _current_target: Node3D = null

const STATE_SEND_RATE: float = 0.066  # ~15 Hz
const RETARGET_INTERVAL: float = 0.5
const STUCK_TIMEOUT: float = 0.7
const JUMP_VEL: float = 5.0
# Grace period at round start — bot stands around for a bit before hunting,
# giving humans time to orient and pick up weapons.
const INITIAL_FIRING_DELAY: float = 10.0
# How often to push the current target's position to the nav agent. The agent
# re-paths internally; we don't need to thrash it every frame.
const NAV_REPATH_INTERVAL: float = 0.4

var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")

# Provided so the taser projectile's `has_method("setup")` player-check passes.
func setup(player_steam_id: int, local: bool) -> void:
	steam_id = player_steam_id
	is_local_player = local
	name = "AIBot_" + str(steam_id)

func reset_round_state() -> void:
	is_dead = false
	current_health = max_health
	_taser_timer = INITIAL_FIRING_DELAY
	visible = true
	$CollisionShape3D.disabled = false

var _anim_player: AnimationPlayer = null
var _anim_lib_prefix: String = ""
var _anim_state: String = ""
var _prev_anim_pos: Vector3 = Vector3.ZERO
var _nav_agent: NavigationAgent3D = null
var _nav_repath_timer: float = 0.0

func _ready() -> void:
	_target_position = global_position
	_target_rotation_y = rotation.y
	_last_position = global_position
	collision_layer = 1
	collision_mask = 1
	_taser_timer = INITIAL_FIRING_DELAY
	_nav_agent = get_node_or_null("NavigationAgent3D")
	NetworkManager.bot_state_received.connect(_on_bot_state_received)
	NetworkManager.bot_died_received.connect(_on_bot_died_received)
	NetworkManager.bot_taser_shot_received.connect(_on_bot_taser_shot_received)
	_start_walk_loop()
	# Defer bone attach until skeleton has a frame to settle. Without this the
	# BoneAttachment3D's transform can be wrong on the very first frame.
	call_deferred("_attach_taser_to_hand")

func _find_animation_player(node: Node) -> AnimationPlayer:
	if node is AnimationPlayer:
		return node
	for child in node.get_children():
		var found := _find_animation_player(child)
		if found:
			return found
	return null

func _find_skeleton(node: Node) -> Skeleton3D:
	if node is Skeleton3D:
		return node
	for c in node.get_children():
		var s := _find_skeleton(c)
		if s:
			return s
	return null

func _attach_taser_to_hand() -> void:
	var model := get_node_or_null("PlayerModel")
	if model == null:
		return
	var skel := _find_skeleton(model)
	if skel == null:
		return
	# Match the bone-name search the baton uses so we stay consistent across
	# Mixamo / non-Mixamo skeletons.
	var bone_idx := -1
	for bone_name in ["mixamorig_RightHand", "mixamorig:RightHand", "RightHand", "mixamorig_RightHandIndex1"]:
		bone_idx = skel.find_bone(bone_name)
		if bone_idx != -1:
			break
	if bone_idx == -1:
		return
	var attach := BoneAttachment3D.new()
	attach.name = "TaserHandAttach"
	attach.bone_idx = bone_idx
	skel.add_child(attach)
	var taser := _TASER_MODEL_SCENE.instantiate()
	# Bone lives under PlayerModel (scale 65) under bot root (scale 1.1), so we
	# divide the visible taser scale through to compensate — same trick used
	# for the baton.
	taser.scale = Vector3(0.008, 0.008, 0.008)
	# Gun model is authored with barrel along its local +Z. The Mixamo right
	# hand bone has its grip direction along local +Y, so we rotate +90° around
	# X to swap +Z → +Y (barrel along grip). Roll of -90° around Y orients
	# the gun's "up" out of the back of the hand so the trigger faces correctly.
	# If still wrong: try (90,0,0), (-90,0,0), (90,90,0), (90,-90,0).
	taser.rotation_degrees = Vector3(-90, 90, 180)
	# Small forward offset along the bone's grip direction (+Y for Mixamo right
	# hand). Value is in bone-local units before the PlayerModel/root scale,
	# so 0.002 ≈ 14cm in world space.
	taser.position = Vector3(0, 0.002, 0)
	attach.add_child(taser)

func _start_walk_loop() -> void:
	var model := get_node_or_null("PlayerModel")
	if model == null:
		return
	_anim_player = _find_animation_player(model)
	if _anim_player == null:
		return
	# Resolve the library prefix the imported FBX uses (e.g., "mixamo_com/").
	var lib_names: Array = _anim_player.get_animation_library_list()
	var main_lib_name: String = ""
	if lib_names.size() > 0:
		main_lib_name = str(lib_names[0])
		if main_lib_name != "":
			_anim_lib_prefix = main_lib_name + "/"
	# Duplicate the shared library so we can add rifle animations without
	# affecting other bots / players using the same FBX.
	var shared_lib: AnimationLibrary = _anim_player.get_animation_library(main_lib_name)
	if shared_lib:
		var main_lib: AnimationLibrary = shared_lib.duplicate()
		_anim_player.remove_animation_library(main_lib_name)
		_anim_player.add_animation_library(main_lib_name, main_lib)
	# Import the full rifle-stance suite: idle, forward, back, strafe L/R.
	_import_animation(_RIFLE_IDLE_SCENE, "rifle_idle", true)
	_import_animation(_SHOOT_RIFLE_SCENE, "shoot_rifle", true)
	_import_animation(_RIFLE_WALK_BACK_SCENE, "rifle_walk_back", true)
	_import_animation(_RIFLE_STRAFE_SCENE, "rifle_strafe", true)
	_import_animation(_RIFLE_STRAFE_MIRROR_SCENE, "rifle_strafe_mirror", true)
	_prev_anim_pos = global_position
	# Start in the idle pose so the bot doesn't T-pose during the firing delay.
	_play_anim_state("rifle_idle", 1.0)

func _anim_name(short: String) -> String:
	return _anim_lib_prefix + short

func _play_anim_state(state: String, speed: float) -> void:
	if _anim_state == state:
		return
	if _anim_player == null:
		return
	var full := _anim_name(state)
	if not _anim_player.has_animation(full):
		return
	_anim_state = state
	_anim_player.play(full, _ANIM_BLEND)
	_anim_player.speed_scale = speed

# Pull a single animation out of an FBX scene and register it in the bot's
# library under `anim_name`. Mirrors player_controller._import_animation but
# uses our own static cache so we don't touch the player's.
func _import_animation(scene: PackedScene, anim_name: String, strip_root_position: bool = false) -> void:
	var lib_names: Array = _anim_player.get_animation_library_list()
	if lib_names.size() == 0:
		return
	var lib: AnimationLibrary = _anim_player.get_animation_library(lib_names[0])
	if lib == null or lib.has_animation(anim_name):
		return
	if _bot_anim_cache.has(anim_name):
		lib.add_animation(anim_name, _bot_anim_cache[anim_name])
		return
	var temp: Node = scene.instantiate()
	for child in temp.get_children():
		if child is AnimationPlayer:
			var ap: AnimationPlayer = child
			var src_libs: Array = ap.get_animation_library_list()
			for src_lib_name in src_libs:
				var src_lib: AnimationLibrary = ap.get_animation_library(src_lib_name)
				if src_lib == null:
					continue
				var anim_list: PackedStringArray = src_lib.get_animation_list()
				if anim_list.size() == 0:
					continue
				var anim: Animation = src_lib.get_animation(anim_list[0])
				if anim == null:
					continue
				if strip_root_position:
					for i in range(anim.get_track_count() - 1, -1, -1):
						var path: String = str(anim.track_get_path(i))
						if "Hips" in path and anim.track_get_type(i) == Animation.TYPE_POSITION_3D:
							anim.remove_track(i)
				anim.loop_mode = Animation.LOOP_LINEAR
				_bot_anim_cache[anim_name] = anim
				lib.add_animation(anim_name, anim)
				break
			break
	temp.queue_free()

# Pick rifle_idle vs shoot_rifle based on how much the bot has actually moved
# this frame. Works the same on host (where movement comes from physics) and
# clients (where it comes from lerp toward the host's broadcast position),
# since both produce real position deltas.
func _update_animation(delta: float) -> void:
	if _anim_player == null or delta <= 0.0:
		return
	if is_dead:
		return
	var step: Vector3 = global_position - _prev_anim_pos
	_prev_anim_pos = global_position
	step.y = 0.0
	var speed: float = step.length() / delta
	if speed <= _MOVE_ANIM_THRESHOLD:
		_play_anim_state("rifle_idle", 1.0)
		return
	# Decompose movement relative to the bot's facing direction (-Z is forward
	# in Godot conventions, matching the player).
	var move_dir: Vector3 = step / step.length()
	var forward: Vector3 = -transform.basis.z
	var right: Vector3 = transform.basis.x
	var fwd_dot: float = forward.dot(move_dir)
	var side_dot: float = right.dot(move_dir)
	# Mirrors player_controller's classification: any meaningful sideways
	# component → strafe; otherwise forward / backward.
	if absf(side_dot) > 0.3:
		if side_dot < 0:
			_play_anim_state("rifle_strafe_mirror", 1.0)
		else:
			_play_anim_state("rifle_strafe", 1.0)
	elif fwd_dot < -0.1:
		_play_anim_state("rifle_walk_back", 1.5)
	else:
		_play_anim_state("shoot_rifle", 1.5)

func _on_bot_state_received(bot_id: int, position: Vector3, rotation_y: float) -> void:
	if bot_id != steam_id:
		return
	if LobbyManager.is_host():
		return  # host is authoritative; ignore echoes
	_target_position = position
	_target_rotation_y = rotation_y

func _on_bot_died_received(bot_id: int) -> void:
	if bot_id != steam_id:
		return
	if is_dead:
		return
	is_dead = true
	visible = false
	$CollisionShape3D.disabled = true

func _physics_process(delta: float) -> void:
	if is_dead:
		return
	if LobbyManager.is_host():
		_host_tick(delta)
	else:
		_remote_tick(delta)
	_update_animation(delta)

func _remote_tick(delta: float) -> void:
	var t: float = clamp(delta * 15.0, 0.0, 1.0)
	global_position = global_position.lerp(_target_position, t)
	rotation.y = lerp_angle(rotation.y, _target_rotation_y, clamp(delta * 12.0, 0.0, 1.0))

func _host_tick(delta: float) -> void:
	_taser_timer = max(_taser_timer - delta, 0.0)
	_retarget_timer -= delta
	if _retarget_timer <= 0.0 or _current_target == null or not _is_valid_target(_current_target):
		_retarget_timer = RETARGET_INTERVAL
		_current_target = _pick_target()

	if not is_on_floor():
		velocity.y -= gravity * delta
	else:
		if velocity.y < 0.0:
			velocity.y = 0.0

	var horizontal := Vector3.ZERO
	if _current_target:
		var target_pos: Vector3 = _current_target.global_position
		# Update the nav target periodically so the agent re-paths to a moving
		# crewmate without re-querying every frame.
		_nav_repath_timer -= delta
		if _nav_agent and (_nav_repath_timer <= 0.0):
			_nav_repath_timer = NAV_REPATH_INTERVAL
			_nav_agent.target_position = target_pos
		# Three movement modes, in order of preference:
		#   1. Navmesh path: follow waypoints around walls / through doors.
		#   2. Line-of-sight + close: direct steer (same room).
		#   3. No path and no LOS: stand still — direct steering would just
		#      charge walls. Navmesh bake or target re-pathing will recover.
		var has_los := _has_line_of_sight(_current_target)
		var nav_ready: bool = (
			_nav_agent != null
			and _nav_agent.is_target_reachable()
			and not _nav_agent.is_navigation_finished()
		)
		var steer_target: Vector3 = Vector3.ZERO
		var should_move: bool = false
		if nav_ready:
			steer_target = _nav_agent.get_next_path_position()
			should_move = true
		elif has_los:
			steer_target = target_pos
			should_move = true
		# else: stuck without a path; idle in place until nav re-paths.
		if should_move:
			var to_step: Vector3 = steer_target - global_position
			to_step.y = 0.0
			var step_dist: float = to_step.length()
			if step_dist > 0.001:
				var dir: Vector3 = to_step / step_dist
				horizontal = dir * move_speed
				_target_rotation_y = atan2(-dir.x, -dir.z)
		# Fire if the actual target (not the waypoint) is in range + visible.
		var target_flat: Vector3 = target_pos - global_position
		target_flat.y = 0.0
		var target_dist: float = target_flat.length()
		if target_dist <= taser_range and _taser_timer <= 0.0 and has_los:
			_fire_taser(_current_target)
			_taser_timer = taser_cooldown

	velocity.x = horizontal.x
	velocity.z = horizontal.z

	# Stuck-jump: when trying to move but barely moving, hop.
	if horizontal.length_squared() > 0.01 and is_on_floor():
		var moved_sq: float = global_position.distance_squared_to(_last_position)
		if moved_sq < 0.0008:
			_stuck_timer += delta
			if _stuck_timer > STUCK_TIMEOUT:
				velocity.y = JUMP_VEL
				_stuck_timer = 0.0
		else:
			_stuck_timer = 0.0
	_last_position = global_position

	rotation.y = _target_rotation_y
	move_and_slide()

	_state_send_timer += delta
	if _state_send_timer >= STATE_SEND_RATE:
		_state_send_timer = 0.0
		NetworkManager.send_bot_state(steam_id, global_position, rotation.y)

func _is_valid_target(p: Node) -> bool:
	if p == null or not is_instance_valid(p):
		return false
	if not ("is_impostor" in p and "is_dead" in p):
		return false
	return not p.is_impostor and not p.is_dead

func _pick_target() -> Node3D:
	var best: Node3D = null
	var best_dist_sq: float = sight_range * sight_range
	if GameManager.players_container == null:
		return null
	for p in GameManager.players_container.get_children():
		if p == self:
			continue
		if not _is_valid_target(p):
			continue
		var d_sq: float = global_position.distance_squared_to(p.global_position)
		if d_sq < best_dist_sq:
			best_dist_sq = d_sq
			best = p
	return best

func _has_line_of_sight(target: Node3D) -> bool:
	var space := get_world_3d().direct_space_state
	var from: Vector3 = global_position + Vector3(0, 1.0, 0)
	var to: Vector3 = target.global_position + Vector3(0, 1.0, 0)
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.exclude = [self]
	# Mask 1 = world geometry / players. We exclude self; hitting the target
	# itself still counts as LOS.
	query.collision_mask = 1
	var result := space.intersect_ray(query)
	if result.is_empty():
		return true
	return result.collider == target

func _fire_taser(target: Node3D) -> void:
	var origin: Vector3 = global_position + Vector3(0, 1.0, 0)
	var direction: Vector3 = (target.global_position + Vector3(0, 1.0, 0) - origin).normalized()
	# Broadcast to all peers so every machine spawns a matching projectile.
	# The projectile's own collision handler routes damage via send_taser_hit,
	# matching the existing player-fired pattern.
	NetworkManager.send_bot_taser_shot(steam_id, origin, direction)

func _on_bot_taser_shot_received(bot_id: int, origin: Vector3, direction: Vector3) -> void:
	if bot_id != steam_id:
		return
	var projectile := Area3D.new()
	projectile.set_script(_PROJECTILE_SCRIPT)
	projectile.setup(origin, direction, steam_id)
	get_tree().root.add_child(projectile)

# Called on the HOST when the bot takes damage. Clients route hits to the host
# via NetworkManager.send_bot_hit.
func apply_damage(dmg: int) -> void:
	if is_dead:
		return
	if not LobbyManager.is_host():
		return
	current_health -= dmg
	if current_health <= 0:
		current_health = 0
		_enter_dead_state()

func _enter_dead_state() -> void:
	if is_dead:
		return
	is_dead = true
	visible = false
	$CollisionShape3D.disabled = true
	if LobbyManager.is_host():
		NetworkManager.send_bot_died(steam_id)
