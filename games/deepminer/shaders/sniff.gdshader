shader_type spatial;
render_mode unshaded, depth_test_disabled, cull_disabled, blend_mix;
// Flair : un minerai = sa vraie texture + un cadre pulsant de sa couleur, face caméra.
// Chaque marqueur apparaît (avec un éclair blanc) quand l'onde sonar l'atteint.

uniform sampler2D atlas : filter_nearest, source_color;
uniform vec2 tiles = vec2(4.0, 5.0);
uniform vec3 origin;
uniform float wave = 0.0;
uniform float fade = 1.0;
uniform float t = 0.0;

varying vec3 v_col;
varying vec2 v_tile;
varying float v_dist;

void vertex() {
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
	v_col = COLOR.rgb;
	v_tile = INSTANCE_CUSTOM.xy;
	v_dist = distance(MODEL_MATRIX[3].xyz, origin);
}

void fragment() {
	if (v_dist > wave) {
		discard;
	}
	vec2 p = (UV - 0.5) * 1.5 + 0.5; // 0..1 = la texture du bloc
	p = floor(p * 16.0) / 16.0 + vec2(1.0 / 32.0);
	vec2 q = abs(p - 0.5);
	float d = max(q.x, q.y);
	float pulse = 0.5 + 0.5 * sin(t * 6.0 + v_dist * 0.7);
	float since = wave - v_dist;
	vec3 col;
	float a;
	if (d <= 0.5) {
		col = texture(atlas, (v_tile + p) / tiles).rgb * 1.3;
		col = mix(col, vec3(1.0), clamp(1.0 - since * 1.5, 0.0, 1.0));
		a = 1.0;
	} else if (d <= 0.58) {
		col = mix(v_col, vec3(1.0), 0.25 + 0.4 * pulse);
		a = 1.0;
	} else {
		if (d > 0.75) {
			discard;
		}
		col = v_col;
		a = (0.75 - d) * 3.0 * (0.4 + 0.4 * pulse);
	}
	ALBEDO = col;
	ALPHA = clamp(a, 0.0, 1.0) * fade;
}
