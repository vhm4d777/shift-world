extends SceneTree
## Writes the Godot Engine license and its third-party notices to a text file.
## godot --headless -s res://tools/dump_licenses.gd -- <output_file>

func _initialize() -> void:
	var path: String = OS.get_cmdline_user_args()[0]
	var t := "THIRD-PARTY LICENSES\n====================\n\n"
	t += "SHIFT WORLDS is built with the Godot Engine (https://godotengine.org).\n\n"
	t += "-------------------------------------------------------------------\nGodot Engine\n-------------------------------------------------------------------\n"
	t += Engine.get_license_text() + "\n\n"
	t += "-------------------------------------------------------------------\nComponents included in the Godot Engine\n-------------------------------------------------------------------\n\n"
	for info in Engine.get_copyright_info():
		t += "- " + info["name"] + "\n"
		for part in info["parts"]:
			for c in part["copyright"]:
				t += "    (c) " + c + "\n"
			t += "    License: " + part["license"] + "\n"
		t += "\n"
	t += "-------------------------------------------------------------------\nLicense texts\n-------------------------------------------------------------------\n\n"
	var lic: Dictionary = Engine.get_license_info()
	for k in lic.keys():
		t += "=== " + k + " ===\n" + lic[k] + "\n\n"
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(t)
	f.close()
	quit()
