extends Node

signal timer_synced(arrival_time: float, time_scale: float)
signal health_changed(value: float)
signal ship_durability_changed(value: float)
signal task_updated(task_data)
signal system_alert(text: String)
signal sabotage_triggered(sabotage_type: String)
signal sabotage_ended(sabotage_type: String)
