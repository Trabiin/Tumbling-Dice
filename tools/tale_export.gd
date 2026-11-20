extends SceneTree
## Converts a tale written as GDScript data into a .tale file.
##   godot --headless -s res://tools/tale_export.gd -- res://path/to/tale.gd res://tales/out.tale

const Writer := preload("res://scripts/rules/tale_writer.gd")


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() < 2:
		print("usage: -- <tale.gd> <out.tale>")
		quit(1)
		return
	var src = load(args[0])
	var text := Writer.write(src.tale())
	var f := FileAccess.open(args[1], FileAccess.WRITE)
	f.store_string(text)
	f.close()
	print("wrote ", args[1], " (", text.length(), " chars)")
	quit(0)
