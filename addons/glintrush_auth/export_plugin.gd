@tool
extends EditorPlugin

var android_export_plugin: EditorExportPlugin


func _enter_tree() -> void:
	android_export_plugin = AndroidAuthExportPlugin.new()
	add_export_plugin(android_export_plugin)


func _exit_tree() -> void:
	remove_export_plugin(android_export_plugin)
	android_export_plugin = null


class AndroidAuthExportPlugin extends EditorExportPlugin:
	const AAR_PATH := "res://addons/glintrush_auth/bin/glintrush-auth.aar"

	func _get_name() -> String:
		return "GLINT RUSH Android Auth"

	func _supports_platform(platform: EditorExportPlatform) -> bool:
		return platform is EditorExportPlatformAndroid

	func _get_android_libraries(_platform: EditorExportPlatform, _debug: bool) -> PackedStringArray:
		return PackedStringArray([AAR_PATH])


	func _get_android_manifest_activity_element_contents(_platform: EditorExportPlatform, _debug: bool) -> String:
		return """
<intent-filter>
    <action android:name="android.intent.action.VIEW" />
    <category android:name="android.intent.category.DEFAULT" />
    <category android:name="android.intent.category.BROWSABLE" />
    <data android:scheme="glintrush" android:host="auth" android:path="/callback" />
</intent-filter>
"""
