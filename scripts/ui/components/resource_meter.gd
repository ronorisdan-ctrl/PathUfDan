extends PanelContainer
## Presentation only. The owner supplies values; no Game/Events/stat/save access.

@onready var caption: Label = $Content/Header/Caption
@onready var readout: Label = $Content/Header/Readout
@onready var bar: ProgressBar = $Content/Bar

func present(current: float, maximum: float, resource_name: String = "Life", mana: bool = false) -> void:
	var limit := maxf(0.0, maximum) if is_finite(maximum) else 0.0
	var shown := clampf(current, 0.0, limit) if is_finite(current) else 0.0
	caption.text = resource_name.to_upper()
	readout.text = "%d / %d" % [int(ceil(shown)), int(ceil(limit))]
	bar.theme_type_variation = &"ManaMeter" if mana else &"LifeMeter"
	bar.value = shown / limit * 100.0 if limit > 0.0 else 0.0
	tooltip_text = "%s: %s" % [resource_name, readout.text]
