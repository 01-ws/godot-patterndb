@tool
class_name PdbWebIo
extends RefCounted

static var _upload_cb
static var _on_upload: Callable

static func is_web() -> bool:
	return OS.has_feature("web")

static func download_bytes(bytes: PackedByteArray, filename: String, mime := "application/octet-stream") -> void:
	if not is_web():
		return
	JavaScriptBridge.download_buffer(bytes, filename, mime)

static func download_text(text: String, filename: String, mime := "text/plain") -> void:
	download_bytes(text.to_utf8_buffer(), filename, mime)

static func begin_upload(accept: String, on_bytes: Callable) -> void:
	if not is_web():
		return
	_on_upload = on_bytes
	_upload_cb = JavaScriptBridge.create_callback(_on_upload_done)
	var window = JavaScriptBridge.get_interface("window")
	window.pdbUploadCallback = _upload_cb
	var js := """
	(function(){
		var input = document.createElement('input');
		input.type = 'file';
		input.accept = '__ACCEPT__';
		input.style.display = 'none';
		input.addEventListener('change', function(e){
			var file = e.target.files[0];
			if (!file) { return; }
			var reader = new FileReader();
			reader.onload = function(){
				var s = reader.result;
				var comma = s.indexOf(',');
				var b64 = comma >= 0 ? s.substring(comma + 1) : s;
				window.pdbUploadCallback(file.name, b64);
			};
			reader.readAsDataURL(file);
		});
		document.body.appendChild(input);
		input.click();
		setTimeout(function(){ if (input.parentNode) { input.parentNode.removeChild(input); } }, 5000);
	})();
	""".replace("__ACCEPT__", accept)
	JavaScriptBridge.eval(js, true)

static func _on_upload_done(args: Array) -> void:
	var filename: String = String(args[0]) if args.size() > 0 else "upload"
	var b64: String = String(args[1]) if args.size() > 1 else ""
	var bytes := Marshalls.base64_to_raw(b64)
	if _on_upload.is_valid():
		_on_upload.call(filename, bytes)

static func filters_to_accept(filters: Array) -> String:
	var exts: Array[String] = []
	for f in filters:
		if f is Array and f.size() > 0:
			for part in String(f[0]).split(","):
				var e := part.strip_edges().trim_prefix("*")
				if e != "" and not exts.has(e):
					exts.append(e)
	return ",".join(exts)
