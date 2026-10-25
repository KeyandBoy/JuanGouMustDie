class_name DialogueDb
extends RefCounted

static func _line(speaker: String, text: String, flag: String = "") -> DialogueLine:
	var line := DialogueLine.new()
	line.speaker = speaker
	line.text = text
	line.flag = flag
	return line

static func make(id: String, entries: Array) -> DialogueData:
	var data := DialogueData.new()
	data.id = id
	for e in entries:
		var line := DialogueLine.new()
		line.speaker = String(e.get("speaker", ""))
		line.text = String(e.get("text", ""))
		line.flag = String(e.get("flag", ""))
		line.on_left = bool(e.get("on_left", false))
		if e.has("portrait"):
			line.portrait = e["portrait"]
		data.lines.append(line)
	return data

static func level_tip(level: int) -> DialogueData:
	match level:
		1:
			return make("level_1_tip", [
				{"speaker": "广播", "text": "欢迎来到躺平学校。在这里，学习是违规的。"},
				{"speaker": "广播", "text": "靠近课桌按 F 坐下答题；答对才有净增长，答错会掉空虚值。"},
				{"speaker": "广播", "text": "被盯上就往楼梯间跑——下一层永远比这一层安全。"},
			])
		2:
			return make("level_2_tip", [
				{"speaker": "同桌", "text": "巡查开始记巡逻路线了，别在一个房间待太久。"},
				{"speaker": "同桌", "text": "离开房间超过半分钟，里面的东西……会忘掉你。"},
			])
		3:
			return make("level_3_tip", [
				{"speaker": "广播", "text": "警告三次，本层作废。老师已经把你的名字写进小本子了。"},
			])
		4:
			return make("level_4_tip", [
				{"speaker": "???", "text": "四楼有东西在模仿学生。听到翻书声变快，就别回头。"},
			])
		5:
			return make("level_5_tip", [
				{"speaker": "???", "text": "楼梯尽头那位，已经等了你很久。"},
				{"speaker": "???", "text": "这一层，别答题。跑。"},
			])
	return null

static func tutorial() -> DialogueData:
	return make("tutorial", [
		{"speaker": "系统", "text": "WASD 移动，Shift 闪避，F 学习/答题，E 开门。"},
		{"speaker": "系统", "text": "R/T/Y 使用背包道具，ESC 暂停。活下去，然后往上爬。"},
	])
