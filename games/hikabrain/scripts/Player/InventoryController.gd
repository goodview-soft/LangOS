class_name InventoryController
extends Node
## Inventaire : épée, pioche, blocs.

signal changed
signal slot_selected(index: int)

const SLOT_COUNT := 3
var selected: int = Cfg.Slot.BLOCKS
var block_count := Tuning.start_blocks

func reset() -> void:
	block_count = Tuning.start_blocks
	selected = Cfg.Slot.BLOCKS
	changed.emit()
	slot_selected.emit(selected)

func select(i: int) -> void:
	i = clampi(i, 0, SLOT_COUNT - 1)
	if i != selected:
		selected = i
		slot_selected.emit(selected)

func scroll(dir: int) -> void:
	select(posmod(selected + dir, SLOT_COUNT))

func consume_block() -> bool:
	if block_count <= 0:
		return false
	block_count -= 1
	changed.emit()
	return true
