extends RefCounted
## 程序化小学数学题生成器（第一批：100 以内四则混合运算）。
##
## 设计原则：
## - 按需生成 1 题，不预生成题库池、不落盘，内存占用恒定；
## - 只在本局内存里记录已出的算式（_seen），重开一局调用 reset() 清空；
## - 生成的题目带 generated=true，options 已洗牌并保证 4 个不重复、含正确答案。

const SEEN_MAX := 300

## 档位规格：项数 + 数字/中间值/答案上限。
const SPECS: Dictionary = {
	1: {"terms": 2, "max": 20},
	2: {"terms": 2, "max": 20},
	3: {"terms": 3, "max": 50},
	4: {"terms": 3, "max": 50},
	5: {"terms": 3, "max": 100},
	6: {"terms": 3, "max": 100},
	7: {"terms": 3, "max": 100},
}

var _seen: Dictionary = {}
var _seen_order: Array[String] = []

func reset() -> void:
	_seen.clear()
	_seen_order.clear()

func spec_for(tier: int) -> Dictionary:
	return SPECS.get(clampi(tier, 1, 7), {"terms": 3, "max": 100})

## 生成一道题；失败返回 {}（调用方回退到固定题库）。
func make(tier: int) -> Dictionary:
	var spec: Dictionary = spec_for(tier)
	var term_count := int(spec["terms"])
	var max_v := int(spec["max"])
	for _attempt in 80:
		var built := _build(term_count, max_v)
		if built.is_empty():
			continue
		var terms: Array = built["terms"]
		var ops: Array = built["ops"]
		var key := _expr_key(terms, ops)
		if _seen.has(key):
			continue
		var ev := evaluate(terms, ops, max_v)
		if not bool(ev.get("ok", false)):
			continue
		var answer := int(ev["value"])
		if answer <= 0:
			continue
		var options := _make_options(terms, ops, answer, max_v)
		if options.size() != 4:
			continue
		_note_seen(key)
		return {
			"id": "gen_math_%s" % key.md5_text(),
			"grade": "primary",
			"subject": "math",
			"tier": clampi(tier, 1, 7),
			"type": "choice",
			"prompt": "%s = ?" % _expr_text(terms, ops),
			"options": options,
			"answer": str(answer),
			"explain": "",
			"generated": true,
			"_prepared": true,
		}
	return {}

## 按「先乘除后加减」求值，并校验每一步中间值都落在 0~max_v。
func evaluate(terms: Array, ops: Array, max_v: int) -> Dictionary:
	if terms.size() != ops.size() + 1 or terms.is_empty():
		return {"ok": false}
	var vals: Array = terms.duplicate()
	var o: Array = ops.duplicate()
	for v in vals:
		if not _valid_num(v, max_v):
			return {"ok": false}
	var i := 0
	while i < o.size():
		var op := String(o[i])
		if op != "×" and op != "÷":
			i += 1
			continue
		var a := int(vals[i])
		var b := int(vals[i + 1])
		var r := 0
		if op == "×":
			if a < 2 or b < 2:
				return {"ok": false}
			r = a * b
		else:
			if a < 2 or b < 2 or a % b != 0:
				return {"ok": false}
			r = a / b
			if r < 2:
				return {"ok": false}
		if r > max_v:
			return {"ok": false}
		vals[i] = r
		vals.remove_at(i + 1)
		o.remove_at(i)
	var cur := int(vals[0])
	for j in o.size():
		var op2 := String(o[j])
		var b2 := int(vals[j + 1])
		if op2 == "+":
			cur += b2
		elif op2 == "-":
			cur -= b2
		else:
			return {"ok": false}
		if cur < 0 or cur > max_v:
			return {"ok": false}
	return {"ok": true, "value": cur}

# ---------------------------------------------------------------- 构造算式

func _build(count: int, max_v: int) -> Dictionary:
	if count <= 2:
		var op := _pick_op()
		var pair := _pair_for(op, max_v)
		if pair.is_empty():
			return {}
		return {"terms": pair, "ops": [op]}
	var op1 := _pick_op()
	var op2 := _pick_op()
	if _is_mul(op1):
		var pair := _pair_for(op1, max_v)
		if pair.is_empty():
			return {}
		var r := _value_of(op1, int(pair[0]), int(pair[1]))
		var c := 0
		if _is_mul(op2):
			c = _right_for_mul(r, op2, max_v)
		else:
			c = _addend_for(r, op2, max_v)
		if c <= 0:
			return {}
		return {"terms": [pair[0], pair[1], c], "ops": [op1, op2]}
	if _is_mul(op2):
		var pair2 := _pair_for(op2, max_v)
		if pair2.is_empty():
			return {}
		var r2 := _value_of(op2, int(pair2[0]), int(pair2[1]))
		var a := 0
		if op1 == "+":
			if max_v - r2 < 1:
				return {}
			a = randi_range(1, max_v - r2)
		else:
			if r2 + 1 > max_v:
				return {}
			a = randi_range(r2 + 1, max_v)
		return {"terms": [a, pair2[0], pair2[1]], "ops": [op1, op2]}
	var a3 := randi_range(1, max_v)
	var b3 := _addend_for(a3, op1, max_v)
	if b3 <= 0:
		return {}
	var r3 := a3 + b3 if op1 == "+" else a3 - b3
	var c3 := _addend_for(r3, op2, max_v)
	if c3 <= 0:
		return {}
	return {"terms": [a3, b3, c3], "ops": [op1, op2]}

func _pick_op() -> String:
	var roll := randi_range(0, 10)
	if roll < 4:
		return "+"
	if roll < 7:
		return "-"
	if roll < 9:
		return "×"
	return "÷"

## 两项：a op b，结果与中间值都在 1~max_v。
func _pair_for(op: String, max_v: int) -> Array:
	if op == "+":
		if max_v < 2:
			return []
		var a := randi_range(1, max_v - 1)
		return [a, randi_range(1, max_v - a)]
	if op == "-":
		if max_v < 2:
			return []
		var a2 := randi_range(2, max_v)
		return [a2, randi_range(1, a2 - 1)]
	if max_v < 4:
		return []
	if op == "×":
		var a3 := randi_range(2, max_v / 2)
		return [a3, randi_range(2, max_v / a3)]
	var b := randi_range(2, max_v / 2)
	return [b * randi_range(2, max_v / b), b]

## 给加法/减法挑右操作数，返回 0 表示无解。
func _addend_for(v: int, op: String, max_v: int) -> int:
	if op == "+":
		if max_v - v < 1:
			return 0
		return randi_range(1, max_v - v)
	if v <= 1:
		return 0
	return randi_range(1, v - 1)

## 给乘/除挑右操作数，返回 0 表示无解。
func _right_for_mul(v: int, op: String, max_v: int) -> int:
	if op == "×":
		if v < 2:
			return 0
		var hi := max_v / v
		if hi < 2:
			return 0
		return randi_range(2, hi)
	var divs: Array[int] = []
	for y in range(2, v / 2 + 1):
		if v % y == 0 and v / y >= 2:
			divs.append(y)
	if divs.is_empty():
		return 0
	return int(divs.pick_random())

func _value_of(op: String, a: int, b: int) -> int:
	if op == "×":
		return a * b
	if op == "÷":
		return a / b
	return a + b if op == "+" else a - b

func _is_mul(op: String) -> bool:
	return op == "×" or op == "÷"

func _valid_num(v, max_v: int) -> bool:
	if not (v is int or v is float):
		return false
	var n := int(v)
	return n >= 0 and n <= max_v

# ---------------------------------------------------------------- 题干/选项

func _expr_text(terms: Array, ops: Array) -> String:
	var s := str(terms[0])
	for i in ops.size():
		s += " %s %s" % [String(ops[i]), str(terms[i + 1])]
	return s

func _expr_key(terms: Array, ops: Array) -> String:
	var s := str(terms[0])
	for i in ops.size():
		s += "%s%s" % [String(ops[i]), str(terms[i + 1])]
	return s

## 干扰项优先级：忽略优先级从左到右 → 交换一对运算符 → 抄错一位数字 → 邻近值兜底。
func _make_options(terms: Array, ops: Array, answer: int, max_v: int) -> Array:
	var cands: Array[int] = []
	var ltr := _left_to_right(terms, ops)
	if ltr > 0:
		cands.append(ltr)
	for i in ops.size():
		for j in range(i + 1, ops.size()):
			if String(ops[i]) == String(ops[j]):
				continue
			var swapped: Array = ops.duplicate()
			swapped[i] = ops[j]
			swapped[j] = ops[i]
			var ev := evaluate(terms, swapped, max_v)
			if bool(ev.get("ok", false)):
				cands.append(int(ev["value"]))
	var s := str(answer)
	if s.length() >= 2:
		var rev := s.reverse()
		if rev.is_valid_int() and not rev.begins_with("0"):
			cands.append(int(rev))
	cands.append(answer + 10)
	cands.append(answer - 10)
	var deltas: Array[int] = [1, -1, 2, -2, 5, -5]
	deltas.shuffle()
	for d in deltas:
		cands.append(answer + d)
	var opts: Array = [str(answer)]
	for c in cands:
		if c < 0 or c > max_v or c == answer:
			continue
		var cs := str(c)
		if opts.has(cs):
			continue
		opts.append(cs)
		if opts.size() == 4:
			break
	var guard := 0
	while opts.size() < 4 and guard < 60:
		guard += 1
		var x := answer + randi_range(-15, 15)
		if x < 0 or x > max_v or x == answer:
			continue
		var xs := str(x)
		if not opts.has(xs):
			opts.append(xs)
	if opts.size() != 4:
		return []
	opts.shuffle()
	return opts

## 忽略运算优先级、严格从左到右算（典型错误）。无法整除时返回 -1。
func _left_to_right(terms: Array, ops: Array) -> int:
	var cur := int(terms[0])
	for i in ops.size():
		var b := int(terms[i + 1])
		match String(ops[i]):
			"+":
				cur += b
			"-":
				cur -= b
			"×":
				cur *= b
			"÷":
				if b == 0 or cur % b != 0:
					return -1
				cur /= b
			_:
				return -1
		if cur < 0:
			return -1
	return cur

func _note_seen(key: String) -> void:
	_seen[key] = true
	_seen_order.append(key)
	if _seen_order.size() > SEEN_MAX:
		var old: String = _seen_order.pop_front()
		_seen.erase(old)
