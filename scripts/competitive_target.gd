extends RefCounted

## Converts one authenticated weekly leaderboard response into a local-only
## target snapshot. No network or gameplay state is owned by this helper.

static func from_snapshot(entries: Array, request_succeeded: bool, local_best: int) -> Dictionary:
	if not request_succeeded:
		return local_fallback(local_best)

	var ranked: Array[Dictionary] = []
	for item in entries:
		if not item is Dictionary:
			continue
		var handle := str(item.get("handle", "")).strip_edges().trim_prefix("@")
		if handle.is_empty():
			handle = "jugador"
		ranked.append({
			"position": maxi(1, int(item.get("position", 0))),
			"handle": handle,
			"best_score": maxi(0, int(item.get("best_score", 0))),
			"is_me": bool(item.get("is_me", false)),
		})
	ranked.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a["position"]) < int(b["position"])
	)
	if ranked.is_empty():
		return local_fallback(local_best)

	var me_index := -1
	var player_position := 0
	for i in range(ranked.size()):
		if bool(ranked[i]["is_me"]):
			me_index = i
			player_position = int(ranked[i]["position"])
			break

	if me_index >= 0:
		var me: Dictionary = ranked[me_index]
		var my_position := int(me["position"])
		if my_position == 1:
			return _target(
				"weekly_record", "SUPERÁ TU RÉCORD SEMANAL", "@" + str(me["handle"]),
				int(me["best_score"]), true, false, my_position, my_position
			)
		if my_position <= 25:
			for entry in ranked:
				if int(entry["position"]) == my_position - 1:
					var is_leader := int(entry["position"]) == 1
					return _target(
						"rival", "A SUPERAR", "@" + str(entry["handle"]),
						int(entry["best_score"]), true, is_leader, int(entry["position"]), my_position
					)
			# An incomplete response should not create an invalid rank target.
			return local_fallback(local_best)

	var cutoff: Dictionary = {}
	for entry in ranked:
		if int(entry["position"]) == 25:
			cutoff = entry
			break
	if not cutoff.is_empty():
		return _target(
			"top25", "ENTRÁ AL TOP 25", "PUESTO #25",
			int(cutoff["best_score"]), true, false, 25, player_position
		)

	# Fewer than 25 ranked players means any positive score enters the Top 25.
	return _target("top25", "ENTRÁ AL TOP 25", "PUESTO DISPONIBLE", 0, true, false, 25, player_position)


static func local_fallback(local_best: int) -> Dictionary:
	return _target(
		"local_record", "SUPERÁ TU RÉCORD", "RÉCORD LOCAL",
		maxi(0, local_best), false, false, 0
	)


static func remaining(target: Dictionary, current_score: int) -> int:
	return maxi(0, int(target.get("target_score", 1)) - maxi(0, current_score))


static func is_reached(target: Dictionary, current_score: int) -> bool:
	return current_score >= int(target.get("target_score", 1))


static func completion_message(target: Dictionary) -> String:
	match str(target.get("mode", "local_record")):
		"rival":
			return "NUEVO #1 PROVISIONAL" if bool(target.get("target_is_leader", false)) else "¡OBJETIVO SUPERADO!"
		"top25":
			return "¡TOP 25 PROVISIONAL!"
		"weekly_record":
			return "¡NUEVO RÉCORD SEMANAL!"
		_:
			return "¡RÉCORD LOCAL SUPERADO!"


static func _target(mode: String, title: String, name: String, reference_score: int, online: bool, is_leader: bool, position: int, player_position := 0) -> Dictionary:
	return {
		"mode": mode,
		"title": title,
		"name": name,
		"reference_score": maxi(0, reference_score),
		# Beating a player/record requires one point more than their score.
		"target_score": maxi(1, reference_score + 1),
		"online": online,
		"target_is_leader": is_leader,
		"position": position,
		"player_position": player_position,
	}
