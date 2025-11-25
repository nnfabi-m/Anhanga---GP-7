extends CharacterBody2D

# ===== MOVIMENTO =====
const WALK_SPEED: float = 80.0
const RUN_SPEED: float  = 140.0
const JUMP_VELOCITY: float = -200.0
const ACCELERATION: float = 1000.0
const FRICTION: float     = 1200.0

# ===== CRAWL (agachar/engatinhar) =====
const CRAWL_SPEED: float = 50.0
const CRAWL_SCALE_Y: float = 0.50
const CRAWL_OFFSET_Y: float = 6.0

# ===== LEDGE (auto) =====
const AUTO_LEDGE: bool = true
const HANG_X_OFFSET: float = 8.0
const HANG_Y_OFFSET: float = 0.25
const PUSH_FROM_WALL: float = 3.0
const CLIMB_CLEAR_X: float = 0.01
const CLIMB_UP_OFFSET: Vector2 = Vector2(6, 1)
const CLIMB_TIME: float = 0.20

const AUTO_CLIMB: bool = true
const LEDGE_AUTO_DELAY: float = 0.06

const AIR_TIME_MIN_FOR_LEDGE: float = 0.06
const MIN_FALL_SPEED_FOR_LEDGE: float = 22.0
const MAX_FALL_SPEED_FOR_LEDGE: float = 420.0

const LEDGE_MIN_HEIGHT: float = 12.0
const LEDGE_MAX_HEIGHT: float = 46.0

const LEDGE_COOLDOWN_TIME: float = 0.30
const SAME_LEDGE_FORBID_RADIUS: float = 28.0

const CHEST_HEIGHT: float = 12.0
const HEAD_HEIGHT: float  = 24.0
const PROBE_FORWARD: float = 22.0
const PROBE_DROP: float    = 66.0

const FLOOR_SNAP_GROUND: float = 8.0
const FLOOR_SNAP_AIR: float = 0.0

# ===== MORTE / GHOST =====
const GHOST_DURATION: float = 2.0
const GHOST_RISE: float = 32.0
const GHOST_FADE_START: float = 0.5

# --- Jump quality ---
const COYOTE_TIME: float = 0.12
const JUMP_BUFFER: float = 0.12
var coyote_timer: float = 0.0
var jump_buffer_timer: float = 0.0

const DEBUG_LEDGE: bool = false

@onready var anim: AnimatedSprite2D = $AnimatedSprite2D
@onready var wall_check: RayCast2D = $WallCheck
@onready var ledge_check: RayCast2D = $LedgeCheck
@onready var head_clear: RayCast2D = $HeadClearCheck
@onready var col: CollisionShape2D = get_node_or_null("CollisionShape2D")
@onready var ghost: AnimatedSprite2D = get_node_or_null("Ghost")
@onready var health_bar: ProgressBar = get_node_or_null("HealthBar")
@onready var attack_hitbox: Area2D = get_node_or_null("AttackHitbox")

var facing: int = 1

const ANIMS := {
	"idle": "idle",
	"walk": "walkingtest",
	"run":  "runningtest",
	"jump": "jump",
	"fall": "fall",
	"ledge": "ledge",
	"crawl": "crawl",
	"death": "death",
	"angel": "angel"
}

enum State { NORMAL, CRAWL, LEDGE_GRAB, LEDGE_CLIMB, DEAD }
var state: State = State.NORMAL
var is_dead: bool = false
var _is_attacking: bool = false
var _attack_timer: float = 0.0

var _crawl_latch: bool = false

var ledge_top_world: Vector2 = Vector2.ZERO
var climb_elapsed: float = 0.0
var climb_start: Vector2 = Vector2.ZERO
var climb_target: Vector2 = Vector2.ZERO
var ledge_cooldown: float = 0.0
var air_time: float = 0.0

var last_ledge_pos: Vector2 = Vector2.INF
var last_ledge_frame: int = -999
var ledge_auto_timer: float = 0.0

var _orig_shape_data := {}
var _is_crawl_shape := false

var _dbg_from_chest: Vector2
var _dbg_to_chest: Vector2
var _dbg_edge_from: Vector2
var _dbg_edge_to: Vector2
var _dbg_head_from: Vector2
var _dbg_head_to: Vector2
var _dbg_ledge_pick: Vector2
var _dbg_hit_valid: bool = false

# ===== COMBAT / VIDA (via combat.txt) =====
var max_health: int = 5
var health: int = 5
var attack_power: int = 1     # dano base no inimigo (via DSL)
var _current_attack_damage: int = 0  # dano do ataque atual (normal x especial)
var _is_defending: bool = false      # <<< NOVO: indica se está defendendo

@export var combat_id: String = "PLAYER"
const COMBAT_FILE_PATH := "res://data/combat.txt"

# ===== DURACÕES COMBATE =====
const ATTACK_DURATION: float = 0.4
const SPECIAL_ATTACK_DURATION: float = 0.7
const DEFEND_DURATION: float = 0.5


# ================= INPUT HELPERS =================
func _has_action(a: String) -> bool:
	return InputMap.has_action(a)

func _pressed_move_left() -> bool:
	return (_has_action("move_left") and Input.is_action_pressed("move_left")) \
		or Input.is_physical_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT)

func _pressed_move_right() -> bool:
	return (_has_action("move_right") and Input.is_action_pressed("move_right")) \
		or Input.is_physical_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT)

func _axis_lr() -> int:
	return int(_pressed_move_right()) - int(_pressed_move_left())

func _pressed_jump_any() -> bool:
	return (_has_action("jump") and Input.is_action_pressed("jump")) \
		or Input.is_physical_key_pressed(KEY_W) or Input.is_key_pressed(KEY_SPACE) or Input.is_key_pressed(KEY_UP)

func _pressed_crawl() -> bool:
	return (_has_action("crawl") and Input.is_action_pressed("crawl")) \
		or Input.is_physical_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN)

func _pressed_run() -> bool:
	return (_has_action("run") and Input.is_action_pressed("run")) \
		or Input.is_key_pressed(KEY_SHIFT)

func _just_pressed_attack() -> bool:
	# um clique = um ataque; sem flood por is_mouse_button_pressed
	return (_has_action("attack") and Input.is_action_just_pressed("attack"))

func _pressed_defend() -> bool:
	return (_has_action("defend") and Input.is_action_pressed("defend")) \
		or Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT)

func _ctrl_down() -> bool:
	return Input.is_key_pressed(KEY_CTRL)

# vira player e ajusta raycasts + hitbox de ataque
func _set_facing(new_facing: int) -> void:
	if new_facing == facing:
		return
	facing = new_facing
	_update_raycast_directions()
	if attack_hitbox:
		var pos := attack_hitbox.position
		pos.x = abs(pos.x) * float(facing)  # sempre pra frente do player
		attack_hitbox.position = pos


# =================================================================================================

func safe_play(name: String) -> void:
	if not anim or not anim.sprite_frames or not anim.sprite_frames.has_animation(name):
		return
	var is_combat := (name == "attack" or name == "specialAttack" or name == "defend")
	if is_combat:
		anim.play(name)
		return
	if anim.animation != name and not _is_attacking:
		anim.play(name)


func _ready() -> void:
	_update_raycast_directions()
	_set_facing(facing)  # normaliza raycasts + hitbox de ataque na direção inicial

	floor_snap_length = FLOOR_SNAP_GROUND
	_cache_original_shape()
	if ghost:
		ghost.visible = false
		ghost.modulate.a = 0.0
	if DEBUG_LEDGE:
		set_process(true)

	# ==== GRUPO "player" + COMBAT TXT ====
	add_to_group("player")
	_load_combat_stats()
	_update_health_bar()

	if attack_hitbox:
		attack_hitbox.monitoring = true
		attack_hitbox.monitorable = true
		
	# ==== GRUPO "player" + COMBAT TXT ====
	add_to_group("player")
	_load_combat_stats()
	_update_health_bar()

	if attack_hitbox:
		attack_hitbox.monitoring = true
		attack_hitbox.monitorable = true
		# se quiser, pode manter o sinal conectado ao _on_attack_hitbox_body_entered


func _physics_process(delta: float) -> void:
	if is_dead:
		return

	coyote_timer = max(0.0, coyote_timer - delta)
	jump_buffer_timer = max(0.0, jump_buffer_timer - delta)
	if is_on_floor():
		coyote_timer = COYOTE_TIME

	if ledge_cooldown > 0.0:
		ledge_cooldown -= delta

	if is_on_floor():
		air_time = 0.0
	else:
		air_time += delta

	match state:
		State.NORMAL:
			_state_normal(delta)
		State.CRAWL:
			_state_crawl(delta)
		State.LEDGE_GRAB:
			_state_ledge_grab(delta)
		State.LEDGE_CLIMB:
			_state_ledge_climb(delta)
		State.DEAD:
			_state_dead(delta)

	if DEBUG_LEDGE:
		queue_redraw()

# ================= NORMAL =================
func _state_normal(delta: float) -> void:
	floor_snap_length = (FLOOR_SNAP_GROUND if is_on_floor() else FLOOR_SNAP_AIR)

	# Entrar em crawl (somente no chão)
	if _pressed_crawl() and is_on_floor():
		state = State.CRAWL
		_crawl_latch = false
		_apply_crawl_shape(true)
		safe_play(ANIMS.get("crawl", "walk"))
		return

	# Gravidade
	if not is_on_floor():
		velocity += get_gravity() * delta

	# Pulo sem buffer
	if _pressed_jump_any() and (is_on_floor() or coyote_timer > 0.0):
		velocity.y = JUMP_VELOCITY
		coyote_timer = 0.0
		safe_play(ANIMS.get("jump", "idle"))

	# Movimento horizontal
	var dir_i: int = _axis_lr()
	var dir: float = float(dir_i)
	var running: bool = _pressed_run()

	var target_speed: float = 0.0
	if dir_i != 0:
		target_speed = (RUN_SPEED if running else WALK_SPEED) * dir
		if dir_i > 0:
			_set_facing(1)
		elif dir_i < 0:
			_set_facing(-1)

	if dir_i != 0:
		velocity.x = move_toward(velocity.x, target_speed, ACCELERATION * delta)
	else:
		velocity.x = move_toward(velocity.x, 0.0, FRICTION * delta)

	move_and_slide()
	anim.flip_h = (facing == -1)

	# AUTO-LEDGE
	if AUTO_LEDGE \
		and not is_on_floor() \
		and velocity.y > MIN_FALL_SPEED_FOR_LEDGE and velocity.y < MAX_FALL_SPEED_FOR_LEDGE \
		and air_time >= AIR_TIME_MIN_FOR_LEDGE \
		and ledge_cooldown <= 0.0 \
		and dir_i != 0 \
		and coyote_timer <= 0.0:
		if _try_auto_ledge():
			return

	# Ataques
	if _just_pressed_attack():
		if _ctrl_down():
			_perform_special_attack()
		else:
			_perform_attack()
		return
	elif _pressed_defend():
		_perform_defend()
		return

	# Animações
	if state == State.NORMAL and not _is_attacking:
		if is_on_floor():
			var speed_abs: float = abs(velocity.x)
			if speed_abs < 5.0:
				safe_play(ANIMS["idle"])
			elif running:
				safe_play(ANIMS["run"])
			else:
				safe_play(ANIMS["walk"])
		else:
			if velocity.y <= -10.0:
				safe_play(ANIMS.get("jump", "idle"))
			elif velocity.y >= 10.0:
				safe_play(ANIMS.get("fall", "idle"))

# ================= CRAWL =================
func _state_crawl(delta: float) -> void:
	floor_snap_length = FLOOR_SNAP_GROUND

	var crawl_pressed := _pressed_crawl()

	# Quando SOLTAR o crawl
	if not crawl_pressed:
		if _has_blocking_ceiling():
			_die()
			return

		state = State.NORMAL
		_apply_crawl_shape(false)
		safe_play(ANIMS.get("idle", "idle"))
		return

	# Enquanto estiver segurando, apenas rasteja
	var dir_i: int = _axis_lr()
	var target_speed: float = CRAWL_SPEED * float(dir_i)
	if dir_i != 0:
		if dir_i > 0:
			_set_facing(1)
		elif dir_i < 0:
			_set_facing(-1)
		velocity.x = move_toward(velocity.x, target_speed, ACCELERATION * 0.6 * delta)
	else:
		velocity.x = move_toward(velocity.x, 0.0, FRICTION * delta)

	move_and_slide()
	anim.flip_h = (facing == -1)
	safe_play(ANIMS.get("crawl", "walk"))

#===========CAN STAND==============
func _can_stand() -> bool:
	if _orig_shape_data.is_empty():
		return true

	var space: PhysicsDirectSpaceState2D = get_world_2d().direct_space_state
	var params := PhysicsShapeQueryParameters2D.new()
	params.collide_with_areas = false
	params.exclude = [self]

	var stand_shape: Shape2D
	var stand_origin: Vector2 = Vector2.ZERO

	match _orig_shape_data.get("type"):
		"rect":
			var ext: Vector2 = _orig_shape_data.get("extents") as Vector2
			var pos0: Vector2 = _orig_shape_data.get("pos") as Vector2
			var r := RectangleShape2D.new()
			r.extents = ext
			stand_shape = r
			stand_origin = global_position + pos0
		"capsule":
			var h0: float = float(_orig_shape_data.get("height"))
			var rad: float = float(_orig_shape_data.get("radius"))
			var pos1: Vector2 = _orig_shape_data.get("pos") as Vector2
			var c := CapsuleShape2D.new()
			c.height = h0
			c.radius = rad
			stand_shape = c
			stand_origin = global_position + pos1
		_:
			return true

	var xf := Transform2D.IDENTITY
	xf.origin = stand_origin
	params.shape = stand_shape
	params.transform = xf

	var hits := space.intersect_shape(params, 1)
	return hits.is_empty()

# ===== BLOQUEIO NO TETO =====
func _has_blocking_ceiling() -> bool:
	if not head_clear:
		return false
	if not head_clear.is_colliding():
		return false

	var collider: Object = head_clear.get_collider()
	if collider == null:
		return false

	if collider is Node:
		var node := collider as Node
		if node.is_in_group("enemy"):
			return false

	return true

# ================= LEDGE =================
func _try_auto_ledge() -> bool:
	if last_ledge_frame > 0 and (Engine.get_physics_frames() - last_ledge_frame) < 6:
		return false

	var space: PhysicsDirectSpaceState2D = get_world_2d().direct_space_state
	_dbg_hit_valid = false

	var from_chest: Vector2 = global_position + Vector2(0.0, -CHEST_HEIGHT)
	var to_chest: Vector2 = from_chest + Vector2(PROBE_FORWARD * facing, 0.0)
	var q: PhysicsRayQueryParameters2D = PhysicsRayQueryParameters2D.create(from_chest, to_chest)
	q.collide_with_areas = false
	q.exclude = [self]
	var hit: Dictionary = space.intersect_ray(q)
	_dbg_from_chest = from_chest
	_dbg_to_chest = to_chest
	if hit.is_empty():
		return false

	var hit_pos: Vector2 = hit["position"]
	var hit_normal: Vector2 = hit["normal"]
	if abs(hit_normal.y) > 0.25:
		return false

	var edge_from: Vector2 = hit_pos + Vector2(-hit_normal.x * 2.0, -HEAD_HEIGHT)
	var edge_to: Vector2 = edge_from + Vector2(0.0, PROBE_DROP)
	q = PhysicsRayQueryParameters2D.create(edge_from, edge_to)
	q.collide_with_areas = false
	q.exclude = [self]
	var drop: Dictionary = space.intersect_ray(q)
	_dbg_edge_from = edge_from
	_dbg_edge_to = edge_to
	if drop.is_empty():
		return false

	var ledge_pos: Vector2 = drop["position"]

	var delta_y: float = global_position.y - ledge_pos.y
	if delta_y < LEDGE_MIN_HEIGHT or delta_y > LEDGE_MAX_HEIGHT:
		return false

	var head_from: Vector2 = ledge_pos + Vector2(-facing * 6.0, -HEAD_HEIGHT)
	var head_to: Vector2 = head_from + Vector2(12.0 * facing, -12.0)
	q = PhysicsRayQueryParameters2D.create(head_from, head_to)
	q.collide_with_areas = false
	q.exclude = [self]
	var head_hit: Dictionary = space.intersect_ray(q)
	_dbg_head_from = head_from
	_dbg_head_to = head_to
	if not head_hit.is_empty():
		return false

	if last_ledge_pos != Vector2.INF and last_ledge_pos.distance_to(ledge_pos) <= SAME_LEDGE_FORBID_RADIUS and ledge_cooldown > 0.0:
		return false

	ledge_top_world = ledge_pos
	climb_start = ledge_top_world + Vector2(-facing * (HANG_X_OFFSET + PUSH_FROM_WALL), -HANG_Y_OFFSET)
	climb_target = ledge_top_world + Vector2(-facing * (CLIMB_UP_OFFSET.x + CLIMB_CLEAR_X), -CLIMB_UP_OFFSET.y)

	state = State.LEDGE_CLIMB
	climb_elapsed = 0.0
	velocity = Vector2.ZERO
	floor_snap_length = FLOOR_SNAP_AIR
	global_position = climb_start
	safe_play(ANIMS["ledge"])

	last_ledge_pos = ledge_pos
	last_ledge_frame = Engine.get_physics_frames()
	_dbg_ledge_pick = ledge_pos
	_dbg_hit_valid = true
	return true

func _state_ledge_grab(delta: float) -> void:
	velocity = Vector2.ZERO
	floor_snap_length = FLOOR_SNAP_AIR
	var hang_pos: Vector2 = ledge_top_world + Vector2(-facing * (HANG_X_OFFSET + PUSH_FROM_WALL), -HANG_Y_OFFSET)
	global_position = hang_pos
	anim.flip_h = (facing == -1)
	safe_play(ANIMS["ledge"])

func _state_ledge_climb(delta: float) -> void:
	velocity = Vector2.ZERO
	floor_snap_length = FLOOR_SNAP_AIR

	climb_elapsed += delta
	var t: float = clamp(climb_elapsed / CLIMB_TIME, 0.0, 1.0)
	var t_eased: float = t * t * (3.0 - 2.0 * t)
	global_position = climb_start.lerp(climb_target, t_eased)

	anim.flip_h = (facing == -1)
	safe_play(ANIMS["ledge"])

	if t >= 1.0:
		state = State.NORMAL
		ledge_cooldown = LEDGE_COOLDOWN_TIME
		floor_snap_length = FLOOR_SNAP_GROUND

		var space2: PhysicsDirectSpaceState2D = get_world_2d().direct_space_state
		var from: Vector2 = global_position
		var to: Vector2 = from + Vector2(0.0, 4.0)
		var q2: PhysicsRayQueryParameters2D = PhysicsRayQueryParameters2D.create(from, to)
		q2.collide_with_areas = false
		q2.exclude = [self]
		var hit2: Dictionary = space2.intersect_ray(q2)
		if not hit2.is_empty():
			global_position.y = hit2["position"].y - 1.0

		safe_play(ANIMS["idle"])

func _update_raycast_directions() -> void:
	if wall_check:
		wall_check.target_position = Vector2(16.0 * facing, 0.0)
	if ledge_check:
		ledge_check.position = Vector2(10.0 * facing, -24.0)
		ledge_check.target_position = Vector2(0.0, 48.0)
	if head_clear:
		head_clear.position = Vector2(10.0 * facing, -36.0)
		head_clear.target_position = Vector2(14.0 * facing, -28.0)

func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSFORM_CHANGED and anim:
		anim.flip_h = (facing == -1)

# ===== DEAD =====
func _state_dead(_delta: float) -> void:
	velocity = Vector2.ZERO

func _play_once(sprite: AnimatedSprite2D, name: String) -> void:
	if not sprite or not sprite.sprite_frames or not sprite.sprite_frames.has_animation(name):
		return
	sprite.play(name)
	var sf: SpriteFrames = sprite.sprite_frames
	var frames: int = sf.get_frame_count(name)
	var speed: float = max(sf.get_animation_speed(name), 0.001)
	var duration: float = float(frames) / speed
	await get_tree().create_timer(duration).timeout
	sprite.stop()
	sprite.frame = max(frames - 1, 0)

func _die() -> void:
	if is_dead:
		return
	is_dead = true
	state = State.DEAD
	velocity = Vector2.ZERO
	floor_snap_length = 0.0

	if col:
		col.disabled = true

	if anim and ANIMS.has("death"):
		await _play_once(anim, ANIMS["death"])
	else:
		if anim:
			anim.stop()

	if ghost:
		ghost.visible = true
		ghost.modulate.a = 0.7
		if ghost.sprite_frames and ghost.sprite_frames.has_animation(ANIMS.get("angel", "angel")):
			ghost.play(ANIMS.get("angel", "angel"))
		ghost.position = Vector2(0, -8)

		var tw: Tween = create_tween()
		tw.tween_property(ghost, "position:y", ghost.position.y - GHOST_RISE, GHOST_DURATION)
		tw.parallel().tween_property(ghost, "modulate:a", 0.7, GHOST_DURATION * GHOST_FADE_START)
		tw.tween_property(ghost, "modulate:a", 0.0, GHOST_DURATION * (1.0 - GHOST_FADE_START))

# ===== collider helpers =====
func _cache_original_shape() -> void:
	if col and col.shape:
		if col.shape is RectangleShape2D:
			var r := col.shape as RectangleShape2D
			_orig_shape_data = {
				"type": "rect",
				"extents": r.extents,
				"pos": col.position
			}
		elif col.shape is CapsuleShape2D:
			var c := col.shape as CapsuleShape2D
			_orig_shape_data = {
				"type": "capsule",
				"height": float(c.height),
				"radius": float(c.radius),
				"pos": col.position
			}
		else:
			_orig_shape_data = {"type": "other"}

func _apply_crawl_shape(enable: bool) -> void:
	if not col or not col.shape or _orig_shape_data.is_empty():
		_is_crawl_shape = enable
		return

	if enable and not _is_crawl_shape:
		match _orig_shape_data.get("type"):
			"rect":
				var r := col.shape as RectangleShape2D
				var ext: Vector2 = _orig_shape_data.get("extents") as Vector2
				var pos0: Vector2 = _orig_shape_data.get("pos") as Vector2
				r.extents = Vector2(ext.x, ext.y * CRAWL_SCALE_Y)
				col.position = pos0 + Vector2(0, CRAWL_OFFSET_Y)
			"capsule":
				var c := col.shape as CapsuleShape2D
				var h0: float = float(_orig_shape_data.get("height"))
				var pos1: Vector2 = _orig_shape_data.get("pos") as Vector2
				c.height = h0 * CRAWL_SCALE_Y
				col.position = pos1 + Vector2(0, CRAWL_OFFSET_Y)
		_is_crawl_shape = true
	elif (not enable) and _is_crawl_shape:
		match _orig_shape_data.get("type"):
			"rect":
				var r2 := col.shape as RectangleShape2D
				var ext0: Vector2 = _orig_shape_data.get("extents") as Vector2
				var pos2: Vector2 = _orig_shape_data.get("pos") as Vector2
				r2.extents = ext0
				col.position = pos2
			"capsule":
				var c2 := col.shape as CapsuleShape2D
				var h00: float = float(_orig_shape_data.get("height"))
				var pos3: Vector2 = _orig_shape_data.get("pos") as Vector2
				c2.height = h00
				col.position = pos3
		_is_crawl_shape = false

# ===== COMBATE: carregar stats do combat.txt =====
func _load_combat_stats() -> void:
	var path := COMBAT_FILE_PATH
	if not FileAccess.file_exists(path):
		return

	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return

	while not f.eof_reached():
		var line := f.get_line().strip_edges()
		if line == "" or line.begins_with("#"):
			continue

		# Ex: PLAYER;player;5;1
		var parts := line.split(";")
		if parts.size() < 4:
			continue

		if parts[0].strip_edges() != combat_id:
			continue

		var hp_str := parts[2].strip_edges()
		var atk_str := parts[3].strip_edges()

		var hp := int(hp_str)
		var atk := int(atk_str)

		max_health = hp
		health = hp
		attack_power = atk
		break


func _update_health_bar() -> void:
	if health_bar:
		health_bar.max_value = max_health
		health_bar.value = health


func take_damage(amount: int) -> void:
	if is_dead:
		return

	# se estiver defendendo, ignora dano
	if _is_defending:
		return

	health -= amount
	if health < 0:
		health = 0

	_update_health_bar()

	if health <= 0:
		_die()

# ===== ATAQUE / DEFESA =====
func _perform_attack() -> void:
	if _is_attacking or is_dead:
		return
	_is_attacking = true
	_current_attack_damage = attack_power        # dano normal
	velocity = Vector2.ZERO
	if anim and anim.sprite_frames and anim.sprite_frames.has_animation("attack"):
		anim.play("attack")
	await get_tree().create_timer(ATTACK_DURATION).timeout
	_deal_attack_damage()
	_is_attacking = false

func _perform_special_attack() -> void:
	if _is_attacking or is_dead:
		return
	_is_attacking = true
	_current_attack_damage = attack_power * 2   # dano dobrado
	velocity = Vector2.ZERO
	if anim and anim.sprite_frames and anim.sprite_frames.has_animation("specialAttack"):
		anim.play("specialAttack")
	await get_tree().create_timer(SPECIAL_ATTACK_DURATION).timeout
	_deal_attack_damage()
	_is_attacking = false

func _perform_defend() -> void:
	if is_dead or state != State.NORMAL:
		return

	_is_attacking = true
	_is_defending = true          # ativa defesa
	_current_attack_damage = 0    # não dá dano defendendo
	velocity = Vector2.ZERO

	if anim and anim.sprite_frames and anim.sprite_frames.has_animation("defend"):
		anim.play("defend")

	await get_tree().create_timer(DEFEND_DURATION).timeout

	_is_defending = false         # terminou defesa
	_is_attacking = false

# ===== HITBOX DE ATAQUE =====
func _deal_attack_damage() -> void:
	if not attack_hitbox:
		return
	if _current_attack_damage <= 0:
		return

	var bodies := attack_hitbox.get_overlapping_bodies()
	for b in bodies:
		if not (b is Node):
			continue
		if not b.is_in_group("enemy"):
			continue

		if b.has_method("apply_damage"):
			b.apply_damage(_current_attack_damage)
		elif b.has_method("take_damage"):
			b.take_damage(_current_attack_damage)

	_current_attack_damage = 0

# se o sinal estiver conectado, ainda respeita o estado atual
func _on_attack_hitbox_body_entered(body: Node) -> void:
	if not _is_attacking:
		return
	if _current_attack_damage <= 0:
		return
	if body.is_in_group("enemy"):
		if body.has_method("apply_damage"):
			body.apply_damage(_current_attack_damage)
		elif body.has_method("take_damage"):
			body.take_damage(_current_attack_damage)

# ===== DEBUG DRAW =====
func _draw() -> void:
	if not DEBUG_LEDGE:
		return
	draw_line(to_local(_dbg_from_chest), to_local(_dbg_to_chest), Color(0.2, 0.6, 1.0), 1.0)
	draw_line(to_local(_dbg_edge_from), to_local(_dbg_edge_to), Color(1.0, 0.6, 0.2), 1.0)
	draw_line(to_local(_dbg_head_from), to_local(_dbg_head_to), Color(0.2, 1.0, 0.6), 1.0)
	if _dbg_hit_valid:
		draw_circle(to_local(_dbg_ledge_pick), 3.0, Color(1, 0, 0, 0.9))
