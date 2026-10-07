extends Node

signal online_status_changed(status: String, detail: String)
signal request_succeeded(request_id: int, status_code: int, data: Variant)
signal request_failed(request_id: int, status_code: int, code: String, detail: String)
signal round_observed(client_match_id: String, phase: String)

const ONLINE_CONTRACT = preload("res://scripts/online_contract.gd")
const CONFIG_RESOURCE_PATH := "res://backend_config.cfg"
const CONFIG_USER_PATH := "user://backend_config.cfg"
const HTTP_TIMEOUT_SECONDS := 8.0
const MAX_RETRY_DELAY_SECONDS := 2.0

var backend_url := ""
var public_key := ""
var service_status := "unconfigured"
var last_status_detail := "Backend is not configured"
var last_client_match_id := ""
var last_match_phase := ""
var _next_request_id := 1
var _access_token := ""
var _refresh_token := ""
var _access_token_expires_at := 0
var _active_match_session_id := ""
var _test_mode := false


func _ready() -> void:
	_test_mode = OS.get_environment("GLINT_RUSH_TEST") == "1"
	_load_backend_config()


func _load_backend_config() -> void:
	var config := ConfigFile.new()
	var loaded := false
	if config.load(CONFIG_RESOURCE_PATH) == OK:
		loaded = true
	elif config.load(CONFIG_USER_PATH) == OK:
		loaded = true
	if loaded:
		backend_url = str(config.get_value("supabase", "url", "")).strip_edges().trim_suffix("/")
		public_key = str(config.get_value("supabase", "public_key", "")).strip_edges()
	if backend_url.is_empty():
		backend_url = OS.get_environment("SUPABASE_URL").strip_edges().trim_suffix("/")
	if public_key.is_empty():
		public_key = OS.get_environment("SUPABASE_PUBLIC_KEY").strip_edges()
	if _is_allowed_backend_url(backend_url) and not public_key.is_empty() and not _looks_like_secret_key(public_key):
		_set_status("idle", "Backend configuration loaded; no request is required for local play")
	else:
		backend_url = ""
		public_key = ""
		_set_status("unconfigured", "Set a Supabase URL and public key; secret keys are rejected")


func _looks_like_secret_key(key: String) -> bool:
	var lowered := key.to_lower()
	if lowered.begins_with("sb_secret_") or lowered.contains("service_role"):
		return true
	var parts := key.split(".")
	if parts.size() != 3:
		return false
	var encoded_payload := parts[1].replace("-", "+").replace("_", "/")
	while encoded_payload.length() % 4 != 0:
		encoded_payload += "="
	var decoded_payload := Marshalls.base64_to_raw(encoded_payload)
	var payload: Variant = JSON.parse_string(decoded_payload.get_string_from_utf8())
	return payload is Dictionary and str(payload.get("role", "")) == "service_role"


func _is_allowed_backend_url(url: String) -> bool:
	if url.begins_with("https://"):
		return true
	# Supabase local development uses loopback HTTP. Never allow cleartext HTTP
	# to a non-loopback host from a release build.
	for loopback_host in ["http://localhost", "http://127.0.0.1", "http://[::1]"]:
		if url == loopback_host or url.begins_with(loopback_host + ":"):
			return true
	return false


func is_configured() -> bool:
	return not backend_url.is_empty() and not public_key.is_empty()


func has_authenticated_session() -> bool:
	return not _access_token.is_empty() and _access_token_expires_at > int(Time.get_unix_time_from_system())


func set_access_token(access_token: String, expires_at_unix: int) -> void:
	_access_token = access_token
	_access_token_expires_at = expires_at_unix if not access_token.is_empty() else 0
	if access_token.is_empty():
		_active_match_session_id = ""


func get_access_token() -> String:
	return _access_token if has_authenticated_session() else ""


func get_access_token_expires_at() -> int:
	return _access_token_expires_at


func request_json_async(method: int, path: String, payload: Variant = null, bearer_token: String = "", extra_headers: PackedStringArray = PackedStringArray()) -> Dictionary:
	if _test_mode or OS.get_environment("GLINT_RUSH_TEST") == "1":
		return {"ok": false, "status": 0, "error": "test_mode", "data": null}
	if not is_configured():
		return {"ok": false, "status": 0, "error": "not_configured", "data": null}
	if not path.begins_with("/") or path.contains("://"):
		return {"ok": false, "status": 0, "error": "invalid_path", "data": null}
	var http := HTTPRequest.new()
	http.timeout = HTTP_TIMEOUT_SECONDS
	add_child(http)
	var headers := PackedStringArray(["apikey: " + public_key, "Accept: application/json"])
	if not bearer_token.is_empty():
		headers.append("Authorization: Bearer " + bearer_token)
	if payload != null:
		headers.append("Content-Type: application/json")
	for header in extra_headers:
		if not header.contains("\n") and not header.contains("\r") and header.find(":") > 0:
			headers.append(header)
	var body := "" if payload == null else JSON.stringify(payload)
	var transport_result: int = int(http.request(backend_url + path, headers, method, body))
	if transport_result != OK:
		http.queue_free()
		return {"ok": false, "status": 0, "error": "network_error", "data": null}
	var response: Array = await http.request_completed
	http.queue_free()
	var request_result: int = int(response[0])
	var status_code: int = int(response[1])
	var response_bytes: PackedByteArray = response[3]
	if request_result != HTTPRequest.RESULT_SUCCESS:
		return {"ok": false, "status": 0, "error": "network_error", "data": null}
	var parsed: Variant = null
	if not response_bytes.is_empty():
		var parser := JSON.new()
		if parser.parse(response_bytes.get_string_from_utf8()) != OK:
			return {"ok": false, "status": status_code, "error": "invalid_json", "data": null}
		parsed = parser.data
	var succeeded: bool = status_code >= 200 and status_code < 300
	return {"ok": succeeded, "status": status_code, "error": "" if succeeded else "http_error", "data": parsed}


func request_authenticated_json(method: int, path: String, payload: Variant = null) -> Dictionary:
	var token_ready: bool = await AuthService.ensure_access_token()
	if not token_ready:
		return {"ok": false, "status": 0, "error": "unauthenticated", "data": null}
	return await request_json_async(method, path, payload, get_access_token())


func has_ranked_match_session() -> bool:
	return has_authenticated_session() and not _active_match_session_id.is_empty()


func on_round_started(client_match_id: String, game_version: String, protocol_version: int) -> void:
	last_client_match_id = client_match_id
	last_match_phase = "started"
	_active_match_session_id = ""
	round_observed.emit(client_match_id, "started")
	# Deliberately no network request in this phase. Auth and start_match are later work.
	if game_version != ONLINE_CONTRACT.GAME_VERSION or protocol_version != ONLINE_CONTRACT.ONLINE_PROTOCOL_VERSION:
		push_warning("Round metadata does not match the centralized online contract")


func on_round_finished(client_match_id: String, final_score: int, game_version: String, protocol_version: int, match_session_id: String) -> void:
	if client_match_id.is_empty() or client_match_id != last_client_match_id:
		return
	last_match_phase = "finished"
	round_observed.emit(client_match_id, "finished")
	# Never submit a score until a real authenticated session and server-issued
	# match_session exist. No credentials or fake session are created in this phase.
	if not has_authenticated_session() or match_session_id.is_empty() or not has_ranked_match_session():
		return
	# Future: send an idempotent submit_match request here. Kept intentionally
	# unimplemented so this foundation cannot accept an unvalidated client score.
	var _unused := [final_score, game_version, protocol_version]


func request_json(method: int, path: String, payload: Variant = null, bearer_token: String = "", max_retries: int = 0, idempotency_key: String = "") -> int:
	var request_id := _next_request_id
	_next_request_id += 1
	if _test_mode or OS.get_environment("GLINT_RUSH_TEST") == "1":
		request_failed.emit(request_id, 0, "test_mode", "Network requests are disabled during smoke tests")
		return request_id
	if not is_configured():
		_set_status("unconfigured", "Backend URL or public key is missing")
		request_failed.emit(request_id, 0, "not_configured", "No backend request was sent")
		return request_id
	if not path.begins_with("/") or path.contains("://"):
		request_failed.emit(request_id, 0, "invalid_path", "Use a relative API path beginning with /")
		return request_id
	var retry_count := clampi(max_retries, 0, 3)
	if method != HTTPClient.METHOD_GET and method != HTTPClient.METHOD_HEAD and idempotency_key.is_empty():
		retry_count = 0
	call_deferred("_perform_request", request_id, method, path, payload, bearer_token, retry_count, idempotency_key)
	return request_id


func _perform_request(request_id: int, method: int, path: String, payload: Variant, bearer_token: String, retry_count: int, idempotency_key: String) -> void:
	var attempt := 0
	while attempt <= retry_count:
		var http := HTTPRequest.new()
		http.timeout = HTTP_TIMEOUT_SECONDS
		add_child(http)
		var headers := PackedStringArray(["apikey: " + public_key, "Accept: application/json"])
		var request_body := ""
		if payload != null:
			headers.append("Content-Type: application/json")
			request_body = JSON.stringify(payload)
		var effective_bearer: String = bearer_token
		if effective_bearer.is_empty() and has_authenticated_session():
			effective_bearer = _access_token
		if not effective_bearer.is_empty():
			headers.append("Authorization: Bearer " + effective_bearer)
		if not idempotency_key.is_empty():
			headers.append("Idempotency-Key: " + idempotency_key)
		var request_error := http.request(backend_url + path, headers, method, request_body)
		var result_code := int(request_error)
		var status_code := 0
		var response_body := PackedByteArray()
		if request_error == OK:
			var response: Array = await http.request_completed
			result_code = int(response[0])
			status_code = int(response[1])
			response_body = response[3]
		http.queue_free()
		var parsed: Variant = null
		var json_valid := true
		if not response_body.is_empty():
			var json_parser := JSON.new()
			var parse_result := json_parser.parse(response_body.get_string_from_utf8())
			json_valid = parse_result == OK
			if json_valid:
				parsed = json_parser.data
		var success := result_code == HTTPRequest.RESULT_SUCCESS and status_code >= 200 and status_code < 300 and json_valid
		if success:
			_set_status("online", "Last backend request succeeded")
			request_succeeded.emit(request_id, status_code, parsed)
			return
		var retryable := result_code != HTTPRequest.RESULT_SUCCESS or status_code == 408 or status_code == 429 or status_code >= 500
		if not retryable or attempt >= retry_count:
			if result_code == HTTPRequest.RESULT_SUCCESS:
				_set_status("online", "Backend responded; request was rejected or returned invalid data")
			else:
				_set_status("offline", "Backend request failed; local play remains available")
			var error_code := "network_error" if result_code != HTTPRequest.RESULT_SUCCESS else ("invalid_json" if not json_valid else "http_error")
			var detail := "Transport result %d" % result_code if result_code != HTTPRequest.RESULT_SUCCESS else ("Backend response was not valid JSON" if not json_valid else "Backend returned HTTP %d" % status_code)
			request_failed.emit(request_id, status_code, error_code, detail)
			return
		attempt += 1
		await get_tree().create_timer(minf(0.35 * pow(2.0, float(attempt - 1)), MAX_RETRY_DELAY_SECONDS)).timeout


func _set_status(status: String, detail: String) -> void:
	if service_status == status and last_status_detail == detail:
		return
	service_status = status
	last_status_detail = detail
	online_status_changed.emit(status, detail)
