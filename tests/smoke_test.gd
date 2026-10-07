extends SceneTree

const ONLINE_CONTRACT = preload("res://scripts/online_contract.gd")


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	OS.set_environment("GLINT_RUSH_TEST", "1")
	var scene: PackedScene = load("res://scenes/main.tscn")
	var game: Control = scene.instantiate()
	game.size = Vector2(720, 1280)
	AudioServer.set_bus_mute(AudioServer.get_bus_index("Master"), true)
	root.add_child(game)
	await process_frame
	var client_match_ids: Array[String] = []
	var completed_rounds: Array[Dictionary] = []
	game.round_started.connect(func(match_id: String, _version: String, _protocol: int) -> void:
		client_match_ids.append(match_id)
	)
	game.round_finished.connect(func(match_id: String, final_score: int, version: String, protocol_version: int, session_id: String) -> void:
		completed_rounds.append({"id": match_id, "score": final_score, "version": version, "protocol": protocol_version, "session_id": session_id})
	)
	var service_error_count := [0]
	root.get_node("OnlineService").request_failed.connect(func(_request_id: int, _status_code: int, _code: String, _detail: String) -> void:
		service_error_count[0] += 1
	)
	var rejected_request_id: int = root.get_node("OnlineService").request_json(HTTPClient.METHOD_GET, "/rest/v1/never-called-in-game")
	assert(rejected_request_id > 0 and service_error_count[0] == 1, "offline/test-mode backend failure should be reported without a network call")
	assert(not root.get_node("OnlineService").has_authenticated_session(), "this phase must not invent an authenticated session")
	var verifier: String = root.get_node("AuthService").generate_code_verifier()
	var oauth_state: String = root.get_node("AuthService").generate_state()
	var challenge: String = root.get_node("AuthService").code_challenge_for_verifier(verifier)
	assert(verifier.length() >= 43 and verifier.length() <= 128, "PKCE verifier should meet RFC length bounds")
	assert(oauth_state.length() >= 43 and oauth_state.length() <= 128, "OAuth state should have high entropy")
	assert(challenge.length() == 43 and not challenge.contains("=") and not challenge.contains("+") and not challenge.contains("/"), "PKCE challenge should use unpadded base64url SHA-256")
	assert(root.get_node("AuthService").code_challenge_for_verifier("A".repeat(43)) == "DwBzhbb51LfusnSGBa_hqYSgo7-j8BTQnip4TOnlzRo", "PKCE must hash the verifier with SHA-256 before base64url encoding")
	var authorization_url: String = root.get_node("AuthService").build_authorization_url("https://example.supabase.co", verifier, oauth_state)
	assert(authorization_url.contains("provider=google") and authorization_url.contains("scopes=openid%20email%20profile") and authorization_url.contains("code_challenge_method=s256"), "Google authorization should request public profile data through Supabase PKCE")
	var callback_result: Dictionary = root.get_node("AuthService").parse_callback_url("glintrush://auth/callback?code=test-code&state=" + oauth_state.uri_encode())
	assert(bool(callback_result.get("ok", false)) and str(callback_result.get("code", "")) == "test-code", "deep link parser should accept a code and state")
	assert(not bool(root.get_node("AuthService").parse_callback_url("glintrush://auth/callback?access_token=bad&state=" + oauth_state).get("ok", false)), "implicit token callbacks must be rejected")
	assert(not bool(root.get_node("AuthService").parse_callback_url("glintrush://other/callback?code=x&state=" + oauth_state).get("ok", false)), "callbacks from another URI must be rejected")
	assert(not root.get_node("AuthService").start_google_login(), "GLINT_RUSH_TEST must prevent browser or network authentication")
	assert(not root.get_node("OnlineService").has_authenticated_session(), "authentication smoke coverage must not create a fake session")
	var auth_source := FileAccess.get_file_as_string("res://scripts/services/auth_service.gd")
	assert(auth_source.contains("has_java_method(") and not auth_source.contains("_bridge.has_method("), "Android auth bridge must keep Java method checks")
	assert(game.gem_atlas != null, "transparent gem atlas should load")
	assert(game.prism_texture != null, "the original prism core sprite should load")
	assert(game.background_textures.size() == 3, "three original fantasy arenas should be available to rotate")
	assert(ResourceLoader.exists("res://assets/gems/gem_atlas.png"), "the six-gem material atlas should be bundled")
	assert(ResourceLoader.exists("res://assets/gems/prism_core.png"), "the multicolor prism art should be bundled")
	assert(is_equal_approx(float(game.call("_fall_ease", 0.0)), 0.0), "fall easing should start at the source")
	assert(is_equal_approx(float(game.call("_fall_ease", 1.0, 4)), 1.0), "fall easing should settle exactly at the target")
	assert(ResourceLoader.exists("res://assets/sfx/start_go.wav"), "the GO cue should be an original bundled sound")
	for sound_path in ["cross.wav", "cross_create.wav", "prism_charge.wav", "prism_transform.wav", "final_warning.wav", "final_blast.wav", "speed_shimmer.wav", "speed_harmony.wav"]:
		assert(ResourceLoader.exists("res://assets/sfx/" + sound_path), "new original sound should be bundled: " + sound_path)
	game.call("_start_game")
	var first_match_id: String = game.client_match_id
	assert(first_match_id.split("-").size() == 5 and first_match_id.length() == 36, "each round should receive a UUID client_match_id")
	assert(first_match_id.substr(14, 1) == "4" and "89ab".contains(first_match_id.substr(19, 1)), "client_match_id should be an RFC 4122 version 4 UUID")
	assert(client_match_ids.size() == 1 and client_match_ids[0] == first_match_id, "round_started should expose the ID and centralized version contract")
	assert(game.game_state == "countdown", "pressing PLAY should enter the in-board countdown")
	assert(game.countdown_label == "3" and game.input_locked, "the first countdown number should appear while input is locked")
	assert(game.deadline_msec == 0 and is_equal_approx(game.seconds_left, 60.0), "the round clock must remain stopped during countdown")
	assert(game.countdown_next_msec - game.countdown_started_msec == 760, "each number should last the configured 0.76 seconds")
	assert(game.board.size() == 8, "new round should create 8 rows")
	assert(game.board[0].size() == 8, "new round should create 8 columns")
	assert(game.call("_find_groups").is_empty(), "initial board should not start with a match")
	assert(game.call("_has_valid_move"), "initial board should have a legal move")
	var countdown_entries: Array = game.call("_live_rank_entries")
	assert(countdown_entries.size() == 4 and countdown_entries[0]["name"] == "VOS", "the live demo table should include the player and three local rivals")
	var countdown_move := _find_move(game)
	var countdown_board: Array = game.board.duplicate(true)
	game.call("_attempt_swap", countdown_move[0], countdown_move[1])
	assert(game.board == countdown_board, "board input must not be accepted during countdown")
	_advance_countdown_boundary(game)
	assert(game.countdown_label == "2" and game.game_state == "countdown", "countdown should progress from three to two")
	_advance_countdown_boundary(game)
	assert(game.countdown_label == "1" and game.game_state == "countdown", "countdown should progress from two to one")
	_advance_countdown_boundary(game)
	assert(game.countdown_label == "¡YA!" and game.game_state == "playing", "GO should transition directly into the live round")
	assert(not game.input_locked and game.seconds_left == 60.0, "input and the untouched 60 second timer should start with GO")
	assert(game.deadline_msec == game.countdown_label_started_msec + 60000, "the 60 second deadline should begin on the GO cue")
	var rank_saved_score: int = game.score
	var rank_saved_time: float = game.seconds_left
	game.score = 30000
	game.seconds_left = 30.0
	var updated_entries: Array = game.call("_live_rank_entries")
	assert(updated_entries[0]["name"] == "VOS", "the live ranking should immediately reflect the player's score")
	game.score = rank_saved_score
	game.seconds_left = rank_saved_time
	var before_invalid: Array = game.board.duplicate(true)
	var invalid_move := _find_invalid_move(game)
	assert(invalid_move.size() == 2, "test should locate an invalid swap")
	game.call("_attempt_swap", invalid_move[0], invalid_move[1])
	assert(game.resolving and game.input_locked, "invalid swap animation must lock input")
	var invalid_wait: float = 0.0
	while game.resolving and invalid_wait < 3.0:
		await create_timer(0.05).timeout
		invalid_wait += 0.05
	assert(not game.resolving, "invalid swap should finish within timeout")
	assert(game.board == before_invalid, "invalid swap should return both gems to their original cells")
	assert(not game.input_locked, "invalid swap should restore control after returning")

	var playable_move := _find_move(game)
	assert(playable_move.size() == 2, "test should locate a generated legal move")
	game.call("_attempt_swap", playable_move[0], playable_move[1])
	await create_timer(0.14).timeout
	assert(game.resolving and game.input_locked, "input must stay locked while matches animate")
	assert(not game.clear_visuals.is_empty(), "matched gems should animate before removal")
	assert(not game.fall_visuals.is_empty(), "fall paths should begin while the match is still fading")
	var board_during_fall: Array = game.board.duplicate(true)
	game.call("_attempt_swap", playable_move[0], playable_move[1])
	assert(game.board == board_during_fall, "touch input during a fall must not mutate the board")
	var wait_elapsed := 0.0
	while game.resolving and wait_elapsed < 5.0:
		await create_timer(0.1).timeout
		wait_elapsed += 0.1
	assert(game.score > 0, "a valid match should award score")
	assert(game.speed_streak == 1, "automatic cascades should not count as additional manual SPEED matches")
	assert(not game.resolving, "board should return control after resolution")

	_set_empty_board(game)
	for x in range(1, 5):
		game.board[2][x] = 0
	var groups: Array = game.call("_find_groups")
	assert(groups.size() == 1, "four in a row should be one group")
	assert(game.call("_special_for_group", groups[0])["type"] == "line_h", "horizontal four should create horizontal line")

	_set_empty_board(game)
	for x in range(1, 6): game.board[2][x] = 0
	groups = game.call("_find_groups")
	assert(game.call("_special_for_group", groups[0])["type"] == "prism", "five in a row should create a prism")

	_set_empty_board(game)
	for y in range(1, 5):
		game.board[y][2] = 1
	groups = game.call("_find_groups")
	assert(groups.size() == 1, "vertical four should be one group")	
	assert(game.call("_special_for_group", groups[0])["type"] == "line_v", "vertical four should create vertical line")

	_set_empty_board(game)
	for x in range(2, 5): game.board[3][x] = 2
	for y in range(2, 5): game.board[y][3] = 2
	groups = game.call("_find_groups")
	assert(groups.size() == 1, "T match should resolve as one connected group")
	assert(game.call("_special_for_group", groups[0])["type"] == "cross", "T shape should create row+column cross special")
	assert(game.call("_is_transformable_special", "cross") and game.call("_is_transformable_special", "line_h") and not game.call("_is_transformable_special", "prism"), "Prism conversion should accept secondary specials but preserve the Prism tier")

	_set_empty_board(game)
	for x in range(1, 4): game.board[1][x] = 2
	for y in range(1, 4): game.board[y][1] = 2
	groups = game.call("_find_groups")
	assert(groups.size() == 1 and game.call("_special_for_group", groups[0])["type"] == "cross", "L shape should create the same cross special")

	_set_empty_board(game)
	game.specials.clear()
	var cross_cell := Vector2i(3, 4)
	var effects: Dictionary
	game.specials[game.call("_key", cross_cell)] = "cross"
	effects = game.call("_collect_special_effects", {}, [cross_cell], -1, false)
	assert(effects["activated"] == 1 and effects["clear"].size() == 15, "cross should clear its entire row and column exactly once")
	game.specials[game.call("_key", Vector2i(0, 4))] = "line_v"
	effects = game.call("_collect_special_effects", {}, [cross_cell], -1, false)
	assert(effects["activated"] == 2 and effects["clear"].size() >= 15, "cross lines should trigger reached specials in a deduplicated chain")

	_set_empty_board(game)
	game.specials.clear()
	for cell in [Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 2), Vector2i(6, 6), Vector2i(7, 7)]: game.board[cell.y][cell.x] = 1
	game.specials[game.call("_key", Vector2i(4, 4))] = "line_h"
	var transformed: Array = game.call("_transform_prism_targets", 1, "line_h")
	assert(transformed.size() == 5, "Prism plus line should convert every normal gem of its color and preserve existing specials")
	assert(game.call("_special_at", transformed[0]) == "line_h" and game.call("_special_at", transformed[1]) == "line_v", "converted line specials should alternate deterministically by row-major order")
	game.specials[game.call("_key", Vector2i(1, 1))] = "prism"
	effects = game.call("_collect_special_effects", {}, [Vector2i(1, 1)], 1, false)
	assert(effects["activated"] == 6, "Prism plus line should activate the Prism and all converted line gems")
	assert(game.call("_prism_transform_type", "line_v", 0) == "line_h" and game.call("_prism_transform_type", "line_h", 1) == "line_v", "line-special conversion should use one deterministic alternating orientation rule")

	_set_empty_board(game)
	game.specials.clear()
	for cell in [Vector2i(0, 0), Vector2i(2, 1), Vector2i(4, 3), Vector2i(6, 5)]: game.board[cell.y][cell.x] = 4
	transformed = game.call("_transform_prism_targets", 4, "cross")
	assert(transformed.size() == 4, "Prism plus T/L should convert every normal gem of that color")
	for cell in transformed:
		assert(game.call("_special_at", cell) == "cross", "Prism plus T/L should produce multiple cross specials")
	game.specials[game.call("_key", Vector2i(1, 1))] = "prism"
	effects = game.call("_collect_special_effects", {}, [Vector2i(1, 1)], 4, false)
	assert(effects["activated"] == 5 and effects["clear"].size() >= 45, "Prism plus T/L should activate the Prism and multiple transformed crosses")

	_set_empty_board(game)
	game.specials.clear()
	for cell in [Vector2i(0, 0), Vector2i(3, 2), Vector2i(7, 7)]: game.board[cell.y][cell.x] = 3
	game.specials[game.call("_key", Vector2i(1, 1))] = "prism"
	effects = game.call("_collect_special_effects", {}, [Vector2i(1, 1)], 3, false)
	assert(effects["clear"].size() == 4, "Prism plus normal should still clear its chosen color")

	_set_empty_board(game)
	game.specials.clear()
	game.specials[game.call("_key", Vector2i(3, 4))] = "line_h"
	game.specials[game.call("_key", Vector2i(4, 4))] = "bomb"
	effects = game.call("_collect_special_effects", {}, [Vector2i(3, 4)], -1, false)
	assert(effects["activated"] == 2, "specials reached by another special should chain")

	# An old special in a four-match must fire, while the match still creates its new line special.
	_set_empty_board(game)
	game.specials.clear()
	for x in range(1, 5): game.board[2][x] = 0
	var old_special_cell := Vector2i(2, 2)
	var new_special_cell := Vector2i(4, 2)
	game.specials[game.call("_key", old_special_cell)] = "line_v"
	game.last_move_cell = new_special_cell
	game.score = 0
	await game.call("_resolve_board", "", [], -1, false)
	assert(game.call("_special_at", old_special_cell) == "", "the existing line special in a match must activate and be consumed")
	assert(game.call("_special_at", new_special_cell) == "line_h", "the four-match must retain its newly created special after the old one resolves")
	assert(game.score >= 1800, "the new-special match must include match, create, and existing-special activation score")

	var tile_size: float = float(game.call("_board_geometry")["tile"])
	assert(game.call("_drag_direction", Vector2(tile_size * 0.10, 0.0)) == Vector2i.ZERO, "small finger jitter must not start a swap")
	assert(game.call("_drag_direction", Vector2(tile_size * 0.30, tile_size * 0.05)) == Vector2i.RIGHT, "horizontal drag should choose the dominant axis")
	assert(game.call("_drag_direction", Vector2(-tile_size * 0.05, -tile_size * 0.30)) == Vector2i.UP, "vertical drag should preserve its sign")
	_set_empty_board(game)
	game.specials.clear()
	for y in range(8):
		for x in range(8): game.board[y][x] = (x + 2 * y) % 6
	var board_geometry: Dictionary = game.call("_board_geometry")
	var board_origin: Vector2 = board_geometry["origin"]
	var drag_cell := Vector2i(3, 3)
	var drag_start := board_origin + Vector2((drag_cell.x + 0.5) * tile_size, (drag_cell.y + 0.5) * tile_size) + game.shake_offset
	game.game_state = "playing"
	game.input_locked = false
	game.resolving = false
	game.call("_pointer_start", drag_start)
	game.call("_pointer_motion", drag_start + Vector2(tile_size * 0.30, 0.0))
	assert(game.pointer_swap_started, "crossing the drag threshold should start a swap before finger release")
	var board_after_drag: Array = game.board.duplicate(true)
	game.call("_pointer_motion", drag_start + Vector2(0.0, tile_size * 0.50))
	assert(game.board == board_after_drag, "one drag gesture must not trigger a second swap")
	game.call("_pointer_end", drag_start + Vector2(tile_size * 0.30, 0.0))
	var drag_wait := 0.0
	while game.resolving and drag_wait < 5.0:
		await create_timer(0.05).timeout
		drag_wait += 0.05
	assert(not game.resolving, "drag-initiated move should settle and return control")

	# Restart invalidates an in-flight resolver so it cannot mutate the replacement board.
	_set_empty_board(game)
	game.specials.clear()
	for x in range(1, 5): game.board[2][x] = 1
	game.last_move_cell = Vector2i(4, 2)
	game.call("_resolve_board", "", [], -1, false)
	game.call("_start_game")
	var restarted_board: Array = game.board.duplicate(true)
	await create_timer(0.55).timeout
	assert(game.game_state == "countdown" and game.board == restarted_board, "restart must cancel pending async board resolutions")
	assert(game.specials.is_empty() and not game.resolving, "restart must clear specials and input locks from the prior round")
	game.call("_open_dialog", "restart")
	assert(game.dialog_kind == "restart", "restart action should request confirmation")
	game.call("_close_dialog")
	assert(game.dialog_kind == "", "cancel should close the restart confirmation")
	game.call("_open_dialog", "exit")
	assert(game.dialog_kind == "exit", "exit action should request confirmation without confusing it with logout")
	game.call("_close_dialog")
	var restart_generation: int = game.round_generation
	game.call("_open_dialog", "restart")
	game.call("_confirm_dialog")
	game.call("_open_dialog", "restart")
	game.call("_confirm_dialog")
	assert(game.round_generation == restart_generation + 2 and game.game_state == "countdown", "repeated confirmed restarts should start clean rounds without accumulating state")
	assert(game.specials.is_empty() and game.particles.is_empty() and not game.resolving, "repeated restart should keep transient board state cleared")

	_set_empty_board(game)
	game.specials.clear()
	game.board[0][0] = 2
	game.board[3][5] = 2
	game.board[7][7] = 2
	game.specials[game.call("_key", Vector2i(1, 1))] = "prism"
	effects = game.call("_collect_special_effects", {}, [Vector2i(1, 1)], 2, false)
	assert(effects["clear"].size() == 4, "prism should clear its target color and itself")

	_set_empty_board(game)
	game.specials.clear()
	game.specials[game.call("_key", Vector2i(0, 0))] = "prism"
	game.specials[game.call("_key", Vector2i(7, 7))] = "prism"
	game.specials[game.call("_key", Vector2i(3, 3))] = "bomb"
	effects = game.call("_collect_special_effects", {}, [Vector2i(0, 0), Vector2i(7, 7)], -1, true)
	assert(effects["clear"].size() == 64, "prism pair should clear the entire board")
	assert(effects["activated"] == 3, "full-board clear should activate every special it reaches")

	# Deterministic SPEED streak coverage: only registered manual matches advance it.
	game.set_process(false)
	game.speed_streak = 0
	game.speed_last_match_msec = -1
	game.call("_register_speed_match", 10000)
	assert(game.speed_streak == 1 and game.speed_multiplier == 1, "first quick match should start SPEED x1")
	assert(game.speed_pitch_semitones == 0, "first quick match should use the base musical step")
	game.call("_register_speed_match", 12000)
	assert(game.speed_streak == 2 and game.speed_multiplier == 1, "second quick match should continue the streak at x1")
	assert(game.speed_pitch_semitones == 2, "second match should rise by a musical step")
	game.call("_register_speed_match", 13500)
	assert(game.speed_streak == 3 and game.speed_multiplier == 2, "third quick match should raise SPEED to x2")
	game.call("_register_speed_match", 14500)
	assert(game.speed_streak == 4 and game.speed_multiplier == 2, "fourth quick match should hold x2")
	game.call("_register_speed_match", 15000)
	assert(game.speed_streak == 5 and game.speed_multiplier == 3, "fifth quick match should raise SPEED to x3")
	assert(game.speed_pitch_semitones == 9, "fifth match should use the configured ascending pitch step")
	game.score = 0
	game.call("_score_wave", 3, [], 0, 1, false, [], game.speed_multiplier)
	assert(game.score == 900, "the manual match score should receive the active SPEED multiplier")
	game.call("_score_wave", 3, [], 0, 2, false, [], 1)
	assert(game.score == 1500, "an automatic cascade should use its chain multiplier without reapplying SPEED")
	var strong_glow: float = game.speed_intensity
	game.call("_update_speed_state", 0.10, 18001)
	assert(game.speed_streak == 0 and game.speed_multiplier == 1, "expired SPEED window should reset the streak and multiplier")
	assert(game.speed_intensity < strong_glow and game.speed_intensity > 0.0, "expired SPEED glow should decay instead of dropping instantly")
	game.call("_register_speed_match", 18100)
	assert(game.speed_streak == 1 and game.speed_multiplier == 1, "a new move after expiry should begin a fresh streak")
	game.set_process(true)

	game.call("_start_game")
	var second_match_id: String = game.client_match_id
	assert(second_match_id != first_match_id and client_match_ids.size() == 2, "a replay should get a new ID and preserve it for the full round")
	_skip_start_countdown(game)
	playable_move = _find_move(game)
	game.deadline_msec = Time.get_ticks_msec() + 100
	game.call("_attempt_swap", playable_move[0], playable_move[1])
	var settle_wait := 0.0
	while game.game_state == "playing" and settle_wait < 12.0:
		await create_timer(0.1).timeout
		settle_wait += 0.1
	assert(game.game_state == "result", "timer should finish only after the started move settles")
	assert(game.score > 0, "move started before zero should still score")
	assert(game.timed_out and game.seconds_left == 0.0, "the clock should remain at zero through settlement")

	# Final Blast ordering, no-special fast finish and an actual cross detonation.
	game.call("_start_game")
	_skip_start_countdown(game)
	game.specials.clear()
	game.specials[game.call("_key", Vector2i(7, 7))] = "cross"
	game.specials[game.call("_key", Vector2i(0, 2))] = "line_h"
	game.specials[game.call("_key", Vector2i(3, 4))] = "prism"
	var final_pending: Array = game.call("_remaining_special_cells")
	assert(final_pending == [Vector2i(0, 2), Vector2i(3, 4), Vector2i(7, 7)], "remaining specials should be collected in deterministic row-major order")
	game.specials.clear()
	game.score = 731
	game.timed_out = true
	game.seconds_left = 0.0
	game.call("_begin_final_blast")
	assert(game.final_blast_active and game.resolving and game.input_locked, "zero should immediately lock input and enter settlement")
	var final_wait := 0.0
	while game.game_state == "playing" and final_wait < 8.0:
		await create_timer(0.02).timeout
		final_wait += 0.02
	assert(game.game_state == "result" and game.score == 731, "a board without specials should move to results quickly without score changes")

	game.call("_start_game")
	_skip_start_countdown(game)
	_set_empty_board(game)
	game.specials.clear()
	game.specials[game.call("_key", Vector2i(3, 4))] = "cross"
	game.board[4][3] = 2
	game.score = 0
	game.timed_out = true
	game.seconds_left = 0.0
	game.call("_begin_final_blast")
	assert(game.input_locked and game.final_blast_active, "the final cross must detonate with player input locked")
	final_wait = 0.0
	while game.game_state == "playing" and final_wait < 15.0:
		await create_timer(0.02).timeout
		final_wait += 0.02
	assert(game.game_state == "result", "the final special sequence should finish before results appear")
	assert(game.score > 0, "special activations during Final Blast should keep awarding score")
	assert(game.specials.is_empty(), "the final cross should be consumed once without duplicate pending activations")
	assert(not completed_rounds.is_empty(), "round_finished should fire when final settlement is complete")
	var final_round: Dictionary = completed_rounds.back()
	assert(final_round["id"] == game.client_match_id and final_round["id"] == client_match_ids.back(), "round_finished should retain the same ID generated at round start")
	assert(final_round["score"] == game.score and final_round["session_id"] == "", "the final event should contain settled score and no fabricated ranked session")
	assert(final_round["version"] == ONLINE_CONTRACT.GAME_VERSION and final_round["protocol"] == ONLINE_CONTRACT.ONLINE_PROTOCOL_VERSION, "the event should use centralized game/protocol versions")
	var local_record_cfg := ConfigFile.new()
	assert(local_record_cfg.load("user://glint_rush.cfg") == OK, "the existing local record file should still be saved")
	assert(int(local_record_cfg.get_value("local", "best", 0)) == game.best_score, "the saved local best should remain authoritative for the local record")

	print("SMOKE TEST PASS: generation, touch drag direction/threshold, gesture guards, countdown/GO, simulated ranking, local scoring/record, match IDs/events, offline/test-mode service failure, 4/5/T/L specials, old-special activation with preserved new-special creation, full cross and chain reaction, deterministic Prisma conversions, Prisma pair/color clear, SPEED streak/pitch/expiry, restart cancellation, timeout settlement, Final Blast/no-special finish/final scoring")
	game.music_player.stop()
	game.music_player.stream = null
	for player in game.sfx_players:
		player.stop()
		player.stream = null
	await process_frame
	game.free()
	await process_frame
	quit(0)


func _set_empty_board(game: Control) -> void:
	var board: Array = []
	for y in range(8):
		var row: Array[int] = []
		for x in range(8): row.append(-1)
		board.append(row)
	game.board = board


func _find_move(game: Control) -> Array:
	for y in range(8):
		for x in range(8):
			for d in [Vector2i(1, 0), Vector2i(0, 1)]:
				var other: Vector2i = Vector2i(x, y) + d
				if other.x >= 8 or other.y >= 8:
					continue
				game.call("_swap_cells", Vector2i(x, y), other)
				var valid: bool = not game.call("_find_groups").is_empty()
				game.call("_swap_cells", Vector2i(x, y), other)
				if valid:
					return [Vector2i(x, y), other]
	return []


func _find_invalid_move(game: Control) -> Array:
	for y in range(8):
		for x in range(8):
			for d in [Vector2i(1, 0), Vector2i(0, 1)]:
				var other: Vector2i = Vector2i(x, y) + d
				if other.x >= 8 or other.y >= 8:
					continue
				game.call("_swap_cells", Vector2i(x, y), other)
				var valid: bool = not game.call("_find_groups").is_empty()
				game.call("_swap_cells", Vector2i(x, y), other)
				if not valid:
					return [Vector2i(x, y), other]
	return []


func _advance_countdown_boundary(game: Control) -> void:
	var now_msec := Time.get_ticks_msec()
	game.countdown_next_msec = now_msec
	game.call("_advance_countdown", now_msec)


func _skip_start_countdown(game: Control) -> void:
	for i in range(3):
		_advance_countdown_boundary(game)
