shader_type spatial;
// Pixel-art overlays drawn on block faces (depth-tested, 16 texels per block):
// mode 0: corner brackets of the aimed face + mining cracks, 1: placement preview, 2: player shadow.
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;

uniform int mode = 0;
uniform vec4 frame_col : source_color = vec4(1.0);
uniform int crack = 0;  // 0 = none, 1..4 = stage
uniform sampler2D cracks : filter_nearest;  // 64x16: stage k in columns (k-1)*16..
uniform float shadow_r = 5.0;  // shadow radius in texels

bool bracket(ivec2 p) {
	if (p.x < 0 || p.y < 0 || p.x > 15 || p.y > 15) { return false; }
	ivec2 q = min(p, ivec2(15) - p);
	return (q.x == 0 && q.y <= 2) || (q.y == 0 && q.x <= 2);
}

void fragment() {
	if (mode == 2) {
		vec2 c = floor(UV * 16.0) + 0.5 - 8.0;
		float d = length(c);
		if (d > shadow_r) { discard; }
		ALBEDO = vec3(0.0);
		ALPHA = d < shadow_r - 1.6 ? 0.5 : 0.28;
	} else {
		// quad covers 18x18 texels: the face (0..15) plus a 1-texel margin for the outline
		ivec2 p = ivec2(floor(UV * 18.0)) - 1;
		if (mode == 1) {
			if (p.x < 0 || p.y < 0 || p.x > 15 || p.y > 15) { discard; }
			ivec2 q = min(p, ivec2(15) - p);
			if (!((q.x == 0 || q.y == 0) && ((p.x + p.y) / 2) % 2 == 0)) { discard; }
			ALBEDO = vec3(0.85, 0.92, 1.0);
			ALPHA = 0.45;
		} else if (bracket(p)) {
			ALBEDO = frame_col.rgb * 0.9;
			ALPHA = 0.55;  // repère discret : on voit le bloc visé sans qu'il s'impose
		} else {
			bool rim = false;
			for (int dy = -1; dy <= 1; dy++) {
				for (int dx = -1; dx <= 1; dx++) {
					rim = rim || bracket(p + ivec2(dx, dy));
				}
			}
			if (rim) {
				ALBEDO = vec3(0.04, 0.03, 0.06);
				ALPHA = 0.3;
			} else if (crack > 0 && p.x >= 0 && p.y >= 0 && p.x <= 15 && p.y <= 15
					&& texelFetch(cracks, ivec2(p.x + (crack - 1) * 16, p.y), 0).a > 0.5) {
				ALBEDO = vec3(0.05, 0.04, 0.04);
				ALPHA = 0.75;
			} else {
				discard;
			}
		}
	}
}
