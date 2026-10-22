extends Node

var banks: Dictionary = {}
var tiers: Dictionary = {}
var imported_ids: Dictionary = {}
var recent_ids: Array[String] = []

const GRADE_LABELS: Dictionary = {
	"primary": "小学", "junior": "初中", "senior": "高中", "college": "大学",
}
const SUBJECT_LABELS: Dictionary = {
	"math": "数学", "chinese": "语文", "english": "英语",
	"physics": "物理", "chemistry": "化学", "biology": "生物",
	"calculus": "高数", "linear": "线代",
}

const TIER_LABELS: Dictionary = {
	1: "小学", 2: "初低", 3: "初高", 4: "高一二", 5: "高三", 6: "大学", 7: "打趣",
}
const TIER_GRADE: Dictionary = {
	1: "primary", 2: "junior", 3: "junior", 4: "senior", 5: "senior", 6: "college", 7: "senior",
}
const TIER_WEIGHTS: Array[int] = [31, 23, 16, 13, 8, 6, 3]
const WARMUP_COUNT := 3
const RECENT_MAX := 12

func _ready() -> void:
	_load_builtin()

func get_grades() -> Array:
	return GRADE_LABELS.keys()

func get_grade_label(g: String) -> String:
	return GRADE_LABELS.get(g, g)

func get_subjects(grade: String) -> Array:
	var s: Dictionary = banks.get(grade, {})
	return s.keys()

func get_subject_label(grade: String, s: String) -> String:
	return SUBJECT_LABELS.get(s, s)

func get_tier_label(t: int) -> String:
	return TIER_LABELS.get(t, str(t))

func get_question_count(grade: String, subject: String) -> int:
	var arr: Array = _questions_of(grade, subject)
	return arr.size()

func get_tier_count(t: int) -> int:
	var arr: Array = tiers.get(t, [])
	return arr.size()

func get_total_count() -> int:
	var total := 0
	for t in tiers:
		total += tiers[t].size()
	return total

func pick_question(grade: String, subjects: Array, exclude: Dictionary = {}) -> Dictionary:
	var pool: Array = []
	for s in subjects:
		for q in _questions_of(grade, s):
			if not exclude.has(q.get("id", "")):
				pool.append(q)
	if pool.is_empty():
		for s in subjects:
			pool.append_array(_questions_of(grade, s))
	if pool.is_empty():
		return {}
	var picked: Dictionary = pool.pick_random()
	_ensure_choice(picked)
	return picked

func pick_tiered(answered_in_level: int = 0, tier_shift: int = 0) -> Dictionary:
	var weights := _shifted_weights(tier_shift)
	var allowed: Array[int] = []
	if answered_in_level < WARMUP_COUNT:
		allowed = [1, 2]
	var picked_tier := _roll_tier(weights, allowed)
	var q := _take_from_tier(picked_tier)
	if q.is_empty():
		for t in _tier_order(weights, allowed):
			q = _take_from_tier(t)
			if not q.is_empty():
				break
	if q.is_empty():
		return {}
	_ensure_choice(q)
	_note_recent(String(q.get("id", "")))
	return q

func reset_recent() -> void:
	recent_ids.clear()

func import_text(text: String, filename: String = "") -> Dictionary:
	var lower := filename.to_lower()
	if lower.ends_with(".json") or text.strip_edges().begins_with("{"):
		return import_json(text)
	return import_csv(text)

func import_json(text: String) -> Dictionary:
	var data = JSON.parse_string(text)
	if data == null:
		return {"ok": false, "error": "JSON 解析失败"}
	var added := 0
	var root: Dictionary = data
	if root.has("questions") and root["questions"] is Array:
		for q in root["questions"]:
			if _add_question(q): added += 1
	elif root.has("grades") and root["grades"] is Dictionary:
		for grade: String in root["grades"]:
			var gdata: Dictionary = root["grades"][grade]
			if not (gdata is Dictionary): continue
			var subs: Dictionary = gdata.get("subjects", gdata)
			for subject: String in subs:
				var sdata = subs[subject]
				if sdata is Dictionary: sdata = sdata.get("questions", [])
				if sdata is Array:
					for q in sdata:
						if _add_question(q, grade, subject): added += 1
	else:
		for grade: String in root:
			if not (grade is String): continue
			var gdata = root[grade]
			if not (gdata is Dictionary): continue
			for subject: String in gdata:
				var sdata = gdata[subject]
				if sdata is Array:
					for q in sdata:
						if _add_question(q, grade, subject): added += 1
	return {"ok": true, "added": added}

func import_csv(text: String) -> Dictionary:
	var lines := text.split("\n")
	if lines.size() < 2:
		return {"ok": false, "error": "CSV 至少需要表头和一行数据"}
	var header: PackedStringArray = lines[0].split(",", true)
	for i in header.size(): header[i] = header[i].strip_edges().to_lower()
	var idx := {}
	for key in ["grade", "subject", "type", "prompt", "opt1", "opt2", "opt3", "opt4", "answer", "explain", "tier"]:
		idx[key] = header.find(key)
	if idx["prompt"] < 0 or idx["answer"] < 0:
		return {"ok": false, "error": "CSV 必须包含 prompt 和 answer 列"}
	var added := 0
	for li in range(1, lines.size()):
		var line := lines[li].strip_edges()
		if line.is_empty(): continue
		var cols := line.split(",", true)
		if cols.size() < 2: continue
		var q := {}
		for key in idx:
			var ci: int = idx[key]
			if ci >= 0 and ci < cols.size():
				q[key] = cols[ci].strip_edges()
		if _add_question(q): added += 1
	return {"ok": true, "added": added}

func _add_question(raw, grade: String = "", subject: String = "") -> bool:
	if not (raw is Dictionary): return false
	var q: Dictionary = raw.duplicate()
	var g: String = String(q.get("grade", grade))
	var s: String = String(q.get("subject", subject))
	if g.is_empty() or s.is_empty(): return false
	if not GRADE_LABELS.has(g): g = "junior"
	if not SUBJECT_LABELS.has(s): s = "math"
	var prompt := String(q.get("prompt", q.get("question", ""))).strip_edges()
	if prompt.is_empty(): return false
	var answer := String(q.get("answer", "")).strip_edges()
	if answer.is_empty(): return false
	var options: Array = []
	var raw_opts = q.get("options", q.get("opts", []))
	if raw_opts is Array:
		for o in raw_opts: options.append(String(o))
	else:
		for k in ["opt1", "opt2", "opt3", "opt4"]:
			if q.has(k) and String(q[k]).strip_edges() != "":
				options.append(String(q[k]).strip_edges())
	var qid := String(q.get("id", "%s_%s_%d" % [g, s, randi()]))
	if imported_ids.has(qid): return false
	imported_ids[qid] = true
	if not banks.has(g): banks[g] = {}
	if not banks[g].has(s): banks[g][s] = []
	var entry := {
		"id": qid, "grade": g, "subject": s,
		"type": String(q.get("type", "choice" if options.size() >= 2 else "fill")),
		"prompt": prompt, "options": options, "answer": answer,
		"explain": String(q.get("explain", "")),
	}
	var tier := int(q.get("tier", 0))
	if tier < 1 or tier > 7:
		tier = _tier_for_grade(g)
	entry["tier"] = tier
	_ensure_choice(entry)
	banks[g][s].append(entry)
	if not tiers.has(tier): tiers[tier] = []
	tiers[tier].append(entry)
	return true

func _ensure_choice(q: Dictionary) -> void:
	if q.get("_prepared", false) == true:
		return
	var answer := String(q.get("answer", "")).strip_edges()
	if answer.is_empty():
		return
	var opts: Array = []
	var raw_opts = q.get("options", [])
	if raw_opts is Array:
		for o in raw_opts:
			var s := String(o).strip_edges()
			if not s.is_empty() and not opts.has(s):
				opts.append(s)
	var ai := opts.find(answer)
	if ai < 0:
		for o in opts:
			if String(o).to_lower() == answer.to_lower():
				answer = String(o)
				break
	if not opts.has(answer):
		opts = [answer]
	if opts.size() < 4:
		var d := _distractors(answer, String(q.get("grade", "junior")), String(q.get("subject", "math")))
		for x in d:
			var s := String(x).strip_edges()
			if s.is_empty() or opts.has(s):
				continue
			opts.append(s)
			if opts.size() == 4:
				break
	if opts.size() > 4:
		opts = opts.slice(0, 4)
		if not opts.has(answer):
			opts[3] = answer
	if opts.size() < 2:
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("%s|%s" % [String(q.get("id", "")), String(q.get("prompt", ""))])
	for i in range(opts.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp = opts[i]
		opts[i] = opts[j]
		opts[j] = tmp
	q["options"] = opts
	q["type"] = "choice"
	q["_prepared"] = true

func _distractors(answer: String, grade: String, subject: String) -> Array:
	var out: Array = []
	var seen := {answer: true}
	var cands: Array = []
	if answer.is_valid_float():
		if answer.is_valid_int():
			var ni := int(answer.to_float())
			var rev := String(answer).reverse()
			cands = [str(ni + 1), str(ni - 1)]
			if rev.is_valid_int() and str(rev.to_int()) == rev and rev != answer:
				cands.append(rev)
			cands.append_array([str(ni + 10), str(ni - 10), str(ni + 2), str(ni - 2), str(ni * 2)])
		else:
			var n := answer.to_float()
			cands = [
				str(snappedf(n + 0.1, 0.01)), str(snappedf(n - 0.1, 0.01)),
				str(snappedf(n + 0.5, 0.01)), str(snappedf(n - 0.5, 0.01)),
				str(snappedf(n + 1.0, 0.01)), str(snappedf(n - 1.0, 0.01)),
			]
	elif _is_fraction(answer):
		var slash := answer.find("/")
		var num := int(answer.substr(0, slash))
		var den := int(answer.substr(slash + 1))
		var base := float(num) / float(den)
		for pair in [[num + 1, den], [num - 1, den], [num, den + 1], [num + 1, den + 1], [num, den * 2]]:
			var cn := int(pair[0])
			var cd := int(pair[1])
			if cn <= 0 or cd <= 0 or is_equal_approx(float(cn) / float(cd), base):
				continue
			cands.append("%d/%d" % [cn, cd])
	else:
		var near: Array = []
		var far: Array = []
		for qq in _questions_of(grade, subject):
			var a := String(qq.get("answer", "")).strip_edges()
			if a.is_empty() or seen.has(a):
				continue
			if absi(a.length() - answer.length()) <= 2 and _same_lang(a, answer):
				near.append(a)
			else:
				far.append(a)
		cands = near + far
	for c in cands:
		var cs := String(c).strip_edges()
		if cs.is_empty() or cs == answer or seen.has(cs):
			continue
		seen[cs] = true
		out.append(cs)
		if out.size() == 3:
			return out
	for g in ["以上都不对", "无法确定", "没有正确答案"]:
		if out.size() >= 3:
			break
		if not seen.has(g):
			seen[g] = true
			out.append(g)
	return out.slice(0, 3)

func _same_lang(a: String, b: String) -> bool:
	return _has_cjk(a) == _has_cjk(b)

func _has_cjk(s: String) -> bool:
	for i in s.length():
		var u := s.unicode_at(i)
		if u >= 0x3400 and u <= 0x9FFF:
			return true
	return false

func _is_fraction(s: String) -> bool:
	var slash := s.find("/")
	if slash <= 0 or slash >= s.length() - 1:
		return false
	return s.substr(0, slash).is_valid_int() and s.substr(slash + 1).is_valid_int()

func _questions_of(grade: String, subject: String) -> Array:
	var g: Dictionary = banks.get(grade, {})
	return g.get(subject, [])

func _tier_for_grade(grade: String) -> int:
	match grade:
		"primary": return 1
		"junior": return 2
		"senior": return 4
		"college": return 6
	return 2

func _shifted_weights(shift: int) -> Array:
	var w: Array[int] = TIER_WEIGHTS.duplicate()
	if shift <= 0:
		return w
	var move := mini(8 * shift, 24)
	for i in 3:
		var cut := mini(move / 3, w[i] - 1)
		cut = maxi(cut, 0)
		w[i] -= cut
		move -= cut
		if move <= 0:
			break
	var targets: Array[int] = [4, 5, 6, 7]
	var ti := 0
	while move > 0:
		w[targets[ti % targets.size()]] += 1
		move -= 1
		ti += 1
	return w

func _roll_tier(weights: Array, allowed: Array) -> int:
	var total := 0
	for t in range(1, 8):
		if not allowed.is_empty() and not (t in allowed):
			continue
		total += weights[t - 1]
	if total <= 0:
		return 1
	var r := randi_range(0, total - 1)
	for t in range(1, 8):
		if not allowed.is_empty() and not (t in allowed):
			continue
		r -= weights[t - 1]
		if r < 0:
			return t
	return 1

func _tier_order(weights: Array, allowed: Array) -> Array[int]:
	var order: Array[int] = []
	var idx: Array[int] = []
	for t in range(1, 8):
		if not allowed.is_empty() and not (t in allowed):
			continue
		idx.append(t)
	idx.sort_custom(func(a, b): return weights[a - 1] > weights[b - 1])
	for t in idx:
		order.append(t)
	return order

func _take_from_tier(t: int) -> Dictionary:
	var arr: Array = tiers.get(t, [])
	if arr.is_empty():
		return {}
	var fresh: Array = []
	for q in arr:
		if not recent_ids.has(String(q.get("id", ""))):
			fresh.append(q)
	var pool := fresh if not fresh.is_empty() else arr
	return pool.pick_random()

func _note_recent(id: String) -> void:
	if id.is_empty():
		return
	recent_ids.append(id)
	if recent_ids.size() > RECENT_MAX:
		recent_ids.pop_front()

func _load_builtin() -> void:
	var file := FileAccess.open("res://data/questions.json", FileAccess.READ)
	if file == null:
		push_warning("内置题库加载失败")
		return
	var data = JSON.parse_string(file.get_as_text())
	if not (data is Dictionary):
		push_warning("内置题库格式错误")
		return
	banks = {}
	tiers = {}
	imported_ids = {}
	recent_ids.clear()
	if data.has("tiers") and data["tiers"] is Dictionary:
		_load_tiers(data["tiers"])
	elif data.has("grades") and data["grades"] is Dictionary:
		_load_grades(data["grades"])
	_enrich_all()

func _load_tiers(raw: Dictionary) -> void:
	for key in raw:
		var t := int(str(key))
		if t < 1 or t > 7:
			continue
		var tdata = raw[key]
		if not (tdata is Dictionary):
			continue
		var arr = tdata.get("questions", [])
		if not (arr is Array):
			continue
		tiers[t] = []
		for q in arr:
			if q is Dictionary:
				_make_entry(q, t)

func _load_grades(raw: Dictionary) -> void:
	for g in raw:
		var gdata = raw[g]
		if not (gdata is Dictionary):
			continue
		var subs = gdata.get("subjects", gdata)
		if not (subs is Dictionary):
			continue
		for s in subs:
			var sdata = subs[s]
			if sdata is Dictionary:
				sdata = sdata.get("questions", [])
			if not (sdata is Array):
				continue
			for q in sdata:
				if q is Dictionary:
					var entry := _make_entry(q, _tier_for_grade(String(g)), String(g), String(s))
					if entry.is_empty():
						continue

func _make_entry(raw: Dictionary, tier: int, grade: String = "", subject: String = "") -> Dictionary:
	var q: Dictionary = raw.duplicate()
	var prompt := String(q.get("prompt", q.get("question", ""))).strip_edges()
	if prompt.begins_with("填空："):
		prompt = prompt.substr(3).strip_edges()
	var answer := String(q.get("answer", "")).strip_edges()
	if prompt.is_empty() or answer.is_empty():
		return {}
	var g: String = String(q.get("grade", grade))
	if g.is_empty():
		g = String(TIER_GRADE.get(tier, "junior"))
	var s: String = String(q.get("subject", subject))
	if s.is_empty() or not SUBJECT_LABELS.has(s):
		s = "math"
	var options: Array = []
	var raw_opts = q.get("options", q.get("opts", []))
	if raw_opts is Array:
		for o in raw_opts:
			options.append(String(o))
	var qid := String(q.get("id", "t%d_%s_%d" % [tier, s, randi()]))
	if imported_ids.has(qid):
		return {}
	var entry := {
		"id": qid, "grade": g, "subject": s, "tier": tier,
		"type": String(q.get("type", "choice" if options.size() >= 2 else "fill")),
		"prompt": prompt, "options": options, "answer": answer,
		"explain": String(q.get("explain", "")),
	}
	imported_ids[qid] = true
	if not banks.has(g):
		banks[g] = {}
	if not banks[g].has(s):
		banks[g][s] = []
	banks[g][s].append(entry)
	if not tiers.has(tier):
		tiers[tier] = []
	tiers[tier].append(entry)
	return entry

func _enrich_all() -> void:
	for t in tiers:
		for q in tiers[t]:
			_ensure_choice(q)

func get_builtin_sample_csv() -> String:
	return "tier,grade,subject,type,prompt,opt1,opt2,opt3,opt4,answer\n1,primary,math,choice,1+1=?,0,1,2,3,2\n"
