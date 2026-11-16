shader_type spatial;
render_mode unshaded, depth_draw_opaque, cull_disabled, shadows_disabled;

// Square pixel particles: billboarded quads, alpha by Bayer dithering (no blending), cut-plane aware.
uniform vec3 cut_dir = vec3(0.0, 0.0, -1.0);
uniform float cut_depth = -1000.0;
uniform float glow = 1.0;

varying float vd;

float bayer4(ivec2 p) {
	int x = p.x & 3;
	int y = p.y & 3;
	int a = x ^ y;
	int v = ((a & 1) << 3) | ((y & 1) << 2) | (((a >> 1) & 1) << 1) | ((y >> 1) & 1);
	return (float(v) + 0.5) / 16.0;
}

void vertex() {
	vd = dot(MODEL_MATRIX[3].xyz, cut_dir);
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
	MODELVIEW_MATRIX = MODELVIEW_MATRIX * mat4(vec4(length(MODEL_MATRIX[0].xyz), 0.0, 0.0, 0.0), vec4(0.0, length(MODEL_MATRIX[1].xyz), 0.0, 0.0), vec4(0.0, 0.0, length(MODEL_MATRIX[2].xyz), 0.0), vec4(0.0, 0.0, 0.0, 1.0));
}

void fragment() {
	if (vd < cut_depth - 1.0) { discard; }
	if (COLOR.a < bayer4(ivec2(FRAGCOORD.xy))) { discard; }
	ALBEDO = COLOR.rgb * glow;
}
