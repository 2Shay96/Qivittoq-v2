extends StaticBody3D
## A piece of fuel lying on the ground: driftwood, bleached grey like bone.

const Meshes := preload("res://scripts/meshes.gd")
const Materials := preload("res://scripts/materials.gd")
const LENGTHS := [1.1, 1.45, 0.9, 1.3, 1.6, 1.0]
const RADII := [0.06, 0.08, 0.05, 0.07, 0.085, 0.055]

static var _meshes: Array = []

var kind := "driftwood"
var value := 45.0
var seed := 0


static func driftwood_mesh(k: int) -> ArrayMesh:
	if _meshes.is_empty():
		for i in range(LENGTHS.size()):
			_meshes.append(Meshes.log_mesh(LENGTHS[i], RADII[i], 200 + i, 0.07))
	return _meshes[k % _meshes.size()]


func _ready() -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = driftwood_mesh(seed)
	mi.material_override = Materials.get_mat("driftwood")
	add_child(mi)
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(LENGTHS[seed % LENGTHS.size()], 0.3, 0.3)
	cs.shape = box
	add_child(cs)


func get_prompt(player) -> String:
	return "Pick up driftwood" if player.can_carry() else "Your arms are full"


func interact(player) -> void:
	if player.can_carry():
		player.carry_item(kind, value)
		queue_free()
	else:
		player.main.voice.say("arms_full")
