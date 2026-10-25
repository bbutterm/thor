extends Resource
class_name RuneDef
## Руна-улучшение, выбирается после зачистки зала. Эффект применяется в player.gd по id.

@export var id: String = ""
@export var title: String = ""
@export_multiline var description: String = ""
@export var glyph: String = "ᚠ"
@export var color: Color = Color(0.4, 0.75, 1.0)
