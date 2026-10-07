extends Control

signal round_started(client_match_id: String, game_version: String, protocol_version: int)
signal round_finished(client_match_id: String, final_score: int, game_version: String, protocol_version: int, match_session_id: String)

const ONLINE_CONTRACT = preload("res://scripts/online_contract.gd")

# -----------------------------------------------------------------------------
# GLINT RUSH — first playable slice. All game tuning lives in this block.
# -----------------------------------------------------------------------------
const CONFIG := {
	"ROUND_SECONDS": 60.0,
	"ROWS": 8,
	"COLS": 8,
	"GEM_TYPES": 6,
	"POINTS_PER_GEM": 100,
	"SPECIAL_CREATE_BONUS": 500,
	"SPECIAL_ACTIVATE_BONUS": 500,
	"PRISM_ACTIVATE_BONUS": 800,
	"PRISM_PAIR_BONUS": 2500,
	"CROSS_ACTIVATE_BONUS": 900,
	"CHAIN_SCORE_CAP": 8,
	"SWAP_TIME": 0.10,
	"CLEAR_TIME": 0.165,
	"FALL_BASE": 0.035,
	"FALL_PER_SQRT_ROW": 0.105,
	"FALL_MAX": 0.34,
	"CLEAR_STAGGER": 0.006,
	"SHAKE_CAP": 22.0,
	"GEM_GLOW": 0.11,
	"IDLE_GLINT_INTERVAL": Vector2(0.45, 0.95),
	"HUD_ENTRY_TIME": 0.42,
	# Manual-match SPEED streak tuning. Cascade waves never increment this streak.
	"SPEED_WINDOW_SEC": 2.25,
	"SPEED_MULTIPLIERS": [1, 1, 2, 2, 3, 3, 4, 4, 5],
	"SPEED_PITCH_SEMITONES": [0, 2, 4, 7, 9, 12, 14, 16, 19, 21, 24],
	"SPEED_GLOW_PER_MATCH": 0.13,
	"SPEED_GLOW_MAX": 0.95,
	"SPEED_DECAY_SEC": 0.24,
	"SPEED_SCORE_POP": 0.09,
	"SPEED_PARTICLE_BONUS": 0.24,
	"SPEED_SHIMMER_START": 3,
	"SPEED_HARMONY_START": 6,
	"SPEED_SHIMMER_DB": -10.0,
	"SPEED_HARMONY_DB": -15.0,
	"SPEED_HARMONY_INTERVAL": 7,
	"SFX_MATCH_DB": -2.0,
	"SFX_CREATE_DB": 0.0,
	"SFX_SPECIAL_DB": -1.0,
	"SFX_CROSS_DB": 0.0,
	"SFX_PRISM_DB": 0.0,
	"SFX_PRISM_PAIR_DB": 2.0,
	"SFX_PRISM_TRANSFORM_DB": -1.0,
	"SFX_FINAL_WARNING_DB": -1.0,
	"SFX_FINAL_DB": -2.0,
	"SPECIAL_SHAKE_BASE": 5.0,
	"SPECIAL_SHAKE_PER_WAVE": 1.7,
	"FINAL_SHAKE": 4.5,
	"SFX_PITCH_MAX": 4.0,
	"SFX_POLYPHONY": 12,
	"FINAL_BLAST_TEXT": "FINAL BLAST!",
	"FINAL_ZERO_PAUSE_SEC": 0.20,
	"FINAL_NO_SPECIAL_DELAY_SEC": 0.24,
	"FINAL_SPECIAL_DELAY_SEC": 0.11,
	"FINAL_MAX_WAVES": 96,
	"PRISM_TRANSFORM_SEC": 0.30,
	"MUSIC_BASE_DB": -21.0,
	"MUSIC_URGENT_DB": -18.5,
	"TIMEBAR_HEIGHT": 12.0,
	"COUNTDOWN_STEP_SEC": 0.76,
	"COUNTDOWN_GO_SEC": 0.52,
	"COUNTDOWN_FONT_SIZE": 136,
	"LOCAL_RIVALS": [
		{"name": "NOVA", "finish_score": 21800, "pace": 1.08},
		{"name": "LUNA", "finish_score": 17900, "pace": 1.0},
		{"name": "BYTE", "finish_score": 14200, "pace": 0.92},
	],
	"MENU_GLOW": 0.18,
	"HAPTICS_ENABLED": true,
	"SOUND_ENABLED": true,
}

var GEM_COLORS := PackedColorArray([
	Color("ff3d71"), Color("27c5ff"), Color("57f56b"),
	Color("ffd43b"), Color("d75cff"), Color("ff8646")
])
const GEM_NAMES := ["RUBÍ", "ZAFIRO", "ESMERALDA", "CITRINO", "AMATISTA", "ÓPALO"]
const GEM_SPRITE_INDEX := [0, 2, 1, 4, 3, 5]
const SFX := {
	"swap": "res://assets/sfx/swap.wav",
	"match": "res://assets/sfx/match.wav",
	"special_create": "res://assets/sfx/special_create.wav",
	"special": "res://assets/sfx/special.wav",
	"prism": "res://assets/sfx/prism.wav",
	"prism_pair": "res://assets/sfx/prism_pair.wav",
	"bomb": "res://assets/sfx/bomb.wav",
	"cross": "res://assets/sfx/cross.wav",
	"cross_create": "res://assets/sfx/cross_create.wav",
	"prism_charge": "res://assets/sfx/prism_charge.wav",
	"prism_transform": "res://assets/sfx/prism_transform.wav",
	"final_warning": "res://assets/sfx/final_warning.wav",
	"final_blast": "res://assets/sfx/final_blast.wav",
	"speed_shimmer": "res://assets/sfx/speed_shimmer.wav",
	"speed_harmony": "res://assets/sfx/speed_harmony.wav",
	"cascade": "res://assets/sfx/cascade.wav",
	"countdown": "res://assets/sfx/countdown.wav",
	"start_go": "res://assets/sfx/start_go.wav",
	"finish": "res://assets/sfx/finish.wav",
}

var board: Array = []
var specials: Dictionary = {} # "row * COLS + col" -> line_h, line_v, cross, prism
var game_state := "title"
var selected := Vector2i(-1, -1)
var pointer_down := false
var pointer_origin := Vector2.ZERO
var pointer_cell := Vector2i(-1, -1)
var input_locked := false
var resolving := false
var timed_out := false
var final_blast_active := false
var final_blast_started := false
var final_blast_age := 10.0
var deadline_msec := 0
var seconds_left := 60.0
var countdown_label := ""
var countdown_started_msec := 0
var countdown_next_msec := 0
var countdown_label_started_msec := 0
var countdown_label_duration := 0.0
var go_flash_started_msec := -1
var score := 0
var best_score := 0
var client_match_id := ""
var match_session_id := ""
var speed_streak := 0
var speed_multiplier := 1
var speed_pitch_semitones := 0
var speed_last_match_msec := -1
var speed_intensity := 0.0
var speed_pulse := 0.0
var score_pop := 0.0
var chain_count := 0
var visual_chain := 0
var swap_visual_active := false
var swap_visual_progress := 1.0
var swap_visual_a := Vector2i(-1, -1)
var swap_visual_b := Vector2i(-1, -1)
var last_move_cell := Vector2i(-1, -1)
var shake_strength := 0.0
var shake_offset := Vector2.ZERO
var flash_alpha := 0.0
var clear_visuals: Dictionary = {}
var fall_visuals: Dictionary = {}
var special_visuals: Array[Dictionary] = []
var creation_visuals: Array[Dictionary] = []
var combo_banner := ""
var combo_banner_age := 10.0
var last_clock_second := 60
var particles: Array[Dictionary] = []
var floaters: Array[Dictionary] = []
var stars: Array[Dictionary] = []
var idle_glints: Array[Dictionary] = []
var idle_glint_timer := 0.4
var hud_age := 10.0
var transition_alpha := 0.0
var record_beaten := false
var ui_board_style: StyleBoxFlat
var ui_cabinet_style: StyleBoxFlat
var ui_hud_style: StyleBoxFlat
var ui_button_style: StyleBoxFlat
var gem_atlas: Texture2D
var prism_texture: Texture2D
var background_textures: Array[Texture2D] = []
var active_background_index := 0
var sfx_players: Array[AudioStreamPlayer] = []
var sfx_cursor := 0
var music_player: AudioStreamPlayer
var title_button_rect := Rect2()
var again_button_rect := Rect2()
var button_pressed := false


func _ready() -> void:
	round_started.connect(OnlineService.on_round_started)
	round_finished.connect(OnlineService.on_round_finished)
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_ALL
	_make_stars()
	_make_ui_styles()
	gem_atlas = load("res://assets/gems/gem_atlas.png")
	prism_texture = load("res://assets/gems/prism_core.png")
	for path in ["res://assets/backgrounds/crystal_valley.jpg", "res://assets/backgrounds/sky_observatory.jpg", "res://assets/backgrounds/prism_gorge.jpg"]:
		var background: Texture2D = load(path)
		if background != null:
			background_textures.append(background)
	for i in range(int(CONFIG["SFX_POLYPHONY"])):
		var player := AudioStreamPlayer.new()
		add_child(player)
		sfx_players.append(player)
	music_player = AudioStreamPlayer.new()
	music_player.volume_db = float(CONFIG["MUSIC_BASE_DB"])
	add_child(music_player)
	var music_stream: AudioStreamWAV = load("res://assets/sfx/arcade_loop.wav")
	music_stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	music_stream.loop_end = music_stream.data.size() / 2
	music_player.stream = music_stream
	best_score = _load_best()
	set_process(true)
	queue_redraw()


func _process(delta: float) -> void:
	hud_age += delta
	transition_alpha = move_toward(transition_alpha, 0.0, delta * 3.4)
	idle_glint_timer -= delta
	if (game_state == "playing" or game_state == "countdown") and idle_glint_timer <= 0.0 and idle_glints.size() < 2:
		idle_glint_timer = randf_range(float(CONFIG["IDLE_GLINT_INTERVAL"].x), float(CONFIG["IDLE_GLINT_INTERVAL"].y))
		var glint_cell := Vector2i(randi_range(0, int(CONFIG["COLS"]) - 1), randi_range(0, int(CONFIG["ROWS"]) - 1))
		if not board.is_empty() and int(board[glint_cell.y][glint_cell.x]) >= 0:
			idle_glints.append({"cell": glint_cell, "age": 0.0, "kind": randi_range(0, 2)})
	for i in range(idle_glints.size() - 1, -1, -1):
		idle_glints[i]["age"] = float(idle_glints[i]["age"]) + delta
		if float(idle_glints[i]["age"]) > 0.38:
			idle_glints.remove_at(i)
	_advance_countdown(Time.get_ticks_msec())
	if game_state == "playing" and not timed_out:
		seconds_left = maxf(0.0, float(deadline_msec - Time.get_ticks_msec()) / 1000.0)
		var clock_second := int(ceil(seconds_left))
		if clock_second < last_clock_second and clock_second <= 10 and clock_second > 0:
			_play_sfx("countdown", 0.92 + (10 - clock_second) * 0.035, -4.0)
			if clock_second <= 5:
				_vibrate(14 if clock_second > 2 else 24)
		last_clock_second = clock_second
		if seconds_left <= 0.0:
			timed_out = true
			input_locked = true
			if not resolving:
				_begin_final_blast()
	if final_blast_active:
		final_blast_age += delta
	if game_state == "playing":
		_update_speed_state(delta, Time.get_ticks_msec())
		var urgent_mix := 1.0 - clampf(seconds_left / 10.0, 0.0, 1.0)
		var desired_music_db := lerpf(float(CONFIG["MUSIC_BASE_DB"]), float(CONFIG["MUSIC_URGENT_DB"]), urgent_mix)
		music_player.volume_db = move_toward(music_player.volume_db, desired_music_db, delta * 3.0)
	speed_pulse = move_toward(speed_pulse, 0.0, delta * 4.2)
	score_pop = move_toward(score_pop, 0.0, delta * 5.0)
	for i in range(particles.size() - 1, -1, -1):
		var p := particles[i]
		p["life"] = float(p["life"]) - delta
		p["pos"] = Vector2(p["pos"]) + Vector2(p["vel"]) * delta
		p["vel"] = Vector2(p["vel"]) * (1.0 - delta * 1.8) + Vector2(0, 95.0 * delta)
		particles[i] = p
		if float(p["life"]) <= 0.0:
			particles.remove_at(i)
	for i in range(floaters.size() - 1, -1, -1):
		var f := floaters[i]
		f["age"] = float(f.get("age", 0.0)) + delta
		f["life"] = float(f["life"]) - delta
		f["pos"] = Vector2(f["pos"]) + Vector2(0, -42.0 * delta)
		floaters[i] = f
		if float(f["life"]) <= 0.0:
			floaters.remove_at(i)
	shake_strength = move_toward(shake_strength, 0.0, delta * 28.0)
	flash_alpha = move_toward(flash_alpha, 0.0, delta * 2.4)
	combo_banner_age += delta
	for i in range(creation_visuals.size() - 1, -1, -1):
		creation_visuals[i]["age"] = float(creation_visuals[i]["age"]) + delta
		if float(creation_visuals[i]["age"]) > 0.55:
			creation_visuals.remove_at(i)
	shake_offset = Vector2(randf_range(-shake_strength, shake_strength), randf_range(-shake_strength, shake_strength)) if shake_strength > 0.5 else Vector2.ZERO
	queue_redraw()


func _draw() -> void:
	_draw_background()
	if game_state == "title":
		_draw_title()
	elif game_state == "playing" or game_state == "countdown":
		_draw_hud()
		_draw_board()
		_draw_timebar()
		_draw_effects()
		_draw_game_footer()
		_draw_countdown_overlay()
		_draw_final_blast_overlay()
	elif game_state == "result":
		_draw_result()
	if transition_alpha > 0.01:
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.64, 0.91, 1.0, transition_alpha * 0.24))


func _gui_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		if event.pressed:
			_pointer_start(event.position)
		else:
			_pointer_end(event.position)
		accept_event()
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_pointer_start(event.position)
		else:
			_pointer_end(event.position)
		accept_event()
	elif event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		if game_state == "playing" and not resolving:
			get_viewport().set_input_as_handled()


func _pointer_start(pos: Vector2) -> void:
	pointer_down = true
	pointer_origin = pos
	pointer_cell = _cell_at(pos)
	button_pressed = (game_state == "title" and title_button_rect.has_point(pos)) or (game_state == "result" and again_button_rect.has_point(pos))
	queue_redraw()


func _pointer_end(pos: Vector2) -> void:
	if not pointer_down:
		return
	pointer_down = false
	button_pressed = false
	if game_state == "title":
		if title_button_rect.has_point(pos):
			_start_game()
		return
	if game_state == "result":
		if again_button_rect.has_point(pos):
			_start_game()
		return
	if game_state != "playing" or input_locked or timed_out:
		return
	var target := _cell_at(pos)
	if pointer_cell.x < 0:
		return
	if target.x >= 0 and target != pointer_cell and _manhattan(pointer_cell, target) == 1:
		_attempt_swap(pointer_cell, target)
	elif pos.distance_to(pointer_origin) < 24.0:
		_handle_tap(pointer_cell)
	elif target.x < 0:
		selected = Vector2i(-1, -1)
		queue_redraw()


func _handle_tap(cell: Vector2i) -> void:
	if selected.x < 0:
		selected = cell
	elif selected == cell:
		selected = Vector2i(-1, -1)
	else:
		if _manhattan(selected, cell) == 1:
			_attempt_swap(selected, cell)
		else:
			selected = cell
	queue_redraw()


func _attempt_swap(a: Vector2i, b: Vector2i) -> void:
	if resolving or input_locked:
		return
	selected = Vector2i(-1, -1)
	_swap_cells(a, b)
	var both_prisms := _special_at(a) == "prism" and _special_at(b) == "prism"
	var prism_pair := _special_at(a) == "prism" or _special_at(b) == "prism"
	var valid := both_prisms or prism_pair or not _find_groups().is_empty()
	if not valid:
		resolving = true
		input_locked = true
		_play_sfx("swap")
		_begin_swap_visual(a, b, true)
		queue_redraw()
		return
	_register_speed_match(Time.get_ticks_msec())
	resolving = true
	input_locked = true
	_begin_swap_visual(a, b)
	last_move_cell = b
	chain_count = 0
	_play_sfx("swap")
	_run_resolution(a, b)


func _run_resolution(a: Vector2i, b: Vector2i) -> void:
	await get_tree().create_timer(float(CONFIG["SWAP_TIME"])).timeout
	var start_kind := ""
	var prism_color := -1
	var clear_all := false
	var transform_kind := ""
	var sa := _special_at(a)
	var sb := _special_at(b)
	if sa == "prism" and sb == "prism":
		start_kind = "pair"
		clear_all = true
	elif sa == "prism":
		start_kind = "prism_transform" if _is_transformable_special(sb) else "prism"
		transform_kind = sb if start_kind == "prism_transform" else ""
		prism_color = board[b.y][b.x]
	elif sb == "prism":
		start_kind = "prism_transform" if _is_transformable_special(sa) else "prism"
		transform_kind = sa if start_kind == "prism_transform" else ""
		prism_color = board[a.y][a.x]
	await _resolve_board(start_kind, [a, b], prism_color, clear_all, transform_kind)
	resolving = false
	input_locked = false
	if timed_out:
		_begin_final_blast()
	else:
		_ensure_playable_board()
	queue_redraw()


func _advance_countdown(now_msec: int) -> void:
	if game_state == "countdown" and now_msec >= countdown_next_msec:
		if countdown_label == "3":
			_set_countdown_label("2", float(CONFIG["COUNTDOWN_STEP_SEC"]), now_msec)
			_play_sfx("countdown", 1.02, -5.0)
		elif countdown_label == "2":
			_set_countdown_label("1", float(CONFIG["COUNTDOWN_STEP_SEC"]), now_msec)
			_play_sfx("countdown", 1.14, -4.0)
		else:
			_set_countdown_label("¡YA!", float(CONFIG["COUNTDOWN_GO_SEC"]), now_msec)
			game_state = "playing"
			input_locked = false
			timed_out = false
			seconds_left = float(CONFIG["ROUND_SECONDS"])
			last_clock_second = int(CONFIG["ROUND_SECONDS"])
			deadline_msec = now_msec + int(float(CONFIG["ROUND_SECONDS"]) * 1000.0)
			go_flash_started_msec = now_msec
			_play_sfx("start_go", 1.0, -1.0)
			_vibrate(18)
			if bool(CONFIG["SOUND_ENABLED"]) and OS.get_environment("GLINT_RUSH_TEST") != "1":
				music_player.volume_db = float(CONFIG["MUSIC_BASE_DB"])
				music_player.play()
	elif game_state == "playing" and countdown_label == "¡YA!" and now_msec >= countdown_next_msec:
		countdown_label = ""
	queue_redraw()


func _set_countdown_label(label: String, duration_sec: float, now_msec := -1) -> void:
	countdown_label = label
	countdown_label_started_msec = Time.get_ticks_msec() if now_msec < 0 else now_msec
	countdown_label_duration = duration_sec
	countdown_next_msec = countdown_label_started_msec + int(duration_sec * 1000.0)
	if label == "3":
		_play_sfx("countdown", 0.91, -6.0)


func _register_speed_match(now_msec: int) -> void:
	var within_window := speed_streak > 0 and speed_last_match_msec >= 0 and float(now_msec - speed_last_match_msec) <= float(CONFIG["SPEED_WINDOW_SEC"]) * 1000.0
	speed_streak = speed_streak + 1 if within_window else 1
	speed_last_match_msec = now_msec
	speed_multiplier = _speed_multiplier_for_streak(speed_streak)
	speed_pitch_semitones = _speed_pitch_for_streak(speed_streak)
	speed_intensity = maxf(speed_intensity, _speed_glow_for_streak(speed_streak))
	speed_pulse = 1.0
	queue_redraw()


func _speed_multiplier_for_streak(streak: int) -> int:
	var steps: Array = CONFIG["SPEED_MULTIPLIERS"]
	return int(steps[clampi(streak - 1, 0, steps.size() - 1)]) if not steps.is_empty() else 1


func _speed_pitch_for_streak(streak: int) -> int:
	var steps: Array = CONFIG["SPEED_PITCH_SEMITONES"]
	return int(steps[clampi(streak - 1, 0, steps.size() - 1)]) if not steps.is_empty() else 0


func _speed_glow_for_streak(streak: int) -> float:
	return clampf(0.20 + float(maxi(streak - 1, 0)) * float(CONFIG["SPEED_GLOW_PER_MATCH"]), 0.20, float(CONFIG["SPEED_GLOW_MAX"]))


func _update_speed_state(delta: float, now_msec: int) -> void:
	if speed_streak > 0 and speed_last_match_msec >= 0:
		if float(now_msec - speed_last_match_msec) > float(CONFIG["SPEED_WINDOW_SEC"]) * 1000.0:
			speed_streak = 0
			speed_multiplier = 1
			speed_pitch_semitones = 0
			speed_last_match_msec = -1
	speed_intensity = move_toward(speed_intensity, 0.0, delta / maxf(float(CONFIG["SPEED_DECAY_SEC"]), 0.01))


func _speed_window_remaining(now_msec: int) -> float:
	if speed_streak <= 0 or speed_last_match_msec < 0:
		return 0.0
	return clampf(1.0 - float(now_msec - speed_last_match_msec) / (float(CONFIG["SPEED_WINDOW_SEC"]) * 1000.0), 0.0, 1.0)


func _play_speed_match() -> void:
	var pitch_ratio := pow(2.0, float(speed_pitch_semitones) / 12.0)
	_play_sfx("match", pitch_ratio, float(CONFIG["SFX_MATCH_DB"]))
	if speed_streak >= int(CONFIG["SPEED_SHIMMER_START"]):
		var shimmer_db := float(CONFIG["SPEED_SHIMMER_DB"]) + minf(float(speed_streak - int(CONFIG["SPEED_SHIMMER_START"])) * 0.45, 3.0)
		_play_sfx("speed_shimmer", pitch_ratio, shimmer_db)
	if speed_streak >= int(CONFIG["SPEED_HARMONY_START"]):
		var interval := int(CONFIG["SPEED_HARMONY_INTERVAL"])
		var harmony_db := float(CONFIG["SPEED_HARMONY_DB"]) + minf(float(speed_streak - int(CONFIG["SPEED_HARMONY_START"])) * 0.25, 2.0)
		_play_sfx("speed_harmony", pitch_ratio * pow(2.0, float(interval) / 12.0), harmony_db)


func _resolve_board(start_kind: String, start_cells: Array, prism_color: int, clear_all: bool, transform_kind := "") -> void:
	var wave_index := 0
	var forced_kind := start_kind
	while wave_index < 100:
		var groups := _find_groups()
		var base_clear: Dictionary = {}
		var created: Array[Dictionary] = []
		for group in groups:
			var special_data := _special_for_group(group)
			var keep_cell: Vector2i = special_data.get("cell", Vector2i(-1, -1))
			if str(special_data.get("type", "")) != "":
				created.append({"cell": keep_cell, "type": special_data["type"]})
			for c in group["cells"]:
				if c != keep_cell:
					base_clear[_key(c)] = c
				else:
					# Preserve the chosen new special cell from the match removal.
					pass
		var seeds: Array = []
		if wave_index == 0:
			if forced_kind == "pair":
				base_clear.clear()
				for c in start_cells:
					seeds.append(c)
			elif forced_kind == "prism":
				for y in range(int(CONFIG["ROWS"])):
					for x in range(int(CONFIG["COLS"])):
						if int(board[y][x]) == prism_color:
							base_clear[_key(Vector2i(x, y))] = Vector2i(x, y)
				for c in start_cells:
					if _special_at(c) == "prism":
						seeds.append(c)
			elif forced_kind == "prism_transform":
				# Deterministic row-major conversion keeps seeded replays reproducible.
				for c in start_cells:
					if _special_at(c) == "prism":
						seeds.append(c)
				seeds.append_array(_transform_prism_targets(prism_color, transform_kind))
			elif forced_kind == "final":
				seeds.append_array(start_cells)
		for k in base_clear.keys():
			var cell: Vector2i = base_clear[k]
			if _special_at(cell) != "":
				seeds.append(cell)
		if groups.is_empty() and seeds.is_empty() and forced_kind == "":
			break
		var effects := _collect_special_effects(base_clear, seeds, prism_color, clear_all if wave_index == 0 else false, transform_kind if wave_index == 0 else "")
		var cleared: Dictionary = effects["clear"]
		var activated: int = effects["activated"]
		for created_data in created:
			var created_cell: Vector2i = created_data["cell"]
			specials[_key(created_cell)] = created_data["type"]
		if cleared.is_empty():
			break
		wave_index += 1
		chain_count = wave_index
		visual_chain = maxi(visual_chain, wave_index)
		var clear_cells: Array = []
		for k in cleared.keys():
			clear_cells.append(cleared[k])
		if wave_index > 1:
			combo_banner = "COMBO x" + str(wave_index)
			combo_banner_age = 0.0
			_float_text(combo_banner, Vector2(size.x * 0.5, size.y * 0.28), _chain_color(wave_index), true)
		if wave_index >= 3:
			flash_alpha = minf(0.10 + wave_index * 0.025, 0.42)
		for created_data in created:
			creation_visuals.append({"cell": created_data["cell"], "type": created_data["type"], "age": 0.0})
		if activated > 0 or forced_kind == "pair":
			shake_strength = minf(float(CONFIG["SPECIAL_SHAKE_BASE"]) + wave_index * float(CONFIG["SPECIAL_SHAKE_PER_WAVE"]), float(CONFIG["SHAKE_CAP"]))
			if forced_kind == "pair":
				_play_sfx("prism_pair", 0.92 + minf(wave_index * 0.04, 0.5), float(CONFIG["SFX_PRISM_PAIR_DB"]))
			elif forced_kind == "prism_transform":
				_play_sfx("prism_charge", 0.94, 0.0)
				_play_sfx_after("prism_transform", 0.12, 0.96, float(CONFIG["SFX_PRISM_TRANSFORM_DB"]))
			elif forced_kind == "prism":
				_play_sfx("prism", 1.0 + minf(wave_index * 0.045, 0.45), float(CONFIG["SFX_PRISM_DB"]))
			elif effects.get("cross_count", 0) > 0:
				_play_sfx("cross", 1.0 + minf(wave_index * 0.035, 0.35), float(CONFIG["SFX_CROSS_DB"]))
			elif _has_event_kind(effects.get("events", []), "bomb"):
				_play_sfx("bomb", 1.0 + minf(wave_index * 0.04, 0.4), 0.0)
			else:
				_play_sfx("special", 1.0 + minf(wave_index * 0.04, 0.4), float(CONFIG["SFX_SPECIAL_DB"]))
			_vibrate(mini(38 + wave_index * 10, 110))
		elif not created.is_empty():
			_play_sfx("special_create" if str(created[0]["type"]) != "cross" else "cross_create", 1.0 + minf(wave_index * 0.03, 0.3), float(CONFIG["SFX_CREATE_DB"]))
			_vibrate(32)
		else:
			if wave_index > 1 or final_blast_active:
				_play_sfx("cascade", 1.0 + minf(wave_index * 0.055, 0.7), -2.0 + minf(wave_index * 0.4, 2.0))
			_vibrate(mini(18 + wave_index * 4, 45))
		if wave_index == 1 and not final_blast_active:
			_play_speed_match()
		var speed_score_multiplier := speed_multiplier if wave_index == 1 and not final_blast_active else 1
		_score_wave(clear_cells.size(), groups, activated, wave_index, forced_kind == "pair" and wave_index == 1, clear_cells, speed_score_multiplier)
		var clear_duration := _animate_clear(clear_cells, effects.get("events", []), wave_index)
		_spawn_clear_fx(clear_cells, wave_index, speed_intensity)
		for c in clear_cells:
			specials.erase(_key(c))
		var fall_duration := _collapse_and_refill(cleared, wave_index)
		var phase_duration := maxf(clear_duration, fall_duration)
		if phase_duration > 0.0:
			await get_tree().create_timer(phase_duration).timeout
		fall_visuals.clear()
		clear_visuals.clear()
		special_visuals.clear()
		forced_kind = ""
		clear_all = false
		prism_color = -1
	if wave_index >= 100:
		# Defensive escape from an extraordinarily improbable endless refill cascade.
		_reshuffle_board()
	if wave_index == 1:
		chain_count = 0


func _collect_special_effects(base_clear: Dictionary, seeds: Array, prism_color: int, clear_all: bool, transform_kind := "") -> Dictionary:
	var clear: Dictionary = base_clear.duplicate()
	var queue: Array[Vector2i] = []
	var activated: Dictionary = {}
	var events: Array[Dictionary] = []
	var cross_count := 0
	for cell in clear.values():
		var c: Vector2i = cell
		if _special_at(c) != "":
			queue.append(c)
	for c in seeds:
		if _special_at(c) != "":
			queue.append(c)
	if clear_all:
		events.append({"kind": "prism_pair", "cell": Vector2i(-1, -1)})
		for y in range(int(CONFIG["ROWS"])):
			for x in range(int(CONFIG["COLS"])):
				_add_clear_cell(Vector2i(x, y), clear, queue)
	while not queue.is_empty():
		var origin: Vector2i = queue.pop_front()
		var k := _key(origin)
		var kind := _special_at(origin)
		if kind == "" or activated.has(k):
			continue
		activated[k] = true
		clear[k] = origin
		if kind == "line_h":
			events.append({"kind": kind, "cell": origin})
			for x in range(int(CONFIG["COLS"])):
				_add_clear_cell(Vector2i(x, origin.y), clear, queue)
		elif kind == "line_v":
			events.append({"kind": kind, "cell": origin})
			for y in range(int(CONFIG["ROWS"])):
				_add_clear_cell(Vector2i(origin.x, y), clear, queue)
		elif kind == "bomb":
			events.append({"kind": kind, "cell": origin})
			for y in range(maxi(0, origin.y - 1), mini(int(CONFIG["ROWS"]) - 1, origin.y + 1) + 1):
				for x in range(maxi(0, origin.x - 1), mini(int(CONFIG["COLS"]) - 1, origin.x + 1) + 1):
					_add_clear_cell(Vector2i(x, y), clear, queue)
		elif kind == "cross":
			cross_count += 1
			events.append({"kind": kind, "cell": origin})
			for x in range(int(CONFIG["COLS"])):
				_add_clear_cell(Vector2i(x, origin.y), clear, queue)
			for y in range(int(CONFIG["ROWS"])):
				_add_clear_cell(Vector2i(origin.x, y), clear, queue)
		elif kind == "prism":
			var target := prism_color
			if target < 0:
				target = int(board[origin.y][origin.x])
			var targets: Array[Vector2i] = []
			for y in range(int(CONFIG["ROWS"])):
				for x in range(int(CONFIG["COLS"])):
					if int(board[y][x]) == target:
						var target_cell := Vector2i(x, y)
						targets.append(target_cell)
						_add_clear_cell(target_cell, clear, queue)
			var prism_event_kind := "prism_transform" if transform_kind != "" else kind
			events.append({"kind": prism_event_kind, "cell": origin, "targets": targets, "transform_kind": transform_kind, "target_color": target})
	return {"clear": clear, "activated": activated.size(), "events": events, "cross_count": cross_count}


func _has_event_kind(events: Array, kind: String) -> bool:
	for event in events:
		if str(event.get("kind", "")) == kind:
			return true
	return false


func _add_clear_cell(cell: Vector2i, clear: Dictionary, queue: Array[Vector2i]) -> void:
	var k := _key(cell)
	if not clear.has(k):
		clear[k] = cell
	if _special_at(cell) != "":
		queue.append(cell)


func _score_wave(removed: int, groups: Array, activated: int, wave: int, prism_pair: bool, clear_cells: Array, speed_score_multiplier := 1) -> void:
	var group_bonus := 0
	for group in groups:
		var special_data := _special_for_group(group)
		if str(special_data.get("type", "")) != "":
			group_bonus += int(CONFIG["SPECIAL_CREATE_BONUS"])
	var special_bonus := activated * int(CONFIG["SPECIAL_ACTIVATE_BONUS"])
	var cross_count := 0
	for c in clear_cells:
		if _special_at(c) == "cross":
			cross_count += 1
	special_bonus += cross_count * int(CONFIG["CROSS_ACTIVATE_BONUS"])
	if prism_pair:
		special_bonus += int(CONFIG["PRISM_PAIR_BONUS"])
	elif activated > 0 and (groups.is_empty()):
		special_bonus += int(CONFIG["PRISM_ACTIVATE_BONUS"])
	var multiplier := mini(wave, int(CONFIG["CHAIN_SCORE_CAP"]))
	var gained := (removed * int(CONFIG["POINTS_PER_GEM"]) + group_bonus + special_bonus) * maxi(1, multiplier) * maxi(1, speed_score_multiplier)
	score += gained
	score_pop = 1.0 + float(CONFIG["SPEED_SCORE_POP"]) * float(maxi(speed_streak - 1, 0))
	if score > best_score:
		record_beaten = true
	if gained > 0:
		var anchor := _cells_center(clear_cells)
		var large := activated > 0 or prism_pair or wave >= 3
		_float_text("+" + _format_score(gained), anchor, _chain_color(wave), large)


func _find_groups() -> Array:
	var matched: Dictionary = {}
	var h_runs: Dictionary = {}
	var v_runs: Dictionary = {}
	for y in range(int(CONFIG["ROWS"])):
		var x := 0
		while x < int(CONFIG["COLS"]):
			var color := int(board[y][x])
			var end_x := x + 1
			while end_x < int(CONFIG["COLS"]) and int(board[y][end_x]) == color:
				end_x += 1
			if color >= 0 and end_x - x >= 3:
				for cx in range(x, end_x):
					var c := Vector2i(cx, y)
					matched[_key(c)] = color
					h_runs[_key(c)] = end_x - x
			x = end_x
	for x in range(int(CONFIG["COLS"])):
		var y := 0
		while y < int(CONFIG["ROWS"]):
			var color := int(board[y][x])
			var end_y := y + 1
			while end_y < int(CONFIG["ROWS"]) and int(board[end_y][x]) == color:
				end_y += 1
			if color >= 0 and end_y - y >= 3:
				for cy in range(y, end_y):
					var c := Vector2i(x, cy)
					matched[_key(c)] = color
					v_runs[_key(c)] = end_y - y
			y = end_y
	var groups: Array = []
	var visited: Dictionary = {}
	for key in matched.keys():
		if visited.has(key):
			continue
		# Recover the coordinate from the stable integer key.
		var stack: Array[Vector2i] = [_cell_from_key(str(key))]
		var cells: Array[Vector2i] = []
		var color_id: int = int(matched[key])
		var horizontal := 0
		var vertical := 0
		while not stack.is_empty():
			var c: Vector2i = stack.pop_back()
			var ck := _key(c)
			if visited.has(ck) or not matched.has(ck) or int(matched[ck]) != color_id:
				continue
			visited[ck] = true
			cells.append(c)
			horizontal = maxi(horizontal, int(h_runs.get(ck, 0)))
			vertical = maxi(vertical, int(v_runs.get(ck, 0)))
			for d in [Vector2i(1,0), Vector2i(-1,0), Vector2i(0,1), Vector2i(0,-1)]:
				var n: Vector2i = c + d
				if n.x >= 0 and n.y >= 0 and n.x < int(CONFIG["COLS"]) and n.y < int(CONFIG["ROWS"]):
					var nk := _key(n)
					if matched.has(nk) and int(matched[nk]) == color_id and not visited.has(nk):
						stack.append(n)
		groups.append({"cells": cells, "horizontal": horizontal, "vertical": vertical})
	return groups


func _special_for_group(group: Dictionary) -> Dictionary:
	var h: int = int(group["horizontal"])
	var v: int = int(group["vertical"])
	var kind := ""
	if h >= 5 or v >= 5:
		kind = "prism"
	elif h >= 3 and v >= 3:
		kind = "cross"
	elif h >= 4:
		kind = "line_h"
	elif v >= 4:
		kind = "line_v"
	if kind == "":
		return {"type": "", "cell": Vector2i(-1, -1)}
	var chosen := Vector2i(-1, -1)
	if last_move_cell.x >= 0 and group["cells"].has(last_move_cell):
		chosen = last_move_cell
	else:
		chosen = group["cells"][int(group["cells"].size() / 2)]
	return {"type": kind, "cell": chosen}


func _animate_clear(cells: Array, events: Array, wave: int) -> float:
	clear_visuals.clear()
	special_visuals.clear()
	var now := Time.get_ticks_msec()
	var longest_delay := 0.0
	var longest_event := 0.0
	var clear_duration := float(CONFIG["CLEAR_TIME"]) * _wave_motion_scale(wave)
	var transform_sequence := false
	for event in events:
		if str(event.get("kind", "")) == "prism_transform":
			transform_sequence = true
			break
	for i in range(events.size()):
		var visual: Dictionary = events[i].duplicate(true)
		var event_delay_ms := int(roundf(float(i) * float(CONFIG["FINAL_SPECIAL_DELAY_SEC"]) * 1000.0)) if final_blast_active else i * 18
		if transform_sequence and str(visual.get("kind", "")) != "prism_transform":
			event_delay_ms += int(float(CONFIG["PRISM_TRANSFORM_SEC"]) * 1000.0)
		visual["start_msec"] = now + event_delay_ms
		var base_event_ms := 210.0 if visual["kind"] == "prism_pair" else 180.0
		if visual["kind"] == "prism_transform":
			base_event_ms = float(CONFIG["PRISM_TRANSFORM_SEC"]) * 1000.0
		visual["duration_msec"] = int(base_event_ms * _wave_motion_scale(wave))
		longest_event = maxf(longest_event, float(event_delay_ms + int(visual["duration_msec"])) / 1000.0)
		special_visuals.append(visual)
	for cell in cells:
		var c: Vector2i = cell
		var delay := _clear_delay(c, events)
		longest_delay = maxf(longest_delay, delay)
		clear_visuals[_key(c)] = {
			"cell": c,
			"gem": int(board[c.y][c.x]),
			"special": _special_at(c),
			"start_msec": now + int(delay * 1000.0),
			"duration_msec": int(clear_duration * 1000.0),
			"wave": wave,
		}
	queue_redraw()
	return maxf(clear_duration + longest_delay, longest_event)


func _wave_motion_scale(wave: int) -> float:
	return maxf(0.72, 1.0 - float(maxi(wave - 1, 0)) * 0.045)


func _clear_delay(cell: Vector2i, events: Array) -> float:
	var delay := 0.0
	var final_event_found := false
	var transform_sequence := false
	for event in events:
		if str(event.get("kind", "")) == "prism_transform":
			transform_sequence = true
			break
	for event_index in range(events.size()):
		var event: Dictionary = events[event_index]
		var origin: Vector2i = event.get("cell", Vector2i(-1, -1))
		var kind := str(event["kind"])
		if final_blast_active:
			var affected := false
			if kind == "prism_pair":
				affected = true
			elif kind == "line_h":
				affected = cell.y == origin.y
			elif kind == "line_v":
				affected = cell.x == origin.x
			elif kind == "cross":
				affected = cell.y == origin.y or cell.x == origin.x
			elif kind == "prism" or kind == "prism_transform":
				affected = event.get("targets", []).has(cell)
			elif kind == "bomb":
				affected = absf(cell.x - origin.x) <= 1 and absf(cell.y - origin.y) <= 1
			if affected:
				var staged := float(event_index) * float(CONFIG["FINAL_SPECIAL_DELAY_SEC"])
				delay = staged if not final_event_found else minf(delay, staged)
				final_event_found = true
			continue
		if transform_sequence and kind == "prism_transform" and event.get("targets", []).has(cell):
			var transform_index := event["targets"].find(cell)
			var transform_fraction := float(transform_index) / maxf(1.0, float(event["targets"].size() - 1))
			delay = maxf(delay, float(CONFIG["PRISM_TRANSFORM_SEC"]) * (0.72 + transform_fraction * 0.20))
		elif transform_sequence and (kind == "line_h" and cell.y == origin.y or kind == "line_v" and cell.x == origin.x or kind == "cross" and (cell.y == origin.y or cell.x == origin.x)):
			delay = maxf(delay, float(CONFIG["PRISM_TRANSFORM_SEC"]) + float(event_index) * 0.018 + minf(0.045, float(_manhattan(cell, origin)) * 0.004))
			continue
		if kind == "prism_pair":
			delay = maxf(delay, minf(0.07, _manhattan(cell, Vector2i(3, 3)) * 0.009))
		elif kind == "line_h" and cell.y == origin.y:
			delay = maxf(delay, absf(cell.x - origin.x) * float(CONFIG["CLEAR_STAGGER"]))
		elif kind == "line_v" and cell.x == origin.x:
			delay = maxf(delay, absf(cell.y - origin.y) * float(CONFIG["CLEAR_STAGGER"]))
		elif kind == "cross" and (cell.y == origin.y or cell.x == origin.x):
			delay = maxf(delay, minf(0.045, float(_manhattan(cell, origin)) * 0.004))
		elif kind == "bomb" and absf(cell.x - origin.x) <= 1 and absf(cell.y - origin.y) <= 1:
			delay = maxf(delay, _manhattan(cell, origin) * 0.014)
		elif kind == "prism_transform" and event.get("targets", []).has(cell):
			var target_index := event["targets"].find(cell)
			var fraction := float(target_index) / maxf(1.0, float(event["targets"].size() - 1))
			delay = maxf(delay, fraction * float(CONFIG["PRISM_TRANSFORM_SEC"]) * 0.68)
		elif kind == "prism" and event.get("targets", []).has(cell):
			delay = maxf(delay, minf(0.055, Vector2(cell).distance_to(Vector2(origin)) * 0.00008))
	return delay if final_blast_active else minf(delay, maxf(0.08, float(CONFIG["PRISM_TRANSFORM_SEC"]) + 0.12))


func _collapse_and_refill(cleared: Dictionary, wave := 1) -> float:
	fall_visuals.clear()
	var now := Time.get_ticks_msec()
	var longest := 0.0
	for x in range(int(CONFIG["COLS"])):
		var survivors: Array[Dictionary] = []
		for y in range(int(CONFIG["ROWS"]) - 1, -1, -1):
			var c := Vector2i(x, y)
			if not cleared.has(_key(c)):
				survivors.append({"gem": int(board[y][x]), "special": _special_at(c), "from_y": y})
			else:
				specials.erase(_key(c))
		var write_y := int(CONFIG["ROWS"]) - 1
		for item in survivors:
			board[write_y][x] = int(item["gem"])
			if str(item["special"]) != "":
				specials[_key(Vector2i(x, write_y))] = item["special"]
			else:
				specials.erase(_key(Vector2i(x, write_y)))
			var distance := write_y - int(item["from_y"])
			if distance > 0:
				var duration := minf(float(CONFIG["FALL_MAX"]), float(CONFIG["FALL_BASE"]) + sqrt(float(distance)) * float(CONFIG["FALL_PER_SQRT_ROW"])) * _wave_motion_scale(wave)
				fall_visuals[_key(Vector2i(x, write_y))] = {
					"from_y": int(item["from_y"]), "start_msec": now,
					"duration_msec": int(duration * 1000.0), "distance": distance,
				}
				longest = maxf(longest, duration)
			write_y -= 1
		var spawn_depth := 1
		while write_y >= 0:
			board[write_y][x] = randi_range(0, int(CONFIG["GEM_TYPES"]) - 1)
			specials.erase(_key(Vector2i(x, write_y)))
			var distance := write_y + spawn_depth
			var duration := minf(float(CONFIG["FALL_MAX"]), float(CONFIG["FALL_BASE"]) + sqrt(float(distance)) * float(CONFIG["FALL_PER_SQRT_ROW"])) * _wave_motion_scale(wave)
			fall_visuals[_key(Vector2i(x, write_y))] = {
				"from_y": -spawn_depth, "start_msec": now,
				"duration_msec": int(duration * 1000.0), "distance": distance,
			}
			longest = maxf(longest, duration)
			spawn_depth += 1
			write_y -= 1
	return longest


func _fall_ease(t: float, distance := 1) -> float:
	var progress := clampf(t, 0.0, 1.0)
	var overshoot := 1.0 + 0.035 / float(maxi(distance, 1))
	if progress < 0.82:
		var travel := progress / 0.82
		return overshoot * (1.0 - pow(1.0 - travel, 3.0))
	var settle := (progress - 0.82) / 0.18
	return overshoot - (overshoot - 1.0) * (1.0 - pow(1.0 - settle, 2.0))


func _start_game() -> void:
	if not background_textures.is_empty():
		active_background_index = randi_range(0, background_textures.size() - 1)
	client_match_id = ONLINE_CONTRACT.new_client_match_id()
	match_session_id = ""
	board.clear()
	specials.clear()
	score = 0
	countdown_label = "3"
	countdown_started_msec = Time.get_ticks_msec()
	countdown_label_started_msec = countdown_started_msec
	countdown_label_duration = float(CONFIG["COUNTDOWN_STEP_SEC"])
	countdown_next_msec = countdown_started_msec + int(float(CONFIG["COUNTDOWN_STEP_SEC"]) * 1000.0)
	go_flash_started_msec = -1
	speed_streak = 0
	speed_multiplier = 1
	speed_pitch_semitones = 0
	speed_last_match_msec = -1
	speed_intensity = 0.0
	speed_pulse = 0.0
	score_pop = 0.0
	music_player.volume_db = float(CONFIG["MUSIC_BASE_DB"])
	chain_count = 0
	visual_chain = 0
	seconds_left = float(CONFIG["ROUND_SECONDS"])
	timed_out = false
	final_blast_active = false
	final_blast_started = false
	final_blast_age = 10.0
	input_locked = true
	resolving = false
	selected = Vector2i(-1, -1)
	particles.clear()
	floaters.clear()
	clear_visuals.clear()
	fall_visuals.clear()
	special_visuals.clear()
	creation_visuals.clear()
	combo_banner = ""
	combo_banner_age = 10.0
	idle_glints.clear()
	hud_age = 0.0
	record_beaten = false
	transition_alpha = 0.42
	last_clock_second = int(CONFIG["ROUND_SECONDS"])
	_make_board()
	deadline_msec = 0
	seconds_left = float(CONFIG["ROUND_SECONDS"])
	game_state = "countdown"
	music_player.stop()
	_play_sfx("countdown", 0.91, -6.0)
	round_started.emit(client_match_id, ONLINE_CONTRACT.GAME_VERSION, ONLINE_CONTRACT.ONLINE_PROTOCOL_VERSION)
	queue_redraw()


func _make_board() -> void:
	for y in range(int(CONFIG["ROWS"])):
		var row: Array[int] = []
		for x in range(int(CONFIG["COLS"])):
			var value := randi_range(0, int(CONFIG["GEM_TYPES"]) - 1)
			var guard := 0
			while guard < 30 and ((x >= 2 and row[x - 1] == value and row[x - 2] == value) or (y >= 2 and int(board[y - 1][x]) == value and int(board[y - 2][x]) == value)):
				value = randi_range(0, int(CONFIG["GEM_TYPES"]) - 1)
				guard += 1
			row.append(value)
		board.append(row)
	if not _has_valid_move():
		_reshuffle_board()


func _has_valid_move() -> bool:
	for y in range(int(CONFIG["ROWS"])):
		for x in range(int(CONFIG["COLS"])):
			for d in [Vector2i(1,0), Vector2i(0,1)]:
				var b: Vector2i = Vector2i(x, y) + d
				if b.x >= int(CONFIG["COLS"]) or b.y >= int(CONFIG["ROWS"]):
					continue
				_swap_cells(Vector2i(x, y), b)
				var found := not _find_groups().is_empty()
				_swap_cells(Vector2i(x, y), b)
				if found:
					return true
	return false


func _ensure_playable_board() -> void:
	if not _has_valid_move():
		_reshuffle_board()
		_float_text("¡NUEVA COMBINACIÓN!", Vector2(size.x * 0.5, size.y * 0.28), Color("8bf7ff"))


func _reshuffle_board() -> void:
	var attempts := 0
	while attempts < 100:
		attempts += 1
		for y in range(int(CONFIG["ROWS"])):
			for x in range(int(CONFIG["COLS"])):
				board[y][x] = randi_range(0, int(CONFIG["GEM_TYPES"]) - 1)
		specials.clear()
		if _find_groups().is_empty() and _has_valid_move():
			return


func _finish_round() -> void:
	if game_state != "playing":
		return
	input_locked = true
	resolving = false
	final_blast_active = false
	seconds_left = 0.0
	game_state = "result"
	music_player.stop()
	if score > best_score:
		record_beaten = true
		best_score = score
		_save_best(best_score)
	transition_alpha = 0.72
	_play_sfx("finish", 0.9, 2.0)
	round_finished.emit(client_match_id, score, ONLINE_CONTRACT.GAME_VERSION, ONLINE_CONTRACT.ONLINE_PROTOCOL_VERSION, match_session_id)
	queue_redraw()


func _remaining_special_cells() -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for y in range(int(CONFIG["ROWS"])):
		for x in range(int(CONFIG["COLS"])):
			var cell := Vector2i(x, y)
			if _special_at(cell) != "":
				result.append(cell)
	return result


func _begin_final_blast() -> void:
	if final_blast_started or game_state != "playing":
		return
	final_blast_started = true
	final_blast_active = true
	input_locked = true
	resolving = true
	seconds_left = 0.0
	final_blast_age = 0.0
	_play_sfx("final_warning", 1.0, float(CONFIG["SFX_FINAL_WARNING_DB"]))
	_vibrate(26)
	queue_redraw()
	await get_tree().create_timer(float(CONFIG["FINAL_ZERO_PAUSE_SEC"])).timeout
	var pending := _remaining_special_cells()
	if pending.is_empty():
		await get_tree().create_timer(float(CONFIG["FINAL_NO_SPECIAL_DELAY_SEC"])).timeout
		_finish_round()
		return
	combo_banner = str(CONFIG["FINAL_BLAST_TEXT"])
	combo_banner_age = 0.0
	_float_text(combo_banner, Vector2(size.x * 0.5, size.y * 0.30), Color("ffe287"), true)
	_play_sfx("final_blast", 0.88, float(CONFIG["SFX_FINAL_DB"]) + 3.0)
	flash_alpha = 0.16
	shake_strength = float(CONFIG["FINAL_SHAKE"])
	await get_tree().create_timer(0.22).timeout
	var detonations := 0
	while detonations < int(CONFIG["FINAL_MAX_WAVES"]):
		pending = _remaining_special_cells()
		if pending.is_empty():
			break
		# Send the stable row-major batch through the same deduplicating activation queue.
		# Visual hit times are staggered, while board logic resolves once and cascades immediately.
		_play_sfx("final_blast", 0.90 + minf(float(detonations) * 0.025, 0.42), float(CONFIG["SFX_FINAL_DB"]) + minf(float(detonations) * 0.12, 2.0))
		await _resolve_board("final", pending, -1, false)
		detonations += pending.size()
	if not _remaining_special_cells().is_empty():
		# Bounded deterministic drains protect against specials created by refill cascades.
		var drain := 0
		while drain < int(CONFIG["ROWS"]) and not _remaining_special_cells().is_empty():
			var survivors := _remaining_special_cells()
			await _resolve_board("final", survivors, -1, false)
			drain += 1
	final_blast_active = false
	resolving = false
	_finish_round()


func _swap_cells(a: Vector2i, b: Vector2i) -> void:
	var tmp: int = board[a.y][a.x]
	board[a.y][a.x] = board[b.y][b.x]
	board[b.y][b.x] = tmp
	var ka := _key(a)
	var kb := _key(b)
	var sa: String = str(specials.get(ka, ""))
	var sb: String = str(specials.get(kb, ""))
	if sa == "": specials.erase(kb)
	else: specials[kb] = sa
	if sb == "": specials.erase(ka)
	else: specials[ka] = sb


func _special_at(c: Vector2i) -> String:
	if c.x < 0 or c.y < 0 or c.x >= int(CONFIG["COLS"]) or c.y >= int(CONFIG["ROWS"]):
		return ""
	return str(specials.get(_key(c), ""))


func _key(c: Vector2i) -> String:
	return str(c.y * int(CONFIG["COLS"]) + c.x)


func _is_transformable_special(kind: String) -> bool:
	return kind != "" and kind != "prism"


func _prism_transform_type(source_kind: String, row_major_index: int) -> String:
	# One extension point for every special's Prisma conversion rule.
	match source_kind:
		"line_h", "line_v":
			return "line_h" if row_major_index % 2 == 0 else "line_v"
		"cross":
			return "cross"
		"bomb": # Backwards-compatible saves from early prototypes.
			return "bomb"
		_:
			return ""


func _transform_prism_targets(color_id: int, source_kind: String) -> Array[Vector2i]:
	var transformed: Array[Vector2i] = []
	var index := 0
	for y in range(int(CONFIG["ROWS"])):
		for x in range(int(CONFIG["COLS"])):
			var cell := Vector2i(x, y)
			if int(board[y][x]) != color_id or _special_at(cell) != "":
				continue
			var target_kind := _prism_transform_type(source_kind, index)
			if target_kind == "":
				continue
			specials[_key(cell)] = target_kind
			transformed.append(cell)
			index += 1
	return transformed


func _cell_from_key(k: String) -> Vector2i:
	var value := int(k)
	return Vector2i(value % int(CONFIG["COLS"]), int(value / int(CONFIG["COLS"])))


func _manhattan(a: Vector2i, b: Vector2i) -> int:
	return absi(a.x - b.x) + absi(a.y - b.y)


func _board_geometry() -> Dictionary:
	var tile := minf((size.x - 30.0) / float(CONFIG["COLS"]), size.y * 0.53 / float(CONFIG["ROWS"]))
	var width := tile * float(CONFIG["COLS"])
	var x := (size.x - width) * 0.5
	var y := maxf(196.0, size.y * 0.159)
	return {"tile": tile, "origin": Vector2(x, y), "rect": Rect2(x, y, width, width)}


func _cell_at(pos: Vector2) -> Vector2i:
	if game_state != "playing":
		return Vector2i(-1, -1)
	var g := _board_geometry()
	var local: Vector2 = pos - Vector2(g["origin"]) - shake_offset
	var tile: float = float(g["tile"])
	var c := Vector2i(int(floor(local.x / tile)), int(floor(local.y / tile)))
	if c.x < 0 or c.y < 0 or c.x >= int(CONFIG["COLS"]) or c.y >= int(CONFIG["ROWS"]):
		return Vector2i(-1, -1)
	return c


func _make_ui_styles() -> void:
	ui_board_style = StyleBoxFlat.new()
	ui_board_style.bg_color = Color(0.012, 0.016, 0.048, 0.97)
	ui_board_style.set_corner_radius_all(12)
	ui_board_style.set_border_width_all(2)
	ui_board_style.border_color = Color("84704d")
	ui_board_style.shadow_color = Color(0.13, 0.13, 0.52, 0.30)
	ui_board_style.shadow_size = 17
	ui_board_style.shadow_offset = Vector2(0, 7)
	ui_cabinet_style = StyleBoxFlat.new()
	ui_cabinet_style.bg_color = Color(0.015, 0.020, 0.060, 0.53)
	ui_cabinet_style.set_corner_radius_all(18)
	ui_cabinet_style.set_border_width_all(2)
	ui_cabinet_style.border_color = Color(0.72, 0.54, 0.31, 0.72)
	ui_cabinet_style.shadow_color = Color(0.16, 0.22, 0.66, 0.20)
	ui_cabinet_style.shadow_size = 18
	ui_cabinet_style.shadow_offset = Vector2(0, 6)
	ui_hud_style = StyleBoxFlat.new()
	ui_hud_style.bg_color = Color(0.022, 0.027, 0.071, 0.96)
	ui_hud_style.set_corner_radius_all(9)
	ui_hud_style.set_border_width_all(2)
	ui_hud_style.border_color = Color("927347")
	ui_hud_style.shadow_color = Color(0.22, 0.24, 0.66, 0.20)
	ui_hud_style.shadow_size = 11
	ui_hud_style.shadow_offset = Vector2(0, 4)
	ui_button_style = StyleBoxFlat.new()
	ui_button_style.bg_color = Color("14d7ff")
	ui_button_style.set_corner_radius_all(22)
	ui_button_style.set_border_width_all(3)
	ui_button_style.border_color = Color("b8fbff")
	ui_button_style.shadow_color = Color(0.10, 0.72, 1.0, 0.55)
	ui_button_style.shadow_size = 20
	ui_button_style.shadow_offset = Vector2(0, 7)


func _draw_background() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color("050814"))
	if (game_state == "playing" or game_state == "countdown" or game_state == "result") and not background_textures.is_empty():
		draw_texture_rect(background_textures[active_background_index], Rect2(Vector2.ZERO, size), false)
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.008, 0.012, 0.032, 0.60), true)
	else:
		draw_rect(Rect2(0, 0, size.x, size.y * 0.61), Color(0.035, 0.10, 0.34, 0.72))
		draw_circle(Vector2(size.x * 0.49, size.y * 0.34), size.y * 0.49, Color(0.0, 0.50, 1.0, 0.11))
		draw_circle(Vector2(size.x * 0.52, size.y * 0.31), size.y * 0.31, Color(0.32, 0.11, 0.78, 0.10))
	var ambient_phase := Time.get_ticks_msec() * 0.00012
	for i in range(5):
		var beam_x := size.x * (0.10 + i * 0.20) + sin(ambient_phase + i) * 28.0
		var beam_alpha := 0.012 if game_state == "playing" or game_state == "countdown" or game_state == "result" else 0.025
		draw_line(Vector2(beam_x - 40, 0), Vector2(beam_x + 80, size.y * 0.72), Color(0.44, 0.65, 1.0, beam_alpha), 28.0, true)
	for i in range(stars.size()):
		var s: Dictionary = stars[i]
		var pulse := 0.58 + 0.42 * sin(Time.get_ticks_msec() * 0.0012 + float(s["phase"]))
		var r: float = float(s["radius"])
		draw_circle(Vector2(s["pos"]), r, Color(0.55, 0.88, 1.0, float(s["alpha"]) * pulse))
		if i % 8 == 0:
			_draw_sparkle(Vector2(s["pos"]), r * 2.0, Color(0.5, 0.87, 1.0, 0.27 * pulse))
	if game_state == "title" or game_state == "result":
		draw_rect(Rect2(0, 0, size.x, 4), Color("56ddff"))
		draw_rect(Rect2(0, 4, size.x, 2), Color(0.45, 0.3, 1.0, 0.62))


func _draw_title() -> void:
	var cx := size.x * 0.5
	var t := Time.get_ticks_msec() * 0.001
	draw_circle(Vector2(cx, size.y * 0.37), size.x * 0.44, Color(0.08, 0.55, 1.0, float(CONFIG["MENU_GLOW"]) * (0.44 + 0.13 * sin(t * 1.3))))
	draw_circle(Vector2(cx, size.y * 0.37), size.x * 0.33, Color(0.42, 0.13, 0.92, float(CONFIG["MENU_GLOW"]) * 0.42))
	_draw_ambient_crystal(Vector2(-18, size.y * 0.50), size.x * 0.29, Color("36aaff"), 0.17, 1)
	_draw_ambient_crystal(Vector2(size.x + 12, size.y * 0.61), size.x * 0.25, Color("c050ff"), 0.16, 4)
	_draw_ambient_crystal(Vector2(size.x * 0.12, size.y * 0.19), size.x * 0.11, Color("4ce9ff"), 0.15, 2)
	_draw_ambient_crystal(Vector2(size.x * 0.88, size.y * 0.25), size.x * 0.09, Color("ffc15b"), 0.15, 0)
	_draw_crystal_logo(Vector2(cx, size.y * 0.255 + sin(t * 1.4) * 5.0), minf(size.x * 0.15, 106.0))
	_draw_arcade_title_text("GLINT", size.y * 0.435, 82, Color("fff6c2"), Color("48dfff"))
	_draw_arcade_title_text("RUSH", size.y * 0.515, 98, Color("ff7bdf"), Color("c044ff"))
	var sweep_x := fposmod(t * 155.0, size.x + 160.0) - 80.0
	draw_line(Vector2(sweep_x, size.y * 0.365), Vector2(sweep_x + 104, size.y * 0.53), Color(0.73, 0.96, 1.0, 0.30), 3.0, true)
	draw_circle(Vector2(sweep_x + 52, size.y * 0.45), 24.0, Color(0.39, 0.82, 1.0, 0.045))
	_draw_text_center("60 SEGUNDOS  ·  UNA RACHA  ·  TU RÉCORD", size.y * 0.61, 20, Color("c9eaff"))
	var w := minf(size.x - 116.0, 430.0)
	title_button_rect = Rect2((size.x - w) * 0.5, size.y * 0.705, w, 94)
	_draw_button(title_button_rect, "JUGAR", Color("39e9ff"), Color("2135a7"))
	_draw_text_center("RÉCORD PERSONAL  " + _format_score(best_score), size.y * 0.855, 23, Color("ffe88c"), true)
	_draw_text_center("UNA PARTIDA. 60 SEGUNDOS. TODO PUEDE PASAR.", size.y * 0.92, 15, Color("a8bce8"))
	for s in stars:
		var sparkle_pulse := 0.5 + 0.5 * sin(t * 2.6 + float(s["phase"]))
		if int(s.get("phase", 0.0) * 100.0) % 17 == 0 and sparkle_pulse > 0.9 and float(s["pos"].y) > size.y * 0.1 and float(s["pos"].y) < size.y * 0.90:
			_draw_sparkle(Vector2(s["pos"]), float(s["radius"]) * 4.0 * sparkle_pulse, Color(0.83, 0.94, 1.0, (sparkle_pulse - 0.82) * 0.75))


func _draw_arcade_title_text(label: String, baseline: float, font_size: int, face: Color, glow: Color) -> void:
	draw_string_outline(ThemeDB.fallback_font, Vector2(0, baseline), label, HORIZONTAL_ALIGNMENT_CENTER, size.x, font_size, 15, Color(glow.r, glow.g, glow.b, 0.20))
	draw_string_outline(ThemeDB.fallback_font, Vector2(0, baseline), label, HORIZONTAL_ALIGNMENT_CENTER, size.x, font_size, 8, Color(0.12, 0.08, 0.34, 0.98))
	draw_string_outline(ThemeDB.fallback_font, Vector2(0, baseline), label, HORIZONTAL_ALIGNMENT_CENTER, size.x, font_size, 3, Color(0.74, 0.89, 1.0, 0.9))
	draw_string(ThemeDB.fallback_font, Vector2(0, baseline), label, HORIZONTAL_ALIGNMENT_CENTER, size.x, font_size, face)


func _draw_crystal_logo(center: Vector2, radius: float) -> void:
	var pts := PackedVector2Array([center + Vector2(0,-radius), center + Vector2(radius*0.78,-radius*0.28), center + Vector2(radius*0.58,radius*0.7), center + Vector2(0,radius), center + Vector2(-radius*0.58,radius*0.7), center + Vector2(-radius*0.78,-radius*0.28)])
	draw_colored_polygon(pts, Color("26ccff"))
	draw_colored_polygon(PackedVector2Array([center + Vector2(0,-radius), center + Vector2(radius*0.78,-radius*0.28), center + Vector2(0,radius*0.05)]), Color("a9f8ff"))
	draw_colored_polygon(PackedVector2Array([center + Vector2(0,-radius), center + Vector2(-radius*0.78,-radius*0.28), center + Vector2(0,radius*0.05)]), Color("73c8ff"))
	draw_colored_polygon(PackedVector2Array([center + Vector2(0,radius*0.05), center + Vector2(radius*0.58,radius*0.7), center + Vector2(0,radius)]), Color("1769de"))
	draw_colored_polygon(PackedVector2Array([center + Vector2(0,radius*0.05), center + Vector2(-radius*0.58,radius*0.7), center + Vector2(0,radius)]), Color("41afff"))
	draw_arc(center, radius * 1.25, -0.15, PI + 0.15, 42, Color(0.55, 0.94, 1.0, 0.35), 2.0, true)
	draw_polyline(pts + PackedVector2Array([pts[0]]), Color("d8fbff"), 2.0, true)
	_draw_sparkle(center + Vector2(-radius * 0.31, -radius * 0.36), radius * 0.18, Color(1, 1, 1, 0.9))
	var glint_t := fposmod(Time.get_ticks_msec() * 0.00055, 1.0)
	var glint_pos := center.lerp(center + Vector2(radius * 0.42, radius * 0.24), glint_t)
	draw_circle(glint_pos, radius * 0.14, Color(0.92, 1.0, 1.0, sin(glint_t * PI) * 0.55))


func _draw_ambient_crystal(center: Vector2, radius: float, tint: Color, alpha: float, cut: int) -> void:
	var points := _gem_points(center, radius, cut)
	var color := Color(tint.r, tint.g, tint.b, alpha)
	draw_colored_polygon(points, Color(color.r * 0.30, color.g * 0.34, color.b * 0.72, alpha * 0.65))
	for i in range(points.size()):
		var next := (i + 1) % points.size()
		var mid := center + Vector2(0, -radius * 0.08)
		var face_alpha := alpha * (0.20 if i % 2 == 0 else 0.085)
		draw_colored_polygon(PackedVector2Array([mid, points[i], points[next]]), Color(color.r, color.g, color.b, face_alpha))
	draw_polyline(points + PackedVector2Array([points[0]]), Color(0.65, 0.89, 1.0, alpha * 0.48), 1.5, true)


func _draw_hud() -> void:
	var now := Time.get_ticks_msec() * 0.001
	var entry := clampf(hud_age / float(CONFIG["HUD_ENTRY_TIME"]), 0.0, 1.0)
	var slide := 1.0 - pow(1.0 - entry, 3.0)
	var panel_y := lerpf(-18.0, 17.0, slide)
	var header := Rect2(17.0, panel_y, size.x - 34.0, 164.0)
	var board_rect: Rect2 = _board_geometry()["rect"]
	var timebar_y := board_rect.end.y + 9.0
	var timebar_height := float(CONFIG["TIMEBAR_HEIGHT"])
	var rank_panel := _ranking_panel_rect()
	var cabinet_top := panel_y - 8.0
	var cabinet_bottom := maxf(timebar_y + timebar_height + 13.0, rank_panel.end.y + 10.0)
	var cabinet := Rect2(9.0, cabinet_top, size.x - 18.0, cabinet_bottom - cabinet_top)
	var urgent := clampf((10.0 - seconds_left) / 10.0, 0.0, 1.0)
	var pulse := 0.5 + 0.5 * sin(now * lerpf(2.8, 8.0, urgent))
	var resting_border := Color("8b714c")
	ui_cabinet_style.border_color = resting_border.lerp(Color("ff597d"), urgent * (0.68 + pulse * 0.16))
	draw_style_box(ui_cabinet_style, cabinet)
	_draw_ornamental_frame(cabinet, Color("c4a36a").lerp(Color("ff687b"), urgent * 0.52), 9.0)
	ui_hud_style.border_color = Color("4778d8")
	draw_style_box(ui_hud_style, header)
	_draw_ornamental_frame(header, Color("b39a6e"), 8.0)
	var col := header.size.x / 3.0
	var left_x := header.position.x
	var middle_x := left_x + col
	var right_x := middle_x + col
	# Shaded bays keep the console readable while sharing one continuous arcade frame.
	draw_rect(Rect2(header.position + Vector2(3, 3), Vector2(col - 3, header.size.y - 6)), Color(0.04, 0.12, 0.31, 0.31), true)
	draw_rect(Rect2(Vector2(middle_x, header.position.y + 3), Vector2(col, header.size.y - 6)), Color(0.12, 0.07, 0.32, 0.35), true)
	draw_rect(Rect2(Vector2(right_x, header.position.y + 3), Vector2(col - 3, header.size.y - 6)), Color(0.04, 0.12, 0.31, 0.31), true)
	draw_line(Vector2(middle_x, header.position.y + 18), Vector2(middle_x, header.end.y - 18), Color(0.49, 0.74, 1.0, 0.35), 1.5, true)
	draw_line(Vector2(right_x, header.position.y + 18), Vector2(right_x, header.end.y - 18), Color(0.49, 0.74, 1.0, 0.35), 1.5, true)
	_draw_hud_panel_glint(header, now + 0.15)
	var score_size := 36 + int(5.0 * score_pop)
	draw_string(ThemeDB.fallback_font, Vector2(left_x + 17, panel_y + 30), "PUNTAJE", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color("a9d8ff"))
	draw_string_outline(ThemeDB.fallback_font, Vector2(left_x + 15, panel_y + 78), _format_score(score), HORIZONTAL_ALIGNMENT_LEFT, col - 26, score_size, 4, Color(0.02, 0.04, 0.19, 0.96))
	draw_string(ThemeDB.fallback_font, Vector2(left_x + 17, panel_y + 78), _format_score(score), HORIZONTAL_ALIGNMENT_LEFT, col - 26, score_size, Color("fff1a4"))
	var best_color := Color("fff09b") if record_beaten else Color("99d9ff")
	var best_text := "RÉCORD  " + _format_score(best_score)
	if record_beaten:
		best_text = "¡NUEVO RÉCORD!  " + _format_score(best_score)
	draw_string(ThemeDB.fallback_font, Vector2(left_x + 17, panel_y + 109), best_text, HORIZONTAL_ALIGNMENT_LEFT, col - 25, 14, best_color)
	draw_string(ThemeDB.fallback_font, Vector2(left_x + 17, panel_y + 137), "POSICIÓN  " + str(_player_rank_position()) + "º", HORIZONTAL_ALIGNMENT_LEFT, col - 25, 15, Color("f0cf8a"))
	draw_string(ThemeDB.fallback_font, Vector2(middle_x, panel_y + 30), "SPEED  ·  RACHA", HORIZONTAL_ALIGNMENT_CENTER, col, 16, Color("b9dcff"))
	var streak_tint := Color("9aeaff").lerp(Color("ffe28a"), speed_intensity)
	var streak_label := "RACHA %02d" % speed_streak if speed_streak > 0 else "RACHA —"
	var streak_pop := 1.0 + speed_pulse * 0.08
	var streak_size := int(25 * streak_pop)
	draw_string_outline(ThemeDB.fallback_font, Vector2(middle_x + 10, panel_y + 75), streak_label, HORIZONTAL_ALIGNMENT_CENTER, col - 86, streak_size, 3, Color(0.03, 0.03, 0.20, 0.95))
	draw_string(ThemeDB.fallback_font, Vector2(middle_x + 10, panel_y + 75), streak_label, HORIZONTAL_ALIGNMENT_CENTER, col - 86, streak_size, streak_tint)
	var badge := Rect2(middle_x + col - 69, panel_y + 44, 51, 46)
	var old_badge_border := ui_hud_style.border_color
	ui_hud_style.border_color = Color("85f6ff").lerp(Color("fff283"), speed_intensity)
	draw_style_box(ui_hud_style, badge)
	_draw_ornamental_frame(badge, Color("ead08b").lerp(Color("90fbff"), speed_intensity), 5.0)
	ui_hud_style.border_color = old_badge_border
	var multiplier_size := int(27 + speed_pulse * 4)
	draw_string_outline(ThemeDB.fallback_font, Vector2(badge.position.x, badge.position.y + 32), "x" + str(speed_multiplier), HORIZONTAL_ALIGNMENT_CENTER, badge.size.x, multiplier_size, 3, Color(0.04, 0.03, 0.18, 0.95))
	draw_string(ThemeDB.fallback_font, Vector2(badge.position.x, badge.position.y + 32), "x" + str(speed_multiplier), HORIZONTAL_ALIGNMENT_CENTER, badge.size.x, multiplier_size, streak_tint)
	var streak_bar := Rect2(middle_x + 19, panel_y + 119, col - 38, 5)
	draw_rect(streak_bar, Color(0.05, 0.08, 0.22, 0.96), true)
	var remaining := _speed_window_remaining(Time.get_ticks_msec())
	var streak_fill := maxf(remaining, speed_intensity * 0.24) if speed_streak > 0 else 0.0
	draw_rect(Rect2(streak_bar.position, Vector2(streak_bar.size.x * streak_fill, streak_bar.size.y)), Color(0.30, 0.88, 1.0, 0.70 + speed_intensity * 0.30), true)
	var urgent_label := Color("b9dcff").lerp(Color("ff9a87"), urgent)
	draw_string(ThemeDB.fallback_font, Vector2(right_x, panel_y + 30), "TIEMPO", HORIZONTAL_ALIGNMENT_CENTER, col, 16, urgent_label)
	var timer_alpha := 1.0 - urgent * 0.10 + urgent * pulse * 0.10
	var timer_font_size := int(51 + urgent * pulse * 2.0)
	draw_string_outline(ThemeDB.fallback_font, Vector2(right_x, panel_y + 92), "%02d" % int(ceil(seconds_left)), HORIZONTAL_ALIGNMENT_CENTER, col, timer_font_size, 5, Color(0.10, 0.03, 0.20, 0.96))
	var timer_tint := Color("effaff").lerp(Color("ff6b7f"), urgent)
	draw_string(ThemeDB.fallback_font, Vector2(right_x, panel_y + 92), "%02d" % int(ceil(seconds_left)), HORIZONTAL_ALIGNMENT_CENTER, col, timer_font_size, Color(timer_tint.r, timer_tint.g, timer_tint.b, timer_alpha))
	if combo_banner_age < 1.2 and chain_count > 1:
		var enter := clampf(combo_banner_age / 0.16, 0.0, 1.0)
		var leave := clampf((1.2 - combo_banner_age) / 0.24, 0.0, 1.0)
		var pop := 0.68 + 0.50 * (1.0 - pow(1.0 - enter, 3.0))
		var banner_size := int((25 + mini(chain_count, 18) * 1.5) * pop)
		var banner_color := _chain_color(chain_count)
		banner_color.a = leave
		var banner_y := board_rect.position.y - 10.0
		var banner_rect := Rect2(size.x * 0.18, banner_y - banner_size * 0.82, size.x * 0.64, banner_size * 1.35)
		draw_style_box(ui_hud_style, banner_rect)
		draw_string_outline(ThemeDB.fallback_font, Vector2(0, banner_y), combo_banner, HORIZONTAL_ALIGNMENT_CENTER, size.x, banner_size, 6, Color(0.17, 0.04, 0.40, leave))
		draw_string(ThemeDB.fallback_font, Vector2(0, banner_y), combo_banner, HORIZONTAL_ALIGNMENT_CENTER, size.x, banner_size, banner_color)


func _draw_hud_panel_glint(rect: Rect2, phase: float) -> void:
	var t := fposmod(Time.get_ticks_msec() * 0.00034 + phase, 1.0)
	var x := lerpf(rect.position.x + 12.0, rect.end.x - 12.0, t)
	draw_line(Vector2(x - 13, rect.position.y + 4), Vector2(x + 13, rect.position.y + 4), Color(0.75, 0.96, 1.0, 0.27 * sin(t * PI)), 2.0, true)


func _draw_ornamental_frame(rect: Rect2, tint: Color, inset: float) -> void:
	var alpha_tint := Color(tint.r, tint.g, tint.b, 0.82)
	var corner := minf(13.0, minf(rect.size.x, rect.size.y) * 0.16)
	for i in range(4):
		var sx := 1.0 if i == 0 or i == 3 else -1.0
		var sy := 1.0 if i == 0 or i == 1 else -1.0
		var p := Vector2(rect.position.x if sx > 0 else rect.end.x, rect.position.y if sy > 0 else rect.end.y)
		draw_line(p + Vector2(sx * inset, sy * (inset + corner)), p + Vector2(sx * (inset + corner), sy * inset), alpha_tint, 1.4, true)
		draw_circle(p + Vector2(sx * inset, sy * inset), 1.8, Color(0.97, 0.89, 0.68, 0.78))


func _player_rank_position() -> int:
	var entries := _live_rank_entries()
	for i in range(entries.size()):
		if bool(entries[i]["player"]):
			return i + 1
	return entries.size()


func _draw_timebar() -> void:
	var g := _board_geometry()
	var board_rect: Rect2 = g["rect"]
	var bar := Rect2(board_rect.position + Vector2(0, board_rect.size.y + 9.0) + shake_offset * 0.35, Vector2(board_rect.size.x, float(CONFIG["TIMEBAR_HEIGHT"])))
	var ratio := clampf(seconds_left / float(CONFIG["ROUND_SECONDS"]), 0.0, 1.0)
	var urgency := clampf((10.0 - seconds_left) / 10.0, 0.0, 1.0)
	var pulse := 0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.001 * lerpf(2.6, 8.0, urgency))
	var tint := Color("47eaff").lerp(Color("ff557e"), urgency)
	var alpha := 0.88 + urgency * pulse * 0.12
	draw_rect(bar.grow(4.0), Color(0.008, 0.009, 0.025, 0.94), true)
	draw_rect(bar, Color(0.025, 0.026, 0.057, 0.98), true)
	if ratio > 0.0:
		var fill := Rect2(bar.position, Vector2(bar.size.x * ratio, bar.size.y))
		draw_rect(fill, Color(tint.r, tint.g, tint.b, alpha), true)
		draw_rect(Rect2(fill.position + Vector2(1, 1), Vector2(maxf(0, fill.size.x - 2), 2.0)), Color(1.0, 0.98, 0.84, 0.48 + urgency * 0.2), true)
		var sheen_x := fill.position.x + fposmod(Time.get_ticks_msec() * 0.16, maxf(fill.size.x, 1.0))
		draw_line(Vector2(sheen_x - 12, bar.position.y + 2), Vector2(sheen_x + 8, bar.end.y - 2), Color(1, 1, 1, 0.46), 3.0, true)
	draw_rect(bar, Color("c4a36a").lerp(Color("ff8d80"), urgency * pulse * 0.65), false, 1.6, true)
	_draw_ornamental_frame(bar.grow(4.0), Color("c5a873"), 5.0)


func _draw_countdown_overlay() -> void:
	if countdown_label.is_empty():
		return
	var now_msec := Time.get_ticks_msec()
	var age := maxf(0.0, float(now_msec - countdown_label_started_msec) / 1000.0)
	var duration := maxf(countdown_label_duration, 0.01)
	var progress := clampf(age / duration, 0.0, 1.0)
	var fade := 1.0 if progress < 0.72 else clampf((1.0 - progress) / 0.28, 0.0, 1.0)
	var entrance := clampf(age / 0.17, 0.0, 1.0)
	var scale := 1.40 - 0.40 * (1.0 - pow(1.0 - entrance, 3.0)) + 0.055 * sin(entrance * PI)
	var g := _board_geometry()
	var board_rect: Rect2 = g["rect"]
	var center := board_rect.get_center() + shake_offset * 0.45
	var is_go := countdown_label == "¡YA!"
	var base_size := int(CONFIG["COUNTDOWN_FONT_SIZE"] * (1.06 if is_go else 1.0) * scale)
	var impact := exp(-age * 9.0)
	var tint := Color("fff29a") if is_go else Color("f5fbff")
	draw_circle(center, board_rect.size.x * (0.15 + progress * 0.11), Color(0.19, 0.69, 1.0, fade * (0.12 + impact * 0.11)))
	draw_arc(center, board_rect.size.x * (0.18 + progress * 0.18), 0.0, TAU, 64, Color(tint.r, tint.g, tint.b, fade * (0.32 + impact * 0.42)), 3.0 + impact * 2.0, true)
	var baseline := center.y + base_size * 0.34
	draw_string_outline(ThemeDB.fallback_font, Vector2(0.0, baseline), countdown_label, HORIZONTAL_ALIGNMENT_CENTER, size.x, base_size, 26, Color(0.18, 0.66, 1.0, fade * 0.48))
	draw_string_outline(ThemeDB.fallback_font, Vector2(0.0, baseline), countdown_label, HORIZONTAL_ALIGNMENT_CENTER, size.x, base_size, 10, Color(0.04, 0.04, 0.18, fade * 0.96))
	draw_string(ThemeDB.fallback_font, Vector2(0.0, baseline), countdown_label, HORIZONTAL_ALIGNMENT_CENTER, size.x, base_size, Color(tint.r, tint.g, tint.b, fade))
	if is_go and go_flash_started_msec >= 0:
		var flash_age := maxf(0.0, float(now_msec - go_flash_started_msec) / 1000.0)
		var flash_alpha_now := clampf(1.0 - flash_age / 0.34, 0.0, 1.0)
		draw_rect(board_rect, Color(0.60, 0.90, 1.0, flash_alpha_now * 0.16), true)
		draw_rect(board_rect.grow(7.0), Color(0.40, 0.84, 1.0, flash_alpha_now * 0.55), false, 4.0, true)


func _draw_final_blast_overlay() -> void:
	if not final_blast_active or final_blast_age < float(CONFIG["FINAL_ZERO_PAUSE_SEC"]):
		return
	var progress := clampf((final_blast_age - float(CONFIG["FINAL_ZERO_PAUSE_SEC"])) / 0.72, 0.0, 1.0)
	var alpha := (1.0 - progress) * 0.94
	var scale := 0.84 + 0.26 * (1.0 - exp(-final_blast_age * 14.0))
	var baseline := size.y * 0.48
	var font_size := int(50.0 * scale)
	draw_circle(Vector2(size.x * 0.5, baseline - 18.0), size.x * 0.27 * (0.25 + progress), Color(1.0, 0.55, 0.12, alpha * 0.13))
	draw_string_outline(ThemeDB.fallback_font, Vector2(0.0, baseline), str(CONFIG["FINAL_BLAST_TEXT"]), HORIZONTAL_ALIGNMENT_CENTER, size.x, font_size, 8, Color(0.16, 0.035, 0.12, alpha))
	draw_string(ThemeDB.fallback_font, Vector2(0.0, baseline), str(CONFIG["FINAL_BLAST_TEXT"]), HORIZONTAL_ALIGNMENT_CENTER, size.x, font_size, Color(1.0, 0.91, 0.62, alpha))


func _draw_board() -> void:
	var g := _board_geometry()
	var tile: float = float(g["tile"])
	var origin: Vector2 = Vector2(g["origin"]) + shake_offset
	var board_rect: Rect2 = Rect2(origin, Vector2(tile * int(CONFIG["COLS"]), tile * int(CONFIG["ROWS"])))
	draw_style_box(ui_board_style, board_rect.grow(10))
	if speed_intensity > 0.02:
		var glow_tint := Color("2bcaff").lerp(Color("b763ff"), speed_intensity * 0.72)
		draw_rect(board_rect.grow(13.0), Color(glow_tint.r, glow_tint.g, glow_tint.b, speed_intensity * 0.13), false, 2.0 + speed_intensity * 2.0, true)
	draw_rect(board_rect.grow(4), Color(0.58, 0.43, 0.25, 0.72), false, 1.4, true)
	draw_rect(board_rect.grow(7), Color(0.31, 0.58, 0.81, 0.24), false, 1.0, true)
	draw_line(board_rect.position + Vector2(18, -3), board_rect.position + Vector2(board_rect.size.x - 18, -3), Color(0.86, 0.70, 0.43, 0.32), 1.4, true)
	for y in range(int(CONFIG["ROWS"])):
		for x in range(int(CONFIG["COLS"])):
			var c := Vector2i(x, y)
			var rect := Rect2(origin + Vector2(x * tile, y * tile), Vector2(tile, tile))
			var cell_color := Color(0.008, 0.010, 0.022, 0.34) if (x + y) % 2 == 0 else Color(0.006, 0.008, 0.018, 0.28)
			draw_rect(rect.grow(-1.5), cell_color, true)
			var inset := 6.0
			if c == selected:
				draw_rect(rect.grow(-1.0), Color(1.0, 0.89, 0.38, 0.96), false, 3.5, true)
				draw_rect(rect.grow(0.7), Color(0.91, 0.69, 1.0, 0.32), false, 7.0, true)
				inset = 4.0 + sin(Time.get_ticks_msec() * 0.01) * 1.1
			var gem_center := Vector2(rect.position + rect.size * 0.5)
			var visual_key := _key(c)
			if clear_visuals.has(visual_key):
				# Draw the new falling gem underneath the fading matched gem. Their motion
				# overlaps instead of serializing the clear and collapse phases.
				if fall_visuals.has(visual_key):
					_draw_fall_gem(c, origin, tile, inset)
				_draw_clearing_gem(gem_center, tile * 0.5 - inset, clear_visuals[visual_key])
				continue
			if fall_visuals.has(visual_key):
				gem_center = _draw_fall_gem(c, origin, tile, inset)
			else:
				if swap_visual_active:
					var other := Vector2i(-1, -1)
					if c == swap_visual_a:
						other = swap_visual_b
					elif c == swap_visual_b:
						other = swap_visual_a
					if other.x >= 0:
						var from_center := origin + Vector2((other.x + 0.5) * tile, (other.y + 0.5) * tile)
						gem_center = from_center.lerp(gem_center, swap_visual_progress)
				_draw_gem(gem_center, tile * 0.5 - inset, int(board[y][x]), _special_at(c))
			for glint in idle_glints:
				if Vector2i(glint["cell"]) == c:
					_draw_idle_gem_glint(gem_center, tile * 0.5 - inset, float(glint["age"]), int(glint.get("kind", 0)))
			_draw_creation_fx(c, gem_center, tile)
	if board_rect.size.x > 10.0:
		_draw_board_corners(board_rect)


func _draw_fall_gem(cell: Vector2i, origin: Vector2, tile: float, inset: float) -> Vector2:
	var visual_key := _key(cell)
	var fall: Dictionary = fall_visuals[visual_key]
	var t := clampf(float(Time.get_ticks_msec() - int(fall["start_msec"])) / float(fall["duration_msec"]), 0.0, 1.0)
	var from_y := int(fall["from_y"])
	var distance := absi(cell.y - from_y)
	var center := origin + Vector2((cell.x + 0.5) * tile, (from_y + 0.5) * tile + (cell.y - from_y) * tile * _fall_ease(t, distance))
	var landing := clampf((t - 0.82) / 0.18, 0.0, 1.0)
	var squash := sin(landing * PI)
	var stretch := Vector2(1.0 + 0.022 * squash, 1.0 - 0.052 * squash)
	_draw_gem(center, tile * 0.5 - inset, int(board[cell.y][cell.x]), _special_at(cell), stretch)
	return center


func _draw_board_corners(rect: Rect2) -> void:
	var color := Color(0.87, 0.68, 0.38, 0.72)
	var l := 13.0
	for corner in [rect.position, Vector2(rect.end.x, rect.position.y), rect.end, Vector2(rect.position.x, rect.end.y)]:
		var sx := 1.0 if corner.x < rect.get_center().x else -1.0
		var sy := 1.0 if corner.y < rect.get_center().y else -1.0
		draw_line(corner + Vector2(sx * 4, sy * 14), corner + Vector2(sx * l, sy * 14), color, 2.0, true)
		draw_line(corner + Vector2(sx * 14, sy * 4), corner + Vector2(sx * 14, sy * l), color, 2.0, true)


func _draw_clearing_gem(center: Vector2, radius: float, visual: Dictionary) -> void:
	var elapsed := Time.get_ticks_msec() - int(visual["start_msec"])
	var duration := int(visual["duration_msec"])
	if elapsed < 0:
		_draw_gem(center, radius, int(visual["gem"]), str(visual["special"]))
		return
	var t := clampf(float(elapsed) / float(duration), 0.0, 1.0)
	var scale := 1.0
	if t < 0.16:
		scale = 1.0 - 0.13 * sin((t / 0.16) * PI * 0.5)
	else:
		scale = 0.87 * (1.0 - (t - 0.16) / 0.84)
	var color: Color = GEM_COLORS[posmod(maxi(int(visual["gem"]), 0), GEM_COLORS.size())]
	var halo_t := clampf(t * 1.8, 0.0, 1.0)
	draw_circle(center, radius * (0.42 + halo_t * 0.82), Color(color.r, color.g, color.b, 0.40 * (1.0 - t)))
	var flash := clampf(1.0 - absf(t - 0.27) / 0.25, 0.0, 1.0)
	if flash > 0.0:
		draw_circle(center, radius * (0.40 + flash * 0.56), Color(1.0, 0.98, 0.84, flash * 0.94))
		draw_circle(center, radius * (0.20 + flash * 0.20), Color(1.0, 1.0, 1.0, flash))
	if scale > 0.08:
		_draw_gem(center, radius * scale, int(visual["gem"]), str(visual["special"]))
	if t > 0.30:
		_draw_sparkle(center + Vector2(-radius * 0.38, -radius * 0.25), radius * (0.12 + t * 0.1), Color(1,1,1,(t - 0.30) * 0.7))


func _draw_creation_fx(cell: Vector2i, center: Vector2, tile: float) -> void:
	for visual in creation_visuals:
		if visual["cell"] != cell:
			continue
		var age := float(visual["age"])
		var t := clampf(age / 0.48, 0.0, 1.0)
		var radius := tile * (0.18 + t * 0.48)
		var alpha := (1.0 - t) * 0.9
		draw_arc(center, radius, 0, TAU, 32, Color("ffe994"), 3.0 + (1.0 - t) * 3.0, true)
		draw_circle(center, radius * 0.6, Color(1.0, 0.82, 0.35, alpha * 0.25))
		for i in range(4):
			var a := TAU * float(i) / 4.0 + age * 5.0
			var start := center + Vector2(cos(a), sin(a)) * radius * 1.35
			var end := center + Vector2(cos(a), sin(a)) * radius * 0.24
			draw_line(start.lerp(center, t), end, Color(1.0, 0.98, 0.80, alpha * 0.72), 2.0, true)
		var white_flash := clampf(1.0 - absf(t - 0.20) / 0.21, 0.0, 1.0)
		draw_circle(center, tile * (0.10 + white_flash * 0.36), Color(1.0, 1.0, 0.95, alpha * white_flash))
		_draw_sparkle(center + Vector2(radius * 0.56, -radius * 0.56), tile * 0.12, Color(1,1,1,alpha))


func _draw_gem(center: Vector2, r: float, color_id: int, special: String, stretch := Vector2.ONE) -> void:
	var color: Color = Color("f2fdff") if color_id < 0 else GEM_COLORS[color_id % GEM_COLORS.size()]
	if special != "":
		_draw_charged_aura(center, r, color, special)
	if special == "prism" and prism_texture != null:
		var pulse := 0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.0037)
		var extent := r * (2.18 + pulse * 0.08)
		var destination := Rect2(center - Vector2(extent, extent) * 0.5, Vector2(extent, extent))
		draw_texture_rect(prism_texture, destination, false, Color(1.0, 1.0, 1.0, 0.96))
		_draw_prism_orbit(center, r, pulse)
		return
	if gem_atlas != null and color_id >= 0:
		var index: int = GEM_SPRITE_INDEX[posmod(color_id, GEM_SPRITE_INDEX.size())]
		var source := Rect2(Vector2((index % 3) * 512, int(index / 3) * 512), Vector2(512, 512))
		var extent := r * 2.34
		var destination := Rect2(center - Vector2(extent, extent) * stretch * 0.5, Vector2(extent, extent) * stretch)
		draw_texture_rect_region(gem_atlas, destination, source, Color.WHITE, false, true)
		if special != "":
			_draw_special(center, r, special)
		return
	# Fallback for editor/import failures: keep a lightweight procedural cut gem.
	var shape := posmod(maxi(color_id, 0), 6)
	var pts := _gem_points(center, r, shape)
	var special_pulse := 0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.004 + float(color_id) * 1.7)
	if special != "":
		var glow := float(CONFIG["GEM_GLOW"]) * (0.84 + special_pulse * 0.16)
		draw_circle(center + Vector2(0, r * 0.06), r * (1.03 + special_pulse * 0.08), Color(color.r, color.g, color.b, glow))
		draw_arc(center, r * (1.02 + special_pulse * 0.035), 0, TAU, 28, Color(0.76, 0.94, 1.0, 0.18 + special_pulse * 0.12), 1.2, true)
	# Contact shadow and a deep, darker girdle give the stone weight.
	draw_circle(center + Vector2(0, r * 0.105), r * 0.90, Color(0.005, 0.012, 0.06, 0.34))
	draw_colored_polygon(pts, color.darkened(0.55))
	var inner := PackedVector2Array()
	for p in pts:
		inner.append(center + (p - center) * 0.79 + Vector2(0, -r * 0.035))
	draw_colored_polygon(inner, color.darkened(0.23))
	# Faceted girdle: alternating light-catching crown planes and darker pavilion planes.
	for i in range(pts.size()):
		var next := (i + 1) % pts.size()
		var outer_a := pts[i]
		var outer_b := pts[next]
		var inner_a := center + (outer_a - center) * 0.70 + Vector2(0, -r * 0.035)
		var inner_b := center + (outer_b - center) * 0.70 + Vector2(0, -r * 0.035)
		var direction := (outer_a + outer_b) * 0.5 - center
		var light_amount := clampf(0.12 + Vector2(direction.x, direction.y).normalized().dot(Vector2(-0.56, -0.83)) * 0.28, 0.03, 0.45)
		var facet_color := color.lerp(Color(1.0, 0.91, 0.83), light_amount)
		if i % 3 == 1:
			facet_color = color.darkened(0.27 + light_amount * 0.35)
		draw_colored_polygon(PackedVector2Array([outer_a, outer_b, inner_b, inner_a]), facet_color)
		var crown_color := color.lightened(0.19 + light_amount * 0.23) if i % 2 == 0 else color.darkened(0.08)
		draw_colored_polygon(PackedVector2Array([center + Vector2(-r * 0.015, -r * 0.11), inner_a, inner_b]), crown_color)
	# Table and pavilion faces create a bright center surrounded by internal refraction.
	var table := PackedVector2Array()
	for p in pts:
		table.append(center + (p - center) * 0.43 + Vector2(0, -r * 0.045))
	draw_colored_polygon(table, color.lightened(0.06))
	for i in range(table.size()):
		var next := (i + 1) % table.size()
		var face := color.lightened(0.19) if i in [0, 1, 2, 7] else color.darkened(0.18)
		draw_colored_polygon(PackedVector2Array([center + Vector2(0, r * 0.12), table[i], table[next]]), face)
	draw_line(center + Vector2(-r * 0.40, -r * 0.40), center + Vector2(r * 0.31, -r * 0.40), Color(1.0, 0.98, 0.88, 0.40), maxf(1.0, r * 0.035), true)
	# Restrained polished rim and a crisp specular glint.
	draw_polyline(pts + PackedVector2Array([pts[0]]), Color(color.r, color.g, color.b, 0.42), maxf(1.0, r * 0.025), true)
	var shine := PackedVector2Array([center + Vector2(-r * 0.56, -r * 0.48), center + Vector2(-r * 0.28, -r * 0.61), center + Vector2(-r * 0.12, -r * 0.50), center + Vector2(-r * 0.38, -r * 0.37)])
	draw_colored_polygon(shine, Color(1, 1, 1, 0.54))
	draw_circle(center + Vector2(-r * 0.37, -r * 0.47), maxf(1.3, r * 0.052), Color(1, 1, 1, 0.94))
	draw_circle(center + Vector2(r * 0.33, r * 0.28), r * 0.12, Color(color.lightened(0.46).r, color.lightened(0.46).g, color.lightened(0.46).b, 0.20))
	if special != "":
		_draw_special(center, r, special)


func _draw_charged_aura(center: Vector2, radius: float, gem_color: Color, kind: String) -> void:
	var now := Time.get_ticks_msec() * 0.001
	var pulse := 0.5 + 0.5 * sin(now * 7.0 + float(posmod(int(center.x + center.y), 9)))
	var strength := 0.62 + pulse * 0.28
	var inner_light := Color("fff4af")
	draw_circle(center + Vector2(0, radius * 0.04), radius * 1.08, Color(gem_color.r, gem_color.g, gem_color.b, 0.10 + pulse * 0.07))
	draw_circle(center + Vector2(0, radius * 0.03), radius * 0.77, Color(1.0, 0.66, 0.19, 0.12 + pulse * 0.09))
	# Short animated tongues read as stored energy, leaving the gemstone silhouette visible.
	for i in range(8):
		var angle := TAU * float(i) / 8.0 + now * (0.85 if i % 2 == 0 else -0.58)
		var direction := Vector2(cos(angle), sin(angle))
		var tangent := direction.orthogonal()
		var base := center + direction * radius * 0.80
		var tip := center + direction * radius * (1.12 + 0.11 * sin(now * 8.0 + float(i) * 1.9))
		var width := radius * (0.10 + 0.025 * pulse)
		var tongue := PackedVector2Array([base - tangent * width, tip, base + tangent * width])
		draw_colored_polygon(tongue, Color(gem_color.r, gem_color.g, gem_color.b, strength * 0.46))
		draw_line(base, tip, Color(inner_light.r, inner_light.g, inner_light.b, strength * 0.38), maxf(1.0, radius * 0.035), true)
	draw_arc(center, radius * (0.98 + pulse * 0.035), now * 0.6, now * 0.6 + TAU * 0.86, 42, Color(gem_color.r, gem_color.g, gem_color.b, 0.53), maxf(1.6, radius * 0.044), true)
	draw_arc(center, radius * 0.86, -now * 0.45, -now * 0.45 + PI * 0.60, 24, Color(inner_light.r, inner_light.g, inner_light.b, 0.70), maxf(1.0, radius * 0.026), true)
	for i in range(3):
		var phase := fposmod(now * (0.52 + i * 0.07) + float(i) / 3.0, 1.0)
		var spark_pos := center + Vector2(-radius * 0.72 + phase * radius * 1.44, radius * (0.64 - phase * 0.96))
		draw_circle(spark_pos, maxf(1.0, radius * 0.037), Color(1.0, 0.98, 0.90, strength * (1.0 - phase * 0.38)))
	if kind == "bomb":
		draw_circle(center, radius * 0.17, Color(inner_light.r, inner_light.g, inner_light.b, 0.28 + pulse * 0.2))


func _draw_prism_orbit(center: Vector2, radius: float, pulse: float) -> void:
	var now := Time.get_ticks_msec() * 0.001
	var colors := [Color("ff587f"), Color("ffd55c"), Color("53ffd7"), Color("55baff"), Color("d88aff")]
	draw_circle(center, radius * (1.13 + pulse * 0.08), Color(0.68, 0.28, 1.0, 0.17 + pulse * 0.12))
	for i in range(colors.size()):
		var angle := now * 1.3 + TAU * float(i) / float(colors.size())
		var p := center + Vector2(cos(angle), sin(angle)) * radius * 1.18
		draw_circle(p, radius * 0.075, Color(colors[i].r, colors[i].g, colors[i].b, 0.92))
		if i == 1:
			_draw_sparkle(p, radius * 0.16, Color(1, 1, 1, 0.84))


func _gem_points(c: Vector2, r: float, shape: int) -> PackedVector2Array:
	var pts := PackedVector2Array()
	match shape:
		0: # ruby: rounded square cushion cut
			pts = PackedVector2Array([c+Vector2(-0.56*r,-0.86*r),c+Vector2(0.56*r,-0.86*r),c+Vector2(0.86*r,-0.56*r),c+Vector2(0.86*r,0.56*r),c+Vector2(0.56*r,0.86*r),c+Vector2(-0.56*r,0.86*r),c+Vector2(-0.86*r,0.56*r),c+Vector2(-0.86*r,-0.56*r)])
		1: # sapphire: elongated brilliant cut
			pts = PackedVector2Array([c+Vector2(0,-0.94*r),c+Vector2(0.61*r,-0.68*r),c+Vector2(0.83*r,-0.20*r),c+Vector2(0.69*r,0.57*r),c+Vector2(0,0.88*r),c+Vector2(-0.69*r,0.57*r),c+Vector2(-0.83*r,-0.20*r),c+Vector2(-0.61*r,-0.68*r)])
		2: # emerald: clipped rectangular step cut
			pts = PackedVector2Array([c+Vector2(-0.62*r,-0.86*r),c+Vector2(0.62*r,-0.86*r),c+Vector2(0.86*r,-0.62*r),c+Vector2(0.86*r,0.62*r),c+Vector2(0.62*r,0.86*r),c+Vector2(-0.62*r,0.86*r),c+Vector2(-0.86*r,0.62*r),c+Vector2(-0.86*r,-0.62*r)])
		3: # citrine: oval brilliant cut
			for i in range(12):
				var angle := -PI / 2.0 + TAU * float(i) / 12.0
				pts.append(c + Vector2(cos(angle) * r * 0.78, sin(angle) * r * 0.90))
		4: # amethyst: round brilliant cut, no star points
			for i in range(12):
				var angle := -PI / 2.0 + TAU * float(i) / 12.0
				pts.append(c + Vector2(cos(angle), sin(angle)) * r * (0.88 if i % 2 == 0 else 0.82))
		5: # opal: hexagonal crystal cut
			pts = PackedVector2Array([c+Vector2(-0.48*r,-0.84*r),c+Vector2(0.48*r,-0.84*r),c+Vector2(0.89*r,-0.13*r),c+Vector2(0.60*r,0.76*r),c+Vector2(-0.60*r,0.76*r),c+Vector2(-0.89*r,-0.13*r)])
	return pts


func _draw_idle_gem_glint(center: Vector2, radius: float, age: float, kind := 0) -> void:
	var t := clampf(age / 0.38, 0.0, 1.0)
	var fade := sin(t * PI)
	var direction := -1.0 if kind == 1 else 1.0
	var position := center + Vector2(lerpf(-radius * 0.42, radius * 0.40, t), direction * lerpf(-radius * 0.24, radius * 0.30, t))
	if kind == 0:
		draw_line(position - Vector2(radius * 0.18, radius * 0.12), position + Vector2(radius * 0.17, radius * 0.10), Color(0.97, 0.99, 1.0, 0.55 * fade), maxf(1.0, radius * 0.038), true)
		draw_circle(position, radius * 0.072, Color(1, 1, 1, 0.78 * fade))
	elif kind == 1:
		draw_circle(position, radius * 0.06, Color(1, 1, 1, 0.68 * fade))
	else:
		_draw_sparkle(position, radius * 0.22 * fade, Color(1, 1, 1, 0.75 * fade))


func _draw_special(c: Vector2, r: float, kind: String) -> void:
	var pulse := 0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.005 + r)
	if kind == "line_h":
		draw_line(c + Vector2(-r * 0.58, r * 0.38), c + Vector2(r * 0.58, r * 0.38), Color(1.0, 0.91, 0.60, 0.46 + pulse * 0.36), maxf(1.5, r * 0.045), true)
	elif kind == "line_v":
		draw_line(c + Vector2(r * 0.38, -r * 0.58), c + Vector2(r * 0.38, r * 0.58), Color(1.0, 0.91, 0.60, 0.46 + pulse * 0.36), maxf(1.5, r * 0.045), true)
	elif kind == "cross":
		var mark_color := Color(1.0, 0.96, 0.71, 0.62 + pulse * 0.32)
		draw_line(c + Vector2(-r * 0.54, 0), c + Vector2(r * 0.54, 0), mark_color, maxf(1.6, r * 0.055), true)
		draw_line(c + Vector2(0, -r * 0.54), c + Vector2(0, r * 0.54), mark_color, maxf(1.6, r * 0.055), true)
		draw_circle(c, maxf(1.5, r * 0.10), Color(1.0, 1.0, 0.88, 0.78 + pulse * 0.18))
	elif kind == "bomb":
		draw_arc(c, r * (0.91 + pulse * 0.035), -0.8, TAU - 0.8, 32, Color(1.0, 0.85, 0.49, 0.75), maxf(1.5, r * 0.05), true)
		draw_circle(c + Vector2(0, -r * 0.80), maxf(1.4, r * 0.08), Color(1.0, 0.98, 0.84, 0.72 + pulse * 0.22))


func _draw_effects() -> void:
	_draw_special_visuals()
	for p in particles:
		var alpha: float = clampf(float(p["life"]) / float(p["max_life"]), 0.0, 1.0)
		var particle_color: Color = p["color"]
		particle_color.a = alpha
		if bool(p.get("shard", false)):
			var pos: Vector2 = Vector2(p["pos"])
			var heading := Vector2(p["vel"]).angle()
			var shard_r := float(p["radius"]) * alpha
			var shard := PackedVector2Array([pos + Vector2(cos(heading), sin(heading)) * shard_r * 1.6, pos + Vector2(cos(heading + 2.4), sin(heading + 2.4)) * shard_r, pos + Vector2(cos(heading - 2.4), sin(heading - 2.4)) * shard_r])
			draw_colored_polygon(shard, particle_color)
		else:
			draw_circle(Vector2(p["pos"]), float(p["radius"]) * alpha, particle_color)
	for f in floaters:
		var alpha: float = clampf(float(f["life"]) / float(f["max_life"]), 0.0, 1.0)
		var text_pos: Vector2 = Vector2(f["pos"]) - Vector2(110.0, 0.0)
		var age := float(f.get("age", 0.0))
		var pop := 0.72 + 0.48 * (1.0 - pow(1.0 - clampf(age / 0.13, 0.0, 1.0), 3.0))
		var font_size := int(float(f.get("font_size", 27)) * pop)
		var fade := minf(1.0, alpha * 1.35)
		draw_string_outline(ThemeDB.fallback_font, text_pos, str(f["text"]), HORIZONTAL_ALIGNMENT_CENTER, 220, font_size, 4, Color(0.15,0.05,0.35,fade))
		var text_color: Color = f["color"]
		text_color.a = fade
		draw_string(ThemeDB.fallback_font, text_pos, str(f["text"]), HORIZONTAL_ALIGNMENT_CENTER, 220, font_size, text_color)
	if flash_alpha > 0.01:
		var tint := _chain_color(maxi(chain_count, 3))
		draw_rect(Rect2(Vector2.ZERO, size), Color(tint.r, tint.g, tint.b, flash_alpha))


func _draw_special_visuals() -> void:
	var g := _board_geometry()
	var tile: float = float(g["tile"])
	var board_origin: Vector2 = Vector2(g["origin"]) + shake_offset
	var now := Time.get_ticks_msec()
	for event in special_visuals:
		if now < int(event["start_msec"]):
			continue
		var t := clampf(float(now - int(event["start_msec"])) / float(event["duration_msec"]), 0.0, 1.0)
		var alpha := 1.0 - t
		var kind := str(event["kind"])
		if kind == "prism_pair":
			var center := board_origin + Vector2(tile * 4.0, tile * 4.0)
			var radius := (0.15 + t * 5.8) * tile
			for ring in range(3):
				draw_arc(center, radius * (0.66 + ring * 0.22), 0, TAU, 56, Color(0.65 + ring * 0.1, 0.93, 1.0, alpha * 0.86), 5.0 - ring, true)
			var pair_flash := maxf(sin(t * PI), exp(-t * 12.0) * 0.95) * 0.50
			draw_circle(center, radius * 0.22, Color(1.0, 0.98, 0.82, alpha * 0.86))
			draw_rect(Rect2(Vector2.ZERO, size), Color(1.0, 0.93, 0.71, pair_flash * 0.62))
			continue
		var cell: Vector2i = event["cell"]
		var center := board_origin + Vector2((cell.x + 0.5) * tile, (cell.y + 0.5) * tile)
		var origin_flash := exp(-t * 12.0) * alpha
		var core_radius := tile * (0.16 + minf(t, 0.3) * 0.30)
		draw_circle(center, core_radius * 1.48, Color(1.0, 0.67, 0.20, origin_flash * 0.60))
		draw_circle(center, core_radius, Color(1.0, 0.98, 0.83, origin_flash * 0.92))
		if kind == "line_h":
			var reach := tile * 4.0 * minf(1.0, t * 1.7)
			draw_line(center - Vector2(reach, 0), center + Vector2(reach, 0), Color(1.0, 0.63, 0.18, alpha * 0.50), tile * 0.33, true)
			draw_line(center - Vector2(reach, 0), center + Vector2(reach, 0), Color(1.0, 0.89, 0.50, alpha * 0.88), tile * 0.12, true)
			draw_line(center - Vector2(reach, 0), center + Vector2(reach, 0), Color(1, 1, 1, alpha), maxf(3.0, tile * 0.075), true)
			draw_circle(center + Vector2(reach, 0), tile * 0.15, Color(1.0, 0.97, 0.68, alpha))
		elif kind == "line_v":
			var reach := tile * 4.0 * minf(1.0, t * 1.7)
			draw_line(center - Vector2(0, reach), center + Vector2(0, reach), Color(1.0, 0.63, 0.18, alpha * 0.50), tile * 0.33, true)
			draw_line(center - Vector2(0, reach), center + Vector2(0, reach), Color(1.0, 0.89, 0.50, alpha * 0.88), tile * 0.12, true)
			draw_line(center - Vector2(0, reach), center + Vector2(0, reach), Color(1, 1, 1, alpha), maxf(3.0, tile * 0.075), true)
			draw_circle(center + Vector2(0, reach), tile * 0.13, Color(1.0, 0.97, 0.68, alpha))
		elif kind == "cross":
			var reach := tile * 4.0 * minf(1.0, t * 1.7)
			# Two nearly simultaneous white-hot sweeps form the full row and column.
			for axis in [Vector2(1, 0), Vector2(0, 1)]:
				draw_line(center - axis * reach, center + axis * reach, Color(1.0, 0.62, 0.18, alpha * 0.52), tile * 0.34, true)
				draw_line(center - axis * reach, center + axis * reach, Color(1.0, 0.92, 0.58, alpha * 0.90), tile * 0.13, true)
				draw_line(center - axis * reach, center + axis * reach, Color(1.0, 1.0, 0.98, alpha), maxf(3.0, tile * 0.07), true)
			draw_circle(center, tile * (0.16 + 0.2 * exp(-t * 8.0)), Color(1.0, 0.99, 0.82, alpha * 0.92))
		elif kind == "bomb":
			var burst := clampf((t - 0.14) / 0.86, 0.0, 1.0)
			var pulse := 0.25 + 0.75 * minf(1.0, t * 5.0)
			var radius := tile * (0.20 + burst * 1.95)
			draw_circle(center, radius * 0.72, Color(1.0, 0.67, 0.20, alpha * 0.26 * pulse))
			draw_circle(center, radius * 0.36, Color(1.0, 0.99, 0.87, alpha * 0.78 * pulse))
			draw_arc(center, radius, 0, TAU, 48, Color(1.0, 0.91, 0.48, alpha), 5.0 + tile * 0.035, true)
			draw_arc(center, radius * 0.76, 0, TAU, 48, Color(1.0, 0.51, 0.25, alpha * 0.82), 3.0, true)
		elif kind == "prism" or kind == "prism_transform":
			var targets: Array = event.get("targets", [])
			var target_tint: Color = GEM_COLORS[posmod(int(event.get("target_color", 0)), GEM_COLORS.size())]
			for i in range(targets.size()):
				var target: Vector2i = targets[i]
				var target_center := board_origin + Vector2((target.x + 0.5) * tile, (target.y + 0.5) * tile)
				var ray_t := clampf(t * (2.2 if kind == "prism_transform" else 1.5) - i * (0.025 if kind == "prism_transform" else 0.018), 0.0, 1.0)
				var endpoint := center.lerp(target_center, ray_t)
				var ray_alpha := alpha * (0.42 if i % 2 == 0 else 0.68)
				draw_line(center, endpoint, Color(target_tint.r, target_tint.g, target_tint.b, ray_alpha * 0.72), maxf(3.0, tile * 0.08), true)
				draw_line(center, endpoint, Color(1.0, 0.91, 0.55, ray_alpha), maxf(2.0, tile * 0.035), true)
				draw_line(center, endpoint, Color(1.0, 1.0, 0.96, ray_alpha * 0.84), maxf(1.0, tile * 0.014), true)
				if i % 2 == 0:
					_draw_sparkle(endpoint, tile * (0.11 + 0.1 * (1.0 - t)), Color(1,1,1,ray_alpha))
				if kind == "prism_transform" and ray_t > 0.84:
					draw_circle(target_center, tile * 0.13 * alpha, Color(1.0, 0.98, 0.78, alpha * 0.68))


func _cells_center(cells: Array) -> Vector2:
	if cells.is_empty():
		return Vector2(size.x * 0.5, size.y * 0.4)
	var g := _board_geometry()
	var origin: Vector2 = Vector2(g["origin"])
	var tile: float = float(g["tile"])
	var sum := Vector2.ZERO
	for cell in cells:
		var c: Vector2i = cell
		sum += origin + Vector2((c.x + 0.5) * tile, (c.y + 0.5) * tile)
	return sum / float(cells.size())


func _draw_game_footer() -> void:
	_draw_live_ranking()
	_draw_text_center("TOCÁ Y ARRASTRÁ  •  O TOCÁ DOS GEMAS VECINAS", size.y * 0.93, 17, Color("b9d9ff"))
	draw_string(ThemeDB.fallback_font, Vector2(26, size.y - 28), "MEJOR  " + _format_score(best_score), HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color("819bcf"))
	draw_string(ThemeDB.fallback_font, Vector2(size.x - 26, size.y - 28), "GLINT RUSH", HORIZONTAL_ALIGNMENT_RIGHT, -1, 15, Color("819bcf"))


func _ranking_panel_rect() -> Rect2:
	var board_rect: Rect2 = _board_geometry()["rect"]
	var width := minf(size.x - 60.0, 560.0)
	var height := 148.0
	var x := (size.x - width) * 0.5
	var y := board_rect.end.y + 9.0 + float(CONFIG["TIMEBAR_HEIGHT"]) + 14.0
	return Rect2(x, y, width, height)


func _live_rank_entries() -> Array[Dictionary]:
	var elapsed := 0.0
	if game_state == "playing":
		elapsed = clampf(float(CONFIG["ROUND_SECONDS"]) - seconds_left, 0.0, float(CONFIG["ROUND_SECONDS"]))
	var progress := elapsed / float(CONFIG["ROUND_SECONDS"])
	var entries: Array[Dictionary] = [{"name": "VOS", "score": score, "player": true}]
	for rival in CONFIG["LOCAL_RIVALS"]:
		var rival_progress := clampf(progress * float(rival["pace"]), 0.0, 1.0)
		var rival_score := int(float(rival["finish_score"]) * pow(rival_progress, 1.12))
		entries.append({"name": str(rival["name"]), "score": rival_score, "player": false})
	entries.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if int(a["score"]) == int(b["score"]):
			return bool(a["player"]) and not bool(b["player"])
		return int(a["score"]) > int(b["score"])
	)
	return entries


func _draw_live_ranking() -> void:
	var panel := _ranking_panel_rect()
	draw_style_box(ui_hud_style, panel)
	_draw_ornamental_frame(panel, Color("ae9567"), 8.0)
	draw_string(ThemeDB.fallback_font, Vector2(panel.position.x + 16.0, panel.position.y + 23.0), "CLASIFICACIÓN", HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color("c9e4ff"))
	draw_string(ThemeDB.fallback_font, Vector2(panel.position.x, panel.position.y + 23.0), "RIVALES LOCALES · DEMO", HORIZONTAL_ALIGNMENT_RIGHT, panel.size.x - 15.0, 11, Color("8ea9da"))
	var entries := _live_rank_entries()
	var row_top := panel.position.y + 31.0
	var row_height := 27.0
	var medal_colors := [Color("ffe58a"), Color("d4e6ff"), Color("e9a879"), Color("93cfff")]
	for i in range(entries.size()):
		var row := Rect2(panel.position.x + 9.0, row_top + i * row_height, panel.size.x - 18.0, row_height - 2.0)
		var entry: Dictionary = entries[i]
		var is_player := bool(entry["player"])
		if is_player:
			draw_rect(row, Color(0.08, 0.52, 0.82, 0.34), true)
			draw_rect(row, Color("57e7ff"), false, 1.1, true)
		var label_color: Color = Color("f2fbff") if is_player else Color("b9cce9")
		var rank_color: Color = medal_colors[i] if i < medal_colors.size() else Color("b9cce9")
		draw_string(ThemeDB.fallback_font, Vector2(row.position.x + 9.0, row.position.y + 18.0), str(i + 1) + "º", HORIZONTAL_ALIGNMENT_LEFT, 30.0, 14, rank_color)
		draw_string(ThemeDB.fallback_font, Vector2(row.position.x + 44.0, row.position.y + 18.0), str(entry["name"]), HORIZONTAL_ALIGNMENT_LEFT, 120.0, 15, label_color)
		draw_string(ThemeDB.fallback_font, Vector2(row.position.x + 100.0, row.position.y + 18.0), _format_score(int(entry["score"])), HORIZONTAL_ALIGNMENT_RIGHT, row.size.x - 112.0, 15, label_color)


func _draw_result() -> void:
	draw_rect(Rect2(0, 0, size.x, size.y), Color(0.015,0.025,0.12,0.72))
	var panel := Rect2(32, size.y * 0.22, size.x - 64, size.y * 0.55)
	draw_style_box(ui_board_style, panel)
	draw_line(panel.position + Vector2(24, 5), Vector2(panel.end.x - 24, panel.position.y + 5), Color(0.76, 0.94, 1.0, 0.46), 2.0, true)
	_draw_text_center("¡TIEMPO!", size.y * 0.32, 48, Color("ff75d7"), true)
	_draw_text_center("PUNTAJE FINAL", size.y * 0.405, 21, Color("c0dbff"))
	draw_string_outline(ThemeDB.fallback_font, Vector2(0, size.y * 0.485), _format_score(score), HORIZONTAL_ALIGNMENT_CENTER, size.x, 66, 7, Color(0.03, 0.03, 0.19, 1))
	_draw_text_center(_format_score(score), size.y * 0.48, 62, Color("fff18b"), true)
	var result_record_color := Color("fff19b") if record_beaten else Color("7df3ff")
	_draw_text_center(("NUEVO RÉCORD  " if record_beaten else "RÉCORD PERSONAL  ") + _format_score(best_score), size.y * 0.55, 22, result_record_color, true)
	_draw_text_center("MEJOR RACHA DE CASCADAS  " + str(visual_chain) + "x", size.y * 0.61, 19, Color("e5caff"))
	var w := minf(size.x - 100.0, 430.0)
	again_button_rect = Rect2((size.x - w) * 0.5, size.y * 0.665, w, 90)
	_draw_button(again_button_rect, "JUGAR DE NUEVO", Color("12dfff"), Color("143c9b"))
	_draw_text_center("UNA MÁS. ESTA VEZ SALE LA CASCADA.", size.y * 0.81, 17, Color("a7bce9"))


func _draw_button(rect: Rect2, label: String, top: Color, bottom: Color) -> void:
	var now := Time.get_ticks_msec() * 0.001
	var scale := 0.975 if button_pressed else 1.0 + 0.012 * sin(now * 2.4)
	var center := rect.get_center()
	var draw_rect := Rect2(center - rect.size * scale * 0.5, rect.size * scale)
	ui_button_style.bg_color = top
	ui_button_style.shadow_size = 17 + int(3.0 * (0.5 + 0.5 * sin(now * 2.4)))
	draw_style_box(ui_button_style, Rect2(draw_rect.position, Vector2(draw_rect.size.x, draw_rect.size.y - 7)))
	var lower := Rect2(draw_rect.position + Vector2(5, draw_rect.size.y * 0.63), Vector2(draw_rect.size.x - 10, draw_rect.size.y * 0.22))
	draw_rect(lower, Color(bottom.r, bottom.g, bottom.b, 0.48), true)
	draw_rect(Rect2(draw_rect.position + Vector2(13, 9), Vector2(draw_rect.size.x - 26, 3)), Color(1, 1, 1, 0.56), true)
	draw_line(draw_rect.position + Vector2(16, 12), draw_rect.position + Vector2(16, draw_rect.size.y - 17), Color(1, 1, 1, 0.21), 2.0, true)
	var sweep := fposmod(now * 0.55, 1.0)
	var sx := draw_rect.position.x + 22 + (draw_rect.size.x - 44) * sweep
	draw_line(Vector2(sx - 18, draw_rect.position.y + 13), Vector2(sx + 10, draw_rect.end.y - 13), Color(1, 1, 1, 0.28 * sin(sweep * PI)), 5.0, true)
	draw_string_outline(ThemeDB.fallback_font, Vector2(draw_rect.position.x, draw_rect.position.y + draw_rect.size.y * 0.65), label, HORIZONTAL_ALIGNMENT_CENTER, draw_rect.size.x, 35, 4, Color(0.035, 0.035, 0.20, 0.95))
	draw_string(ThemeDB.fallback_font, Vector2(draw_rect.position.x, draw_rect.position.y + draw_rect.size.y * 0.65), label, HORIZONTAL_ALIGNMENT_CENTER, draw_rect.size.x, 35, Color("f7ffff"))


func _draw_text_center(text: String, baseline_y: float, font_size: int, color: Color, outline := false) -> void:
	var rect := Rect2(0, baseline_y - font_size, size.x, font_size * 1.55)
	if outline:
		draw_string_outline(ThemeDB.fallback_font, Vector2(0, baseline_y), text, HORIZONTAL_ALIGNMENT_CENTER, size.x, font_size, 5, Color("29205f"))
	draw_string(ThemeDB.fallback_font, Vector2(0, baseline_y), text, HORIZONTAL_ALIGNMENT_CENTER, size.x, font_size, color)


func _draw_sparkle(c: Vector2, r: float, color: Color) -> void:
	draw_colored_polygon(PackedVector2Array([c+Vector2(0,-r),c+Vector2(r*0.20,0),c+Vector2(0,r),c+Vector2(-r*0.20,0)]), color)
	draw_colored_polygon(PackedVector2Array([c+Vector2(-r,0),c,c+Vector2(r,0),c+Vector2(0,r*0.20)]), Color(color.r,color.g,color.b,color.a*0.7))


func _spawn_clear_fx(cells: Array, wave: int, speed_amount := 0.0) -> void:
	var g := _board_geometry()
	var tile: float = float(g["tile"])
	var origin: Vector2 = Vector2(g["origin"])
	var stride := maxi(1, int(cells.size() / 40))
	for i in range(cells.size()):
		if i % stride != 0:
			continue
		var c: Vector2i = cells[i]
		var center := origin + Vector2((c.x + 0.5) * tile, (c.y + 0.5) * tile)
		var color: Color = GEM_COLORS[posmod(maxi(int(board[c.y][c.x]), 0), GEM_COLORS.size())]
		var base_particle_count := 4 + wave
		var speed_particles := int(roundf(float(base_particle_count) * speed_amount * float(CONFIG["SPEED_PARTICLE_BONUS"])))
		for n in range(mini(base_particle_count + speed_particles, 18)):
			if particles.size() >= 150:
				break
			var angle := randf() * TAU
			var speed := randf_range(55.0, 220.0) * (1.0 + minf(wave * 0.11, 1.5))
			var life := randf_range(0.25, 0.6)
			particles.append({"pos": center, "vel": Vector2(cos(angle), sin(angle)) * speed, "life": life, "max_life": life, "radius": randf_range(2.0, 5.0) * (1.0 + minf(wave * 0.06, 0.8)), "color": color, "shard": n % 3 == 0})
		for n in range(2):
			if particles.size() >= 150:
				break
			var angle := randf() * TAU
			var shard_life := randf_range(0.16, 0.28)
			particles.append({"pos": center, "vel": Vector2(cos(angle), sin(angle)) * randf_range(90.0, 185.0), "life": shard_life, "max_life": shard_life, "radius": randf_range(3.5, 6.0), "color": color.lightened(0.25), "shard": true})
	if wave >= 3:
		shake_strength = minf(5.0 + wave * 1.6, 24.0)


func _float_text(text: String, pos: Vector2, color: Color, large := false) -> void:
	floaters.append({
		"text": text,
		"pos": pos,
		"color": color,
		"age": 0.0,
		"font_size": 51 if large else 29,
		"life": 0.82 if large else 0.72,
		"max_life": 0.82 if large else 0.72,
	})
	while floaters.size() > 8:
		floaters.pop_front()


func _chain_color(chain: int) -> Color:
	var colors := [Color("ffffff"), Color("70f8ff"), Color("fff476"), Color("ff82e4"), Color("ff8958"), Color("c2ff5c")]
	return colors[posmod(maxi(chain - 1, 0), colors.size())]


func _make_stars() -> void:
	stars.clear()
	for i in range(72):
		stars.append({"pos": Vector2(randf() * 720.0, randf() * 1280.0), "radius": randf_range(0.7, 2.5), "alpha": randf_range(0.15, 0.65), "phase": randf_range(0.0, TAU)})


func _begin_swap_visual(a: Vector2i, b: Vector2i, bounce_back := false) -> void:
	swap_visual_a = a
	swap_visual_b = b
	swap_visual_progress = 0.0
	swap_visual_active = true
	var tween := create_tween()
	var swap_out := tween.tween_property(self, "swap_visual_progress", 1.0, float(CONFIG["SWAP_TIME"]))
	swap_out.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	if bounce_back:
		tween.tween_interval(0.018)
		var swap_back := tween.tween_property(self, "swap_visual_progress", 0.0, float(CONFIG["SWAP_TIME"]) * 0.70)
		swap_back.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.tween_callback(func():
		if bounce_back:
			_swap_cells(a, b)
		swap_visual_active = false
		swap_visual_progress = 1.0
		if bounce_back:
			resolving = false
			if timed_out:
				_begin_final_blast()
			else:
				input_locked = false
		queue_redraw()
	)


func _play_sfx(kind: String, pitch := 1.0, volume_db := 0.0) -> void:
	if not bool(CONFIG["SOUND_ENABLED"]) or not SFX.has(kind):
		return
	var stream: AudioStream = load(str(SFX[kind]))
	if stream:
		var player: AudioStreamPlayer = sfx_players[sfx_cursor]
		sfx_cursor = (sfx_cursor + 1) % sfx_players.size()
		player.stream = stream
		player.pitch_scale = clampf(pitch, 0.75, float(CONFIG["SFX_PITCH_MAX"]))
		player.volume_db = clampf(volume_db, -30.0, 2.0)
		player.play()


func _play_sfx_after(kind: String, delay: float, pitch := 1.0, volume_db := 0.0) -> void:
	await get_tree().create_timer(maxf(0.0, delay)).timeout
	_play_sfx(kind, pitch, volume_db)


func _vibrate(duration_ms: int) -> void:
	if bool(CONFIG["HAPTICS_ENABLED"]) and OS.has_feature("mobile"):
		Input.vibrate_handheld(duration_ms)


func _load_best() -> int:
	var cfg := ConfigFile.new()
	if cfg.load("user://glint_rush.cfg") == OK:
		return int(cfg.get_value("local", "best", 0))
	return 0


func _save_best(value: int) -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("local", "best", value)
	cfg.save("user://glint_rush.cfg")


func _format_score(value: int) -> String:
	var raw := str(maxi(value, 0))
	var result := ""
	for i in range(raw.length()):
		if i > 0 and (raw.length() - i) % 3 == 0:
			result += "."
		result += raw[i]
	return result
