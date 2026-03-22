extends Node

# Señal que se emite cuando un enemigo detecta al jugador
signal player_detected(player_position: Vector2, detector_position: Vector2, alert_radius: float)

signal zombie_detected(zombie_position: Vector2, detector_z_position: Vector2, alert_radius_z: float)

signal soldier_shot_fired(shot_position: Vector2, shooter_position: Vector2, alert_radius: float)
