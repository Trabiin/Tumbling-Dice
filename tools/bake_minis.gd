extends SceneTree
## Bakes KayKit characters into posed, static miniatures for the tale board and the foe stand.
##
##   godot --headless -s res://tools/bake_minis.gd -- --adventurers=DIR --skeletons=DIR [--only=knight,mage]
##
## DIR is a clone of github.com/KayKit-Game-Assets/KayKit-Character-Pack-Adventures-1.0 or
## ...-Skeletons-1.0. Each character is posed with one of its animations, the parts we want
## are skinned on the CPU and merged into one mesh (one draw call), and the result is saved to
## assets/kits/minis/<kind>.res next to the pack's colour atlas. The animations and the rig are
## left behind, which keeps the repository small and the figurines cheap on the Low preset.

const OUT := "res://assets/kits/minis/"

## kind: [pack, file, animation, seconds into it, parts to keep (name contains)]
const MINIS := {
	"hero": ["adventurers", "Rogue_Hooded", "Idle", 0.4,
		["Rogue_Cape", "Rogue_ArmLeft", "Rogue_ArmRight", "Rogue_Body", "Rogue_Head_Hooded", "Rogue_LegLeft", "Rogue_LegRight"]],
	"smuggler": ["adventurers", "Rogue", "Idle", 0.4,
		["Rogue_Cape", "Rogue_ArmLeft", "Rogue_ArmRight", "Rogue_Body", "Rogue_Head", "Rogue_LegLeft", "Rogue_LegRight", "Knife"]],
	"innkeeper": ["adventurers", "Barbarian", "Idle", 0.4,
		["Barbarian_Cape", "Barbarian_ArmLeft", "Barbarian_ArmRight", "Barbarian_Body", "Barbarian_Head", "Barbarian_LegLeft", "Barbarian_LegRight", "Mug"]],
	"drowned": ["skeletons", "Skeleton_Minion", "Idle", 0.4,
		["Skeleton_Minion_ArmLeft", "Skeleton_Minion_ArmRight", "Skeleton_Minion_Body", "Skeleton_Minion_Cloak", "Skeleton_Minion_Eyes", "Skeleton_Minion_Head", "Skeleton_Minion_Jaw", "Skeleton_Minion_LegLeft", "Skeleton_Minion_LegRight"]],
	"abbess": ["skeletons", "Skeleton_Mage", "Idle", 0.4,
		["Skeleton_Mage_Hat", "Skeleton_Mage_ArmLeft", "Skeleton_Mage_ArmRight", "Skeleton_Mage_Body", "Skeleton_Mage_Eyes", "Skeleton_Mage_Jaw", "Skeleton_Mage_LegLeft", "Skeleton_Mage_LegRight", "Skeleton_Mage_Skull"]],
	"knight": ["adventurers", "Knight", "Idle", 0.4,
		["Knight_Helmet", "Knight_Cape", "Knight_ArmLeft", "Knight_ArmRight", "Knight_Body", "Knight_Head", "Knight_LegLeft", "Knight_LegRight", "1H_Sword", "Badge_Shield"]],
	"mage": ["adventurers", "Mage", "Idle", 0.4,
		["Mage_Hat", "Mage_Cape", "Mage_ArmLeft", "Mage_ArmRight", "Mage_Body", "Mage_Head", "Mage_LegLeft", "Mage_LegRight", "2H_Staff"]],
	"warrior": ["skeletons", "Skeleton_Warrior", "Idle", 0.4,
		["Skeleton_Warrior_Helmet", "Skeleton_Warrior_ArmLeft", "Skeleton_Warrior_ArmRight", "Skeleton_Warrior_Body", "Skeleton_Warrior_Cloak", "Skeleton_Warrior_Eyes", "Skeleton_Warrior_Head", "Skeleton_Warrior_Jaw", "Skeleton_Warrior_LegLeft", "Skeleton_Warrior_LegRight"]],
	"hooded": ["skeletons", "Skeleton_Rogue", "Idle", 0.4,
		["Skeleton_Rogue_Hood", "Skeleton_Rogue_Cape", "Skeleton_Rogue_ArmLeft", "Skeleton_Rogue_ArmRight", "Skeleton_Rogue_Body", "Skeleton_Rogue_Eyes", "Skeleton_Rogue_Head", "Skeleton_Rogue_Jaw", "Skeleton_Rogue_LegLeft", "Skeleton_Rogue_LegRight"]],
}

const PACKS := {
	"adventurers": "addons/kaykit_character_pack_adventures",
	"skeletons": "addons/kaykit_character_pack_skeletons",
}


func _init() -> void:
	var dirs := {}
	var only: Array = []
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--only="): only = Array(a.substr(7).split(","))
		if a.begins_with("--adventurers="): dirs["adventurers"] = a.substr(14)
		elif a.begins_with("--skeletons="): dirs["skeletons"] = a.substr(12)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	for kind in MINIS:
		var spec: Array = MINIS[kind]
		if not dirs.has(spec[0]) or (not only.is_empty() and not only.has(kind)):
			continue
		var base: String = dirs[spec[0]].path_join(PACKS[spec[0]])
		await _bake(kind, base.path_join("Characters/gltf/%s.glb" % spec[1]), spec[2], spec[3], spec[4])
	for pack in dirs:
		var base: String = dirs[pack].path_join(PACKS[pack])
		var tex_dir := base.path_join("Textures")
		for f in DirAccess.get_files_at(tex_dir):
			if f in ["rogue_texture.png", "barbarian_texture.png", "skeleton_texture.png", "knight_texture.png", "mage_texture.png"]:
				DirAccess.copy_absolute(tex_dir.path_join(f), ProjectSettings.globalize_path(OUT + f))
		DirAccess.copy_absolute(dirs[pack].path_join("LICENSE.txt"), ProjectSettings.globalize_path(OUT + "License_%s.txt" % pack))
	quit()


func _bake(kind: String, path: String, anim: String, t: float, keep: Array) -> void:
	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	if doc.append_from_file(path, state) != OK:
		push_error("cannot read " + path)
		return
	var scene := doc.generate_scene(state)
	root.add_child(scene)
	var player: AnimationPlayer = scene.find_children("*", "AnimationPlayer", true, false)[0]
	player.play(anim)
	player.seek(t, true)
	player.pause()
	await process_frame
	await process_frame
	# One surface for the painted parts (they share one atlas), one for anything glowing.
	var st := {}
	for mi: MeshInstance3D in scene.find_children("*", "MeshInstance3D", true, false):
		var wanted := false
		for k in keep:
			if mi.name == k or String(mi.name).begins_with(k):
				wanted = true
		if not wanted:
			continue
		var mesh: Mesh = mi.mesh
		var xf := mi.global_transform
		if mi.skin != null:
			mesh = _skin(mi)
			xf = Transform3D.IDENTITY
		for s in mesh.get_surface_count():
			var mat := mi.get_active_material(s)
			var glow := mat != null and String(mat.resource_name).to_lower().contains("glow")
			var key := "glow" if glow else "paint"
			if not st.has(key):
				st[key] = SurfaceTool.new()
				st[key].begin(Mesh.PRIMITIVE_TRIANGLES)
			st[key].append_from(mesh, s, xf)
	var out := ArrayMesh.new()
	for key in ["paint", "glow"]:
		if st.has(key):
			var s: SurfaceTool = st[key]
			s.index()
			s.commit(out)
			out.surface_set_name(out.get_surface_count() - 1, key)
			out.surface_set_material(out.get_surface_count() - 1, null)   # painted at load (scripts/kits.gd)
	out.resource_name = kind
	var err := ResourceSaver.save(out, OUT + kind + ".res", ResourceSaver.FLAG_COMPRESS)
	print("baked %s from %s: %d surfaces, aabb %s (%s)" % [kind, path.get_file(), out.get_surface_count(), out.get_aabb(), error_string(err)])
	scene.queue_free()


## Skin a mesh on the CPU in its current pose, into world space.
func _skin(mi: MeshInstance3D) -> ArrayMesh:
	var skel: Skeleton3D = mi.get_node(mi.skeleton)
	var skin: Skin = mi.skin
	var mats: Array[Transform3D] = []
	for i in skin.get_bind_count():
		var bone := skin.get_bind_bone(i)
		if bone < 0:
			bone = skel.find_bone(skin.get_bind_name(i))
		mats.append(skel.global_transform * skel.get_bone_global_pose(bone) * skin.get_bind_pose(i))
	var out := ArrayMesh.new()
	for s in mi.mesh.get_surface_count():
		var arr: Array = mi.mesh.surface_get_arrays(s)
		var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var n: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
		var bones: PackedInt32Array = arr[Mesh.ARRAY_BONES]
		var weights: PackedFloat32Array = arr[Mesh.ARRAY_WEIGHTS]
		var per := bones.size() / v.size()
		for i in v.size():
			var p := Vector3.ZERO
			var nn := Vector3.ZERO
			for j in per:
				var w := weights[i * per + j]
				if w <= 0.0:
					continue
				var m := mats[bones[i * per + j]]
				p += (m * v[i]) * w
				nn += (m.basis * n[i]) * w
			v[i] = p
			n[i] = nn.normalized()
		arr[Mesh.ARRAY_VERTEX] = v
		arr[Mesh.ARRAY_NORMAL] = n
		arr[Mesh.ARRAY_BONES] = null
		arr[Mesh.ARRAY_WEIGHTS] = null
		arr[Mesh.ARRAY_TANGENT] = null
		out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
		out.surface_set_material(s, mi.get_active_material(s))
	return out
