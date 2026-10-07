extends Node

signal auth_state_changed(state: String, profile: Dictionary, detail: String)

const CALLBACK_URL := "glintrush://auth/callback"
const SECURE_REFRESH_KEY := "refresh_token"
const SECURE_VERIFIER_KEY := "pkce_verifier"
const SECURE_STATE_KEY := "pkce_state"
const REFRESH_SKEW_SECONDS := 90

var auth_state := "unauthenticated"
var profile: Dictionary = {}
var session_persisted := false
var last_auth_detail := ""
var _refresh_token := ""
var _code_verifier := ""
var _expected_state := ""
var _bridge: Object
var _refresh_in_flight := false
var _callback_in_flight := false
var _browser_waiting := false
var _poll_elapsed := 0.0
var _restore_attempt_elapsed := 0.0
var _test_mode := false


func _ready() -> void:
	_test_mode = OS.get_environment("GLINT_RUSH_TEST") == "1"
	set_process(true)

	if OS.get_name() == "Android":
		call_deferred("_initialize_android_bridge")
	else:
		_set_state("unauthenticated", {}, "El login Google requiere ejecutar GLINT RUSH en Android.")


func _initialize_android_bridge() -> void:
	# El plugin Android puede registrarse después de que AuthService
	# haya ejecutado _ready(), por eso esperamos algunos frames.
	for _attempt in range(60):
		if Engine.has_singleton("GlintRushAuth"):
			_bridge = Engine.get_singleton("GlintRushAuth")
			call_deferred("_restore_saved_session")
			return

		await get_tree().process_frame

	push_warning("GLINT RUSH Auth: GlintRushAuth no apareció después de 60 frames.")
	_set_state("unauthenticated", {}, "El complemento Android seguro no está disponible. El juego local sigue disponible.")


func _process(delta: float) -> void:
	if _bridge != null and not _callback_in_flight:
		_poll_elapsed += delta
		if _poll_elapsed >= 0.15:
			_poll_elapsed = 0.0
			_poll_auth_callback()
	if auth_state == "authenticated" and not _refresh_in_flight:
		var expires_at: int = OnlineService.get_access_token_expires_at()
		var now_unix: int = int(Time.get_unix_time_from_system())
		if expires_at > 0 and expires_at <= now_unix + REFRESH_SKEW_SECONDS:
			call_deferred("_refresh_saved_session", false)
	elif auth_state == "offline" and not _refresh_in_flight and not _refresh_token.is_empty():
		_restore_attempt_elapsed += delta
		if _restore_attempt_elapsed >= 30.0:
			_restore_attempt_elapsed = 0.0
			call_deferred("_refresh_saved_session", false)


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_RESUMED and _browser_waiting:
		call_deferred("_check_browser_return")


static func _base64url(data: PackedByteArray) -> String:
	return Marshalls.raw_to_base64(data).replace("+", "-").replace("/", "_").replace("=", "")


static func generate_code_verifier() -> String:
	var random_bytes: PackedByteArray = Crypto.new().generate_random_bytes(32)
	if random_bytes.size() != 32:
		return ""
	return _base64url(random_bytes)


static func generate_state() -> String:
	var random_bytes: PackedByteArray = Crypto.new().generate_random_bytes(32)
	if random_bytes.size() != 32:
		return ""
	return _base64url(random_bytes)


static func code_challenge_for_verifier(verifier: String) -> String:
	if verifier.length() < 43 or verifier.length() > 128:
		return ""
	var hashing := HashingContext.new()
	if hashing.start(HashingContext.HASH_SHA256) != OK:
		return ""
	if hashing.update(verifier.to_utf8_buffer()) != OK:
		return ""
	return _base64url(hashing.finish())


static func build_authorization_url(project_url: String, verifier: String, state: String) -> String:
	var challenge: String = code_challenge_for_verifier(verifier)
	if challenge.is_empty() or state.is_empty():
		return ""
	var redirect_with_state: String = CALLBACK_URL + "?state=" + state.uri_encode()
	return project_url.trim_suffix("/") + "/auth/v1/authorize?provider=google&scopes=" + "openid email profile".uri_encode() + "&redirect_to=" + redirect_with_state.uri_encode() + "&code_challenge=" + challenge.uri_encode() + "&code_challenge_method=s256"


static func parse_callback_url(callback_url: String) -> Dictionary:
	if not callback_url.begins_with(CALLBACK_URL):
		return {"ok": false, "code": "invalid_callback"}
	var url_parts: PackedStringArray = callback_url.split("?", true, 1)
	if url_parts.is_empty() or url_parts[0] != CALLBACK_URL or callback_url.contains("#"):
		return {"ok": false, "code": "invalid_callback"}
	if url_parts.size() < 2:
		return {"ok": false, "code": "missing_parameters"}
	var parameters: Dictionary = {}
	for pair in url_parts[1].split("&"):
		if pair.is_empty():
			continue
		var pair_parts: PackedStringArray = pair.split("=", true, 1)
		var key: String = pair_parts[0].uri_decode().replace("+", " ")
		var value: String = "" if pair_parts.size() < 2 else pair_parts[1].uri_decode().replace("+", " ")
		if parameters.has(key):
			return {"ok": false, "code": "duplicate_parameter"}
		parameters[key] = value
	if parameters.has("access_token") or parameters.has("refresh_token"):
		return {"ok": false, "code": "implicit_flow_rejected"}
	if parameters.has("error"):
		return {"ok": false, "code": "provider_error", "state": str(parameters.get("state", ""))}
	var auth_code: String = str(parameters.get("code", ""))
	var returned_state: String = str(parameters.get("state", ""))
	if auth_code.is_empty() or returned_state.is_empty():
		return {"ok": false, "code": "missing_code_or_state"}
	return {"ok": true, "code": auth_code, "state": returned_state}


func start_google_login() -> bool:
	if _test_mode or OS.get_environment("GLINT_RUSH_TEST") == "1":
		_set_state("error", {}, "Login de red deshabilitado durante las pruebas.")
		return false
	if not OnlineService.is_configured():
		_set_state("offline", {}, "Falta la URL o la clave pública de Supabase. Podés jugar localmente.")
		return false
	if _bridge == null or not _bridge.has_java_method("openExternalUrl") or not _bridge.has_java_method("storeSecureValue"):
		_set_state("error", {}, "El complemento Android seguro no está instalado. El juego local sigue disponible.")
		return false
	var verifier: String = generate_code_verifier()
	var state: String = generate_state()
	if verifier.is_empty() or state.is_empty():
		_set_state("error", {}, "No se pudo preparar una solicitud OAuth segura.")
		return false
	var authorization_url: String = build_authorization_url(OnlineService.backend_url, verifier, state)
	if authorization_url.is_empty():
		_set_state("error", {}, "No se pudo construir la solicitud OAuth.")
		return false
	if not _store_secure_value(SECURE_VERIFIER_KEY, verifier) or not _store_secure_value(SECURE_STATE_KEY, state):
		_clear_pending_pkce()
		_set_state("error", {}, "Android no pudo guardar de forma segura la solicitud. No se guardó ningún token.")
		return false
	_code_verifier = verifier
	_expected_state = state
	_browser_waiting = true
	_set_state("authenticating", {}, "Continuá en el navegador. También podés volver y jugar sin cuenta.")
	var opened: bool = bool(_bridge.call("openExternalUrl", authorization_url))
	if not opened:
		_browser_waiting = false
		_clear_pending_pkce()
		_set_state("error", {}, "No se pudo abrir el navegador. El juego local sigue disponible.")
		return false
	return true


func _poll_auth_callback() -> void:
	if _bridge == null or not _bridge.has_java_method("popAuthCallback"):
		return
	var callback_url: String = str(_bridge.call("popAuthCallback"))
	if not callback_url.is_empty() and not _callback_in_flight:
		_callback_in_flight = true
		_browser_waiting = false
		call_deferred("_complete_auth_callback", callback_url)


func _check_browser_return() -> void:
	await get_tree().create_timer(0.35).timeout
	_poll_auth_callback()
	await get_tree().create_timer(0.55).timeout
	_poll_auth_callback()
	if _browser_waiting and not _callback_in_flight:
		_browser_waiting = false
		_clear_pending_pkce()
		_set_state("unauthenticated", {}, "Login cancelado. Podés jugar sin cuenta.")


func _complete_auth_callback(callback_url: String) -> void:
	var parsed: Dictionary = parse_callback_url(callback_url)
	if not bool(parsed.get("ok", false)):
		_clear_pending_pkce()
		_callback_in_flight = false
		var message: String = "Google canceló el login." if str(parsed.get("code", "")) == "provider_error" else "No se pudo validar el callback OAuth. Podés jugar sin cuenta."
		_set_state("unauthenticated", {}, message)
		return
	if _expected_state.is_empty():
		_expected_state = _load_secure_value(SECURE_STATE_KEY)
	if _code_verifier.is_empty():
		_code_verifier = _load_secure_value(SECURE_VERIFIER_KEY)
	if _expected_state.is_empty() or str(parsed.get("state", "")) != _expected_state or _code_verifier.is_empty():
		_clear_pending_pkce()
		_callback_in_flight = false
		_set_state("error", {}, "El callback no coincide con el login iniciado. Volvé a intentarlo.")
		return
	var request_body: Dictionary = {"auth_code": str(parsed.get("code", "")), "code_verifier": _code_verifier}
	var result: Dictionary = await OnlineService.request_json_async(HTTPClient.METHOD_POST, "/auth/v1/token?grant_type=pkce", request_body, "")
	_clear_pending_pkce()
	_callback_in_flight = false
	if not bool(result.get("ok", false)):
		_set_state("offline" if int(result.get("status", 0)) == 0 else "error", {}, "Supabase no pudo completar el login. Revisá la conexión y volvé a intentarlo.")
		return
	await _accept_session_response(result.get("data", null), false)


func _restore_saved_session() -> void:
	if _bridge == null or not _bridge.has_java_method("getSecureValue"):
		return
	_refresh_token = _load_secure_value(SECURE_REFRESH_KEY)
	if _refresh_token.is_empty():
		return
	await _refresh_saved_session(true)


func _refresh_saved_session(restoring: bool) -> void:
	if _refresh_in_flight or _refresh_token.is_empty():
		return
	_refresh_in_flight = true
	if restoring:
		_set_state("refreshing", {}, "Restaurando sesión segura…")
	var result: Dictionary = await OnlineService.request_json_async(HTTPClient.METHOD_POST, "/auth/v1/token?grant_type=refresh_token", {"refresh_token": _refresh_token}, "")
	_refresh_in_flight = false
	if not bool(result.get("ok", false)):
		var status_code: int = int(result.get("status", 0))
		if status_code == 400 or status_code == 401:
			_remove_secure_value(SECURE_REFRESH_KEY)
			_refresh_token = ""
			OnlineService.set_access_token("", 0)
			_set_state("unauthenticated", {}, "La sesión venció. Podés volver a iniciar sesión o jugar sin cuenta.")
		else:
			_restore_attempt_elapsed = 0.0
			var detail: String = "No hay conexión para renovar la sesión. El juego local sigue disponible."
			if OnlineService.has_authenticated_session():
				_set_state("authenticated", profile, detail)
			else:
				_set_state("offline", {}, detail)
		return
	await _accept_session_response(result.get("data", null), true)


func _accept_session_response(response_data: Variant, is_refresh: bool) -> void:
	if not response_data is Dictionary:
		_set_state("error", {}, "Supabase devolvió una respuesta de sesión inválida.")
		return
	var session_data: Dictionary = response_data
	var access_token: String = str(session_data.get("access_token", ""))
	var returned_refresh_token: String = str(session_data.get("refresh_token", ""))
	var expires_in: int = int(session_data.get("expires_in", 0))
	var user_value: Variant = session_data.get("user", {})
	var user: Dictionary = user_value if user_value is Dictionary else {}
	var user_id: String = str(user.get("id", ""))
	if access_token.is_empty() or user_id.is_empty() or expires_in <= 0:
		_set_state("error", {}, "La respuesta de Supabase no contiene una sesión válida.")
		return
	if not returned_refresh_token.is_empty():
		_refresh_token = returned_refresh_token
	OnlineService.set_access_token(access_token, int(Time.get_unix_time_from_system()) + expires_in)
	session_persisted = false
	if not _refresh_token.is_empty():
		session_persisted = _store_secure_value(SECURE_REFRESH_KEY, _refresh_token)
	if not session_persisted:
		# Keep this session only in memory; never downgrade to plaintext storage.
		_set_state("authenticated", {"display_name": "", "handle": "", "user_id": user_id}, "Sesión activa solo en memoria; Android no confirmó el guardado seguro.")
	var profile_result: Dictionary = await OnlineService.request_json_async(
		HTTPClient.METHOD_GET,
		"/rest/v1/profiles?select=id%2Cdisplay_name%2Chandle&id=eq." + user_id + "&limit=1",
		null,
		access_token
	)
	if not bool(profile_result.get("ok", false)):
		var profile_message: String = "Sesión iniciada, pero el perfil todavía no respondió. El juego local sigue disponible."
		_set_state("authenticated", {"display_name": "", "handle": "", "user_id": user_id}, profile_message)
		return
	var rows_value: Variant = profile_result.get("data", null)
	if not rows_value is Array or rows_value.is_empty():
		_set_state("authenticated", {"display_name": "", "handle": "", "user_id": user_id}, "Sesión activa; el perfil aún no aparece. El juego local sigue disponible.")
		return
	var first_row_value: Variant = rows_value[0]
	if not first_row_value is Dictionary:
		_set_state("authenticated", {"display_name": "", "handle": "", "user_id": user_id}, "Sesión activa; la respuesta del perfil no es válida.")
		return
	var profile_row: Dictionary = first_row_value
	if str(profile_row.get("id", "")) != user_id:
		_set_state("error", {}, "El perfil recibido no coincide con la cuenta autenticada.")
		return
	profile = {"user_id": user_id, "display_name": str(profile_row.get("display_name", "Jugador")), "handle": str(profile_row.get("handle", ""))}
	_set_state("authenticated", profile, "Sesión segura restaurada." if is_refresh else ("Conectado a GLINT RUSH." if session_persisted else "Sesión activa solo hasta cerrar la app."))
	# The RPC throttles updates, so restore/login is bounded to one write per 15 minutes.
	await OnlineService.request_json_async(HTTPClient.METHOD_POST, "/rest/v1/rpc/touch_current_profile_last_seen", {}, access_token)


func ensure_access_token() -> bool:
	if OnlineService.has_authenticated_session():
		var remaining_seconds: int = OnlineService.get_access_token_expires_at() - int(Time.get_unix_time_from_system())
		if remaining_seconds > REFRESH_SKEW_SECONDS:
			return true
	if _refresh_token.is_empty():
		return false
	await _refresh_saved_session(false)
	return OnlineService.has_authenticated_session()


func logout() -> void:
	var access_token: String = OnlineService.get_access_token()
	if not access_token.is_empty() and OnlineService.is_configured():
		await OnlineService.request_json_async(HTTPClient.METHOD_POST, "/auth/v1/logout", {}, access_token)
	_remove_secure_value(SECURE_REFRESH_KEY)
	_clear_pending_pkce()
	_refresh_token = ""
	profile.clear()
	session_persisted = false
	OnlineService.set_access_token("", 0)
	_set_state("unauthenticated", {}, "Sesión cerrada. Podés seguir jugando localmente.")


func _store_secure_value(key: String, value: String) -> bool:
	if _bridge == null or not _bridge.has_java_method("storeSecureValue"):
		return false
	return bool(_bridge.call("storeSecureValue", key, value))


func _load_secure_value(key: String) -> String:
	if _bridge == null or not _bridge.has_java_method("getSecureValue"):
		return ""
	return str(_bridge.call("getSecureValue", key))


func _remove_secure_value(key: String) -> void:
	if _bridge != null and _bridge.has_java_method("removeSecureValue"):
		_bridge.call("removeSecureValue", key)


func _clear_pending_pkce() -> void:
	_code_verifier = ""
	_expected_state = ""
	_remove_secure_value(SECURE_VERIFIER_KEY)
	_remove_secure_value(SECURE_STATE_KEY)


func _set_state(new_state: String, profile_data: Dictionary, detail: String) -> void:
	auth_state = new_state
	profile = profile_data.duplicate(true)
	last_auth_detail = detail
	auth_state_changed.emit(auth_state, profile, detail)
