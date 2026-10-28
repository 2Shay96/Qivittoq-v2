extends StaticBody3D
## The woodpile beside the fire: what the day gathers for the night to burn.

const Meshes := preload("res://scripts/meshes.gd")
const Materials := preload("res://scripts/materials.gd")
const FuelItem := preload("res://scripts/fuel_item.gd")

static var _blubber: ArrayMesh

var main
var stock: Array = []  # items like {"kind": "driftwood", "value": 45.0}

var _logs: Node3D


func _ready() -> void:
	_logs = Node3D.new()
	add_child(_logs)
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(1.4, 0.6, 0.9)
	cs.shape = box
	cs.position.y = 0.3
	add_child(cs)
	_rebuild()


func count() -> int:
	return stock.size()


func add(items: Array) -> void:
	stock.append_array(items)
	_rebuild()


func _rebuild() -> void:
	for child in _logs.get_children():
		child.queue_free()
	if _blubber == null:
		_blubber = Meshes.blubber(3)
	for k in range(mini(stock.size(), 18)):
		var item: Dictionary = stock[k]
		var mi := MeshInstance3D.new()
		var row := k / 6
		var slot := k % 6
		if item["kind"] == "blubber":
			mi.mesh = _blubber
			mi.material_override = Materials.get_mat("blubber")
			mi.scale = Vector3.ONE * 1.3
			mi.rotation.y = 0.4 * slot
		else:
			mi.mesh = FuelItem.driftwood_mesh(k)
			mi.material_override = Materials.get_mat("driftwood")
			mi.rotation.y = 0.1 if (k * 7) % 3 == 0 else -0.07
		mi.position = Vector3(0.03 * ((k * 5) % 3 - 1), 0.08 + row * 0.13, -0.32 + slot * 0.13)
		_logs.add_child(mi)


func get_prompt(player) -> String:
	if player.carrying():
		return "Stack it on the woodpile"
	if stock.size() > 0 and player.can_carry():
		return "Take fuel (%d left)" % stock.size()
	return ""


func interact(player) -> void:
	if player.carrying():
		add(player.drop_all())
		player.play_sfx("wood_drop")
	elif stock.size() > 0:
		while stock.size() > 0 and player.can_carry():
			var item: Dictionary = stock.pop_back()
			player.carry_item(item["kind"], item["value"])
		_rebuild()
