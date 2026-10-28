extends StaticBody3D
## A butchered walrus left by the hunt, the tusks hacked out. Its blubber burns long.

const Meshes := preload("res://scripts/meshes.gd")
const Materials := preload("res://scripts/materials.gd")

static var _stain: ImageTexture

var blubber := 2
var seed := 0


func _ready() -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = Meshes.walrus(seed)
	mi.material_override = Materials.get_mat("walrus")
	mi.layers = 2  # so the blood on the snow does not paint the walrus too
	add_child(mi)

	# Old blood frozen into the snow below the head, where the tusks were cut out.
	var decal := Decal.new()
	decal.size = Vector3(2.6, 1.2, 2.0)
	decal.position = Vector3(1.4, 0.3, 0.0)
	decal.texture_albedo = _stain_texture()
	decal.modulate = Color(0.3, 0.07, 0.06)
	decal.albedo_mix = 0.8
	decal.cull_mask = 1
	add_child(decal)

	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(3.6, 0.8, 1.5)
	cs.shape = box
	cs.position = Vector3(0.2, 0.4, 0.0)
	add_child(cs)


static func _stain_texture() -> ImageTexture:
	if _stain == null:
		var n := FastNoiseLite.new()
		n.seed = 5
		n.frequency = 0.04
		var img := Image.create(128, 128, false, Image.FORMAT_RGBA8)
		for y in range(128):
			for x in range(128):
				var d := Vector2(x - 54.0, (y - 64.0) * 1.3).length() / 60.0
				var a := clampf((1.0 - d) * 1.6 + n.get_noise_2d(x, y) * 0.9 - 0.2, 0.0, 1.0)
				img.set_pixel(x, y, Color(1, 1, 1, a * a))
		_stain = ImageTexture.create_from_image(img)
	return _stain


func get_prompt(player) -> String:
	if blubber <= 0:
		return ""
	return "Cut blubber" if player.can_carry() else "Your arms are full"


func interact(player) -> void:
	if blubber > 0 and player.can_carry():
		blubber -= 1
		player.carry_item("blubber", 90.0)
		player.play_sfx("carve")
		player.main.on_cut_blubber()
	elif blubber > 0:
		player.main.voice.say("arms_full")
