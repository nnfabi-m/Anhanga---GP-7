extends Node
class_name CombatData

class CombatStats:
	var id: String
	var type: String
	var max_health: int
	var attack: int

var _stats: Dictionary = {}

func _ready() -> void:
	_load_combat_file()

func _load_combat_file() -> void:
	_stats.clear()

	var path := "res://data/combat.txt"
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_warning("CombatData: NÃO conseguiu abrir %s" % path)
		return

	while not file.eof_reached():
		var line := file.get_line().strip_edges()
		if line == "" or line.begins_with("#"):
			continue

		var parts := line.split(";")
		if parts.size() < 4:
			continue

		var s := CombatStats.new()
		s.id = parts[0]
		s.type = parts[1]
		s.max_health = int(parts[2])
		s.attack = int(parts[3])

		_stats[s.id] = s

	file.close()

func get_stats(id: String):
	if _stats.has(id):
		return _stats[id]
	return null
