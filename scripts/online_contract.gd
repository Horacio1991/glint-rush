extends RefCounted
class_name OnlineContract

# Bump GAME_VERSION when gameplay/scoring rules change. Bump the protocol only
# when the shape or meaning of client/backend messages changes.
const GAME_VERSION := "0.1.0"
const ONLINE_PROTOCOL_VERSION := 1


static func new_client_match_id() -> String:
	# UUIDv4 uses the platform CSPRNG and does not consume the gameplay RNG.
	var bytes := Crypto.new().generate_random_bytes(16)
	if bytes.size() != 16:
		push_error("Could not generate a client match UUID")
		return ""
	bytes[6] = (int(bytes[6]) & 0x0f) | 0x40
	bytes[8] = (int(bytes[8]) & 0x3f) | 0x80
	var hex := ""
	for value in bytes:
		hex += "%02x" % int(value)
	return "%s-%s-%s-%s-%s" % [
		hex.substr(0, 8),
		hex.substr(8, 4),
		hex.substr(12, 4),
		hex.substr(16, 4),
		hex.substr(20, 12),
	]
