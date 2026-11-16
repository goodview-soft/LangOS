shader_type spatial;
render_mode unshaded, depth_test_disabled, cull_disabled, blend_add;
// Onde de choc / sonar : un anneau pixélisé qui grandit (prog 0 -> 1), face caméra.

uniform vec4 color : source_color = vec4(1.0, 0.6, 0.2, 1.0);
uniform float prog = 0.0;
uniform float res = 64.0; // pixels sur toute la largeur du quad

void vertex() {
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
}

void fragment() {
	vec2 p = (UV - 0.5) * 2.0;
	p = floor(p * res * 0.5) / (res * 0.5) + vec2(1.0 / res);
	float r = length(p);
	float w = 0.05 + 0.07 * (1.0 - prog);
	float edge = abs(r - prog);
	float a = step(edge, w) * (1.0 - prog * prog);
	a += step(edge, w * 3.0) * 0.12 * (1.0 - prog);
	if (r > 1.0) {
		a = 0.0;
	}
	ALBEDO = color.rgb * 1.6;
	ALPHA = clamp(a, 0.0, 1.0);
}
