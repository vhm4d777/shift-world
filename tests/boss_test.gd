extends SceneTree
## Boss fight smoke test: a simple bot fights every boss with each weapon tier.
## Pass 1 (invincible): the boss must be defeatable and the fight must end.
## Pass 2 (mortal, default pistol): reports how much damage the bot takes, as a
## rough difficulty curve. godot --headless -s res://tests/boss_test.gd

func _init() -> void:
	var ok := true
	for b in 11:
		var stage := b * 11 + 10
		for wi in [0, 3, 6]:
			var r := fight(stage, Game_weapon(wi), true)
			print("boss %2d %-16s weapon %-13s %s  time %5.1fs  hits taken %d" % [b + 1, Levels.get_level(stage)["name"], Game_weapon(wi)["name"], "WON " if r[0] else "FAIL", r[1], r[2]])
			if not r[0]:
				ok = false
		var m := fight(stage, Game_weapon(0), false)
		print("         mortal bot with pistol: %s after %.1fs" % ["won" if m[0] else "died", m[1]])
	print("BOSSES OK" if ok else "BOSS FAILURES")
	quit(0 if ok else 1)


func Game_weapon(i: int) -> Dictionary:
	# game.gd is an autoload and not available to -s scripts; read its constant directly
	return load("res://scripts/game.gd").WEAPONS[i]


## Returns [won, seconds, hits taken].
func fight(stage: int, weapon: Dictionary, invincible: bool) -> Array:
	var s := Sim.new()
	s.weapon = weapon
	s.load_level(stage)
	s.invincible = invincible
	var hits := 0
	var hp := s.player_hp
	var dir := 1
	var jump_t := 0
	for frame in 60 * 300:
		var b := s.boss
		# dodge: stay under the boss but keep moving, shift when a projectile is close
		var tx := b.x + (60.0 if (frame / 120) % 2 == 0 else -60.0)
		dir = 1 if tx > s.px + 5 else -1
		var danger := false
		for bl in b.bullets:
			if Vector2(bl["x"], bl["y"]).distance_to(Vector2(s.px + 5, s.py + 7)) < 22.0 and (bl["w"] == s.world):
				danger = true
		for l in b.lasers:
			if l["t"] > l["warn"] - 0.15 and absf(l["y"] - (s.py + 7)) < 12.0 and l["w"] == s.world:
				danger = true
		jump_t -= 1
		var jump := false
		for wv in b.waves:
			if absf(wv["x"] - (s.px + 5)) < 40.0:
				jump = true
		if jump and jump_t <= 0:
			jump_t = 30
		s.step({"left": dir < 0, "right": dir > 0, "jump_pressed": jump_t == 29, "jump_held": jump_t > 10,
			"shift_pressed": danger, "fire": true})
		if invincible:
			pass
		elif s.player_hp < hp:
			hits += hp - s.player_hp
		hp = s.player_hp
		if s.events.size() > 0:
			for e in s.events:
				if e[0] == "hurt":
					hits += 1 if invincible else 0
		if s.won:
			return [true, s.time, hits]
		if s.dead:
			return [false, s.time, hits]
	return [false, s.time, hits]
