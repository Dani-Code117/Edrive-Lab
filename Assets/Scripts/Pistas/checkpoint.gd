class_name CheckpointArea
extends Area2D

## Checkpoint invisible de pista (Layer 3) que notifica al VehiculoAgente al cruzar.

@export var id_checkpoint: int = 0


func _ready() -> void:
	body_entered.connect(_on_body_entered)


func _on_body_entered(body: Node2D) -> void:
	if body is VehiculoAgente:
		body.registrar_checkpoint(id_checkpoint)
