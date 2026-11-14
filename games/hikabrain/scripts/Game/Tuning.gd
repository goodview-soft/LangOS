class_name Tuning
## Tous les paramètres d'équilibrage au même endroit (modifiables à chaud).

# --- Déplacement ---
static var walk_speed := 4.4
static var sprint_speed := 5.9
static var sneak_speed := 1.9
static var sneak_eye_drop := 0.25
static var jump_velocity := 7.8
static var gravity := 25.0
static var coyote_time := 0.12
static var jump_buffer := 0.12
static var ground_accel := 40.0
static var ground_decel := 45.0
static var air_accel := 9.0 
static var air_drag := 1.2
static var max_fall_speed := 18.0
static var max_air_speed_mult := 1.05

# --- Caméra ---
static var mouse_sens := 0.0022
static var base_fov := 82.0
static var sprint_fov_bonus := 7.0

# --- Combat ---
static var max_health := 20.0
static var sword_damage := 2.5
static var attack_cooldown := 0.45
static var attack_range := 3.2
static var attack_cone_deg := 28.0     # demi-angle de tolérance (+ rayon du corps)
static var hurt_invuln := 0.4
static var kb_horizontal := 5.2
static var kb_vertical := 3.4
static var kb_sprint_mult := 1.25
static var kb_lock_time := 0.2
static var kb_ground_friction_scale := 0.3
static var kb_control_scale := 0.25
static var regen_per_sec := 0.4
static var regen_delay := 5.0

# --- Construction ---
static var reach := 5.0
static var mine_time := 0.22
static var place_cooldown := 0.1
static var start_blocks := 64
static var build_height_limit := 20

# --- Match ---
static var spawn_protection := 2.5
static var respawn_delay := 1.0
static var countdown_time := 3.0
static var point_banner_time := 2.5
