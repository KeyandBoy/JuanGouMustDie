extends CanvasLayer

signal answered(correct: bool)
signal opened
signal closed
signal stood_up

var panel: PanelContainer
var prompt_label: Label
var options_box: VBoxContainer
var fill_edit: LineEdit
var submit_btn: Button
var close_btn: Button
var info_label: Label
var current_question: Dictionary = {}
var is_open := false

func _ready() -> void:
	layer = 20
	visible = false
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.35)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	UiTheme.apply(center)
	add_child(center)

	panel = PanelContainer.new()
	panel.custom_minimum_size = Vector2(520, 380)
	center.add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	panel.add_child(vbox)

	var title := Label.new()
	title.text = "答题学习（F 暂停 · ESC 起身）"
	title.add_theme_font_size_override("font_size", 16)
	vbox.add_child(title)

	info_label = Label.new()
	info_label.text = ""
	info_label.add_theme_font_size_override("font_size", 13)
	vbox.add_child(info_label)

	prompt_label = Label.new()
	prompt_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	prompt_label.custom_minimum_size = Vector2(0, 60)
	prompt_label.add_theme_font_size_override("font_size", 22)
	vbox.add_child(prompt_label)

	options_box = VBoxContainer.new()
	options_box.add_theme_constant_override("separation", 6)
	vbox.add_child(options_box)

	fill_edit = LineEdit.new()
	fill_edit.placeholder_text = "输入答案后回车"
	fill_edit.visible = false
	vbox.add_child(fill_edit)
	fill_edit.text_submitted.connect(func(_t): _submit_fill())

	var btn_row := HBoxContainer.new()
	vbox.add_child(btn_row)
	submit_btn = Button.new()
	submit_btn.text = "提交"
	submit_btn.visible = false
	submit_btn.pressed.connect(_submit_fill)
	btn_row.add_child(submit_btn)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn_row.add_child(spacer)

	close_btn = Button.new()
	close_btn.text = "起身离开 (ESC)"
	close_btn.pressed.connect(_stand_up)
	btn_row.add_child(close_btn)

func open(question: Dictionary) -> void:
	current_question = question
	is_open = true
	visible = true
	GameState.run_state = GameState.RunState.QUIZ
	opened.emit()
	prompt_label.text = String(question.get("prompt", "?"))
	var qtype := String(question.get("type", "choice"))
	var options: Array = question.get("options", [])
	info_label.text = "科目：%s　题型：%s" % [QuestionBank.get_subject_label(question.get("grade", "junior"), question.get("subject", "math")), "选择" if qtype == "choice" else "填空"]
	for c in options_box.get_children(): c.queue_free()
	fill_edit.visible = false
	submit_btn.visible = false
	if qtype == "choice" and options.size() >= 2:
		var letters := ["A", "B", "C", "D", "E", "F"]
		var buttons: Array[Button] = []
		for i in options.size():
			var btn := Button.new()
			btn.text = "%s. %s" % [letters[i % letters.size()], String(options[i])]
			btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
			var idx := i
			btn.pressed.connect(func(): _submit_choice(idx))
			options_box.add_child(btn)
			buttons.append(btn)
		if GameState.exam_hint and options.size() >= 3:
			var answer := String(question.get("answer", ""))
			var wrong := _first_wrong_index(options, answer)
			if wrong >= 0:
				buttons[wrong].disabled = true
				buttons[wrong].text += "（已排除）"
	else:
		fill_edit.visible = true
		submit_btn.visible = true
		fill_edit.grab_focus()

func _submit_choice(index: int) -> void:
	var options: Array = current_question.get("options", [])
	var answer := String(current_question.get("answer", ""))
	var correct := false
	if answer.is_empty():
		correct = false
	else:
		correct = (String(options[index]) == answer) or (answer == str(index + 1))
	_submit(correct)

func _first_wrong_index(options: Array, answer: String) -> int:
	for i in options.size():
		var is_ans := (String(options[i]) == answer) or (answer == str(i + 1))
		if not is_ans and String(options[i]) != answer:
			return i
	return -1

func _submit_fill() -> void:
	var answer := String(current_question.get("answer", "")).strip_edges()
	var guess := fill_edit.text.strip_edges()
	_submit(not answer.is_empty() and guess == answer)

func _submit(correct: bool) -> void:
	if correct:
		GameState.on_correct_answer()
	else:
		GameState.on_wrong_answer()
	if GameState.run_state == GameState.RunState.CLEARED or GameState.run_state == GameState.RunState.GAMEOVER:
		visible = false
		is_open = false
		current_question = {}
		answered.emit(correct)
		return
	close()
	answered.emit(correct)

func close() -> void:
	visible = false
	is_open = false
	current_question = {}
	if GameState.run_state == GameState.RunState.QUIZ:
		GameState.run_state = GameState.RunState.EXPLORING
	closed.emit()

func _stand_up() -> void:
	if not is_open:
		return
	close()
	stood_up.emit()

func _unhandled_input(event: InputEvent) -> void:
	if not is_open: return
	if event.is_action_pressed("ui_cancel"):
		_stand_up()
		get_viewport().set_input_as_handled()
