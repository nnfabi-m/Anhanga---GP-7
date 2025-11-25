extends CharacterBody2D

# ======================
#   CONSTANTES GERAIS
# ======================
const SPEED: float = 60.0
const GRAVITY: float = 900.0
const ATTACK_RANGE: float = 32.0    # distância pra atacar
const VISION_DISTANCE: float = 160.0
const CHASE_SPEED_MULTIPLIER: float = 1.4

# ======================
#   NODES
# ======================
@onready var anim: AnimatedSprite2D = $AnimatedSprite2D
@onready var floor_check: RayCast2D  = $FloorCheck
@onready var wall_check: RayCast2D   = $WallCheck
@onready var hitbox: Area2D          = $Hitbox
@onready var vision_ray: RayCast2D   = $VisionRay
@onready var health_bar: ProgressBar = $HealthBar

@onready var patrol_a_node: Node2D = $PatrolA
@onready var patrol_b_node: Node2D = $PatrolB

# Player (achado por grupo "player")
var player: Node2D = null

# ======================
#   ESTADO / ATRIBUTOS
# ======================
enum EnemyState { PATROL, CHASE, ATTACK }
var state: EnemyState = EnemyState.PATROL

var direction: int = -1
var attacking: bool = false
var is_dead: bool = false   # flag de morte

# históricos dos raycasts (pra evitar flip louco)
var _floor_was_colliding: bool = true
var _wall_was_colliding: bool = false

# Patrulha
var patrol_a: Vector2
var patrol_b: Vector2
var patrol_target: Vector2

# HP / dano (podem ser sobrescritos via DSL)
var max_health: int = 40
var health: int = 40
var attack_damage: int = 10

# ID usado na DSL (ex: ENEMY1;enemy;3;1)
@export var dsl_id: String = "ENEMY1"


# ======================
#   READY
# ======================
func _ready() -> void:
	# Patrulha: pega posições dos marcadores
	if patrol_a_node and patrol_b_node:
		patrol_a = patrol_a_node.global_position
		patrol_b = patrol_b_node.global_position
		patrol_target = patrol_b
	else:
		patrol_a = global_position + Vector2(-32, 0)
		patrol_b = global_position + Vector2(32, 0)
		patrol_target = patrol_b

	_find_player()
	_load_stats_from_dsl()
	_update_health_bar()
	_update_vision_ray()
	_update_hitbox_direction()  # <<< garante hitbox do lado certo no início

	_floor_was_colliding = floor_check.is_colliding()
	_wall_was_colliding = wall_check.is_colliding()

	# Hitbox como área monitora o player
	if hitbox:
		hitbox.monitoring = true
		hitbox.monitorable = true


# Atualiza a posição do Hitbox pra sempre ficar "na frente" do inimigo
func _update_hitbox_direction() -> void:
	if not hitbox:
		return
	var pos := hitbox.position
	pos.x = abs(pos.x) * float(direction)   # direction = 1 (direita), -1 (esquerda)
	hitbox.position = pos


# ======================
#   LOOP DE FÍSICA
# ======================
func _physics_process(delta: float) -> void:
	# Se estiver morto, só deixa cair e não faz IA
	if is_dead:
		velocity.x = 0.0
		if not is_on_floor():
			velocity.y += GRAVITY * delta
		move_and_slide()
		return

	# Gravidade sempre
	if not is_on_floor():
		velocity.y += GRAVITY * delta

	match state:
		EnemyState.PATROL:
			_state_patrol(delta)
		EnemyState.CHASE:
			_state_chase(delta)
		EnemyState.ATTACK:
			_state_attack(delta)

	move_and_slide()
	anim.flip_h = (direction < 0)
	_update_vision_ray()


# ======================
#   ESTADO: PATROL
# ======================
func _state_patrol(_delta: float) -> void:
	_update_floor_wall_state()

	if patrol_a != patrol_b:
		var tx := patrol_target.x
		var dx := global_position.x - tx

		if abs(dx) < 4.0:
			if patrol_target == patrol_a:
				patrol_target = patrol_b
			else:
				patrol_target = patrol_a

		if global_position.x < patrol_target.x - 1.0:
			direction = 1
		elif global_position.x > patrol_target.x + 1.0:
			direction = -1

	_update_hitbox_direction()  # mantém hitbox na frente durante a patrulha

	velocity.x = direction * SPEED
	_play_walk()

	# Se enxergar o player, começa a perseguir
	if _can_see_player():
		state = EnemyState.CHASE


# ======================
#   ESTADO: CHASE
# ======================
func _state_chase(_delta: float) -> void:
	if player == null:
		_find_player()
		if player == null:
			state = EnemyState.PATROL
			return

	_update_floor_wall_state()

	var to_player: Vector2 = player.global_position - global_position
	var dist: float = to_player.length()

	# Perdeu o player
	if not _can_see_player() and dist > VISION_DISTANCE * 1.5:
		state = EnemyState.PATROL
		return

	# Range de ataque
	if dist <= ATTACK_RANGE:
		state = EnemyState.ATTACK
		velocity.x = 0.0
		return

	# Anda em direção ao player
	if to_player.x > 0.0:
		direction = 1
	elif to_player.x < 0.0:
		direction = -1

	_update_hitbox_direction()  # hitbox acompanha a direção na perseguição

	velocity.x = direction * SPEED * CHASE_SPEED_MULTIPLIER
	_play_walk()


# ======================
#   ESTADO: ATTACK
# ======================
func _state_attack(_delta: float) -> void:
	if player == null:
		_find_player()
		if player == null:
			state = EnemyState.PATROL
			return

	# Se já está no meio da animação, só fica parado
	if attacking:
		velocity.x = 0.0
		return

	var dist: float = player.global_position.distance_to(global_position)

	# Se saiu do alcance, volta a perseguir
	if dist > ATTACK_RANGE:
		state = EnemyState.CHASE
		return

	velocity.x = 0.0
	_play_attack()


# ======================
#   FLOOR / WALL LOGIC
# ======================
func _update_floor_wall_state() -> void:
	if is_on_floor():
		var floor_now: bool = floor_check.is_colliding()
		var wall_now: bool = wall_check.is_colliding()

		if _floor_was_colliding and not floor_now:
			_flip_direction()
		elif not _wall_was_colliding and wall_now:
			_flip_direction()

		_floor_was_colliding = floor_now
		_wall_was_colliding = wall_now


func _flip_direction() -> void:
	direction *= -1

	var fpos := floor_check.target_position
	fpos.x = abs(fpos.x) * direction
	floor_check.target_position = fpos

	var wpos := wall_check.target_position
	wpos.x = abs(wpos.x) * direction
	wall_check.target_position = wpos

	_update_hitbox_direction()   # vira hitbox junto com o inimigo


# ======================
#   VISÃO / PLAYER
# ======================
func _find_player() -> void:
	var n := get_tree().get_first_node_in_group("player")
	if n and n is Node2D:
		player = n


func _update_vision_ray() -> void:
	if not vision_ray:
		return
	vision_ray.target_position = Vector2(VISION_DISTANCE * float(direction), 0.0)


func _can_see_player() -> bool:
	if player == null:
		return false

	var dist := global_position.distance_to(player.global_position)
	if dist > VISION_DISTANCE:
		return false

	if not vision_ray:
		return true

	vision_ray.force_raycast_update()
	if not vision_ray.is_colliding():
		return true

	var collider := vision_ray.get_collider()
	if collider == player:
		return true
	if collider is Node and collider.is_in_group("player"):
		return true

	return false


# ======================
#   ANIMAÇÕES
# ======================
func _play_idle() -> void:
	if anim.animation != "idle":
		anim.play("idle")


func _play_walk() -> void:
	if anim.animation != "walking":
		anim.play("walking")


func _play_attack() -> void:
	if attacking or is_dead:
		return
	attacking = true
	anim.play("attack")
	await anim.animation_finished
	_deal_attack_damage()
	attacking = false

	# Depois do ataque, decide se continua perseguindo ou volta a patrulhar
	if _can_see_player():
		state = EnemyState.CHASE
	else:
		state = EnemyState.PATROL


func _deal_attack_damage() -> void:
	if not hitbox:
		return

	var bodies := hitbox.get_overlapping_bodies()
	for b in bodies:
		if not (b is Node):
			continue
		if not b.is_in_group("player"):
			continue

		if b.has_method("take_damage"):
			b.take_damage(attack_damage)
		elif b.has_method("_die"):
			b._die()


# ======================
#   VIDA / DSL
# ======================
func _load_stats_from_dsl() -> void:
	# ATENÇÃO: caminho bate com o que aparece na tua aba de arquivos
	var path := "res://data/combat.txt"
	if not FileAccess.file_exists(path):
		return

	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return

	while not f.eof_reached():
		var line := f.get_line().strip_edges()
		if line == "" or line.begins_with("#"):
			continue

		# Ex: ENEMY1;enemy;3;1
		var parts := line.split(";")
		if parts.size() < 4:
			continue

		if parts[0].strip_edges() != dsl_id:
			continue

		var hp_str := parts[2].strip_edges()
		var atk_str := parts[3].strip_edges()

		var hp := int(hp_str)
		var atk := int(atk_str)

		max_health = hp
		health = hp
		attack_damage = atk
		break


func _update_health_bar() -> void:
	if health_bar:
		health_bar.max_value = max_health
		health_bar.value = health


func apply_damage(amount: int) -> void:
	if is_dead:
		return

	health -= amount
	if health < 0:
		health = 0
	_update_health_bar()

	if health <= 0:
		await _die()


# ======================
#   MORTE (ANIMAÇÃO "dead")
# ======================
func _die() -> void:
	if is_dead:
		return
	is_dead = true

	# Para ataque e desliga hitbox
	attacking = false
	if hitbox:
		hitbox.monitoring = false
		hitbox.monitorable = false

	velocity = Vector2.ZERO

	if anim and anim.sprite_frames and anim.sprite_frames.has_animation("dead"):
		anim.play("dead")
		await anim.animation_finished

	queue_free()
