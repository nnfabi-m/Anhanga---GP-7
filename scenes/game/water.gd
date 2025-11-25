extends AnimatedSprite2D

func _ready() -> void:
	if sprite_frames and sprite_frames.has_animation("idle"):
		animation = "idle"
		play()
