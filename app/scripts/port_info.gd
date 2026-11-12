class_name PortInfo
## What to say about a port, from the backend's view of it.


static func job_running(p: Dictionary) -> bool:
	var job: Variant = p.get("job")
	return job is Dictionary and job.get("state") == "running"


static func installed(p: Dictionary) -> Dictionary:
	var i: Variant = p.get("installed")
	return i if i is Dictionary else {}


static func built(p: Dictionary) -> bool:
	return bool(installed(p).get("built", false))


static func latest_version(p: Dictionary) -> String:
	var l: Variant = p.get("latest")
	return str(l.get("version", "")) if l is Dictionary else ""


static func version_text(v: String) -> String:
	if v == "":
		return ""
	return v if v.begins_with("v") else "v" + v


## The state line and its colour.
static func status(p: Dictionary) -> Array:
	if job_running(p):
		var job: Dictionary = p["job"]
		var stage := str(job.get("stage", ""))
		var pct: Variant = job.get("percent")
		if pct != null:
			stage = "%s %d%%" % [stage, int(pct)]
		return [L.t("st_building", stage), UI.ACCENT]
	if not p.get("supported", false):
		return [L.t("st_launcher_only"), UI.MUTED]
	var i := installed(p)
	if i.is_empty():
		var job: Variant = p.get("job")
		if job is Dictionary and job.get("state") == "failed":
			return [L.t("st_failed"), UI.RED]
		return [L.t("st_not_installed"), UI.MUTED]
	if not built(p):
		return [L.t("st_unfinished"), UI.AMBER]
	if p.get("update", false):
		return [L.t("st_update", version_text(latest_version(p))), UI.AMBER]
	var v := version_text(str(i.get("version", "")))
	return [L.t("st_installed", v) if v != "" else L.t("st_installed", "").trim_suffix(" · "), UI.GREEN]


static func build_time(p: Dictionary) -> String:
	var m: Variant = p.get("build_minutes")
	if not m is Array or m.is_empty() or m[0] == null:
		return L.t("hour_plus")
	if m.size() < 2 or m[1] == null:
		return L.t("hour_plus") if int(m[0]) >= 60 else L.t("minutes_plus", int(m[0]))
	return L.t("minutes", [int(m[0]), int(m[1])])


static func needs(p: Dictionary) -> String:
	var parts: Array[String] = []
	var list: Variant = p.get("needs", [])
	if list is Array:
		if "iso" in list:
			var s := L.t("needs_iso")
			var disc := str(p.get("disc", ""))
			if disc != "":
				s += " (%s)" % disc
			parts.append(s)
		if "bios" in list:
			parts.append(L.t("needs_bios"))
	return ", ".join(parts) if not parts.is_empty() else L.t("needs_nothing")


## Release notes as plain lines: markdown marks taken out, headings and the install part dropped.
static func notes(p: Dictionary, max_lines := 8) -> Array[String]:
	var out: Array[String] = []
	var l: Variant = p.get("latest")
	if not l is Dictionary:
		return out
	var text := str(l.get("notes", ""))
	var started := false
	for raw in text.split("\n"):
		var line := raw.strip_edges()
		if line.begins_with("#"):
			if started:
				break   # only the first section ("What's new")
			continue
		if line == "":
			continue
		started = true
		line = line.trim_prefix("- ").trim_prefix("* ")
		line = line.replace("**", "").replace("`", "")
		var re := RegEx.create_from_string("\\[([^\\]]+)\\]\\([^)]+\\)")
		line = re.sub(line, "$1", true)
		out.append(line)
		if out.size() >= max_lines:
			break
	return out
