shader_type spatial;
render_mode unshaded, depth_test_disabled, cull_disabled, blend_add;
// Halo lumineux par paliers (look pixel-art), face caméra. Creux au centre pour ne pas noyer le sprite.

uniform vec4 color : source_color = vec4(1.0, 0.6, 0.2, 1.0);
uniform float strength = 1.0;
uniform float t = 0.0;
uniform float res = 40.0;

void vertex() {
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
}

void fragment() {
	vec2 p = (UV - 0.5) * 2.0;
	p = floor(p * res * 0.5) / (res * 0.5) + vec2(1.0 / res);
	float r = length(p);
	float a = smoothstep(1.0, 0.45, r) * mix(0.3, 1.0, smoothstep(0.0, 0.55, r));
	a = floor(a * 5.0) / 5.0;
	a *= 0.7 + 0.3 * sin(t * 9.0);
	ALBEDO = color.rgb * 1.4;
	ALPHA = clamp(a * strength * 0.75, 0.0, 1.0);
}
