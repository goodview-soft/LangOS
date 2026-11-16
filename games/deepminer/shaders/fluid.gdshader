shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled, diffuse_lambert, specular_disabled;

uniform sampler2D atlas : source_color, filter_nearest;
uniform vec3 cut_dir = vec3(0.0, 0.0, -1.0);
uniform float cut_depth = -1000.0;
uniform float fog_depth = -1000.0;
uniform float fog_len = 10.0;
uniform vec3 fog_color : source_color = vec3(0.02, 0.025, 0.05);
uniform float pfeet = 1000.0;  // player's actual feet height (continuous)
uniform float feet_y = -1000.0;
uniform float front_max = 64.0;

#include "res://games/deepminer/shaders/view_cut.gdshaderinc"

varying vec3 wpos;
varying vec3 wnrm;
varying vec4 vcol;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	VERTEX += warp_pos(wpos) - wpos + jitter_pos(wpos) + bend_pos(wpos, CAMERA_POSITION_WORLD);  // chunks sit at the origin (model = world)
	wnrm = (MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz;
	vcol = COLOR;
}

void fragment() {
	// --- VIEW --- per-camera rules (see view_cut.gdshaderinc)
	bool do_slice = slice_main;
	bool do_cut = cut_main;
	if (do_slice) {  // --- VIEW --- same block-level cutaway as the rock
		if (slice_hidden(ivec3(floor(wpos - wnrm * 0.02)), true)) { discard; }
	}
	float d = dot(wpos, cut_dir);
	float ahead = do_cut ? cut_depth - d : 0.0;
	float fade = 1.0;
	float ghost = 1.0;
	if (ahead > 0.003) {  // camera side: only below the player's ground level (see block.gdshader)
		float front = ceil(ahead - 0.003);
		// never above the player's real feet: water in front of a swimmer must not cover his body
		if (front > front_max) { discard; }
		if (wpos.y > min(feet_y, pfeet) + 0.01) { ghost = 0.3; }
  // water in front of the player: see-through sheet, never cut
		fade = 1.0;  // no darkening of the layers in front
	}
	if (((ahead > 0.003 && do_cut) || occl_3d) && occludes(wpos, wnrm, CAMERA_POSITION_WORLD)) { ghost = min(ghost, 0.3); }
	// texel-exact scrolling that wraps inside the 16x16 tile (never samples a neighbour tile)
	bool lava = vcol.g > 0.5;
	ivec2 tile0 = ivec2(floor(UV * vec2(4.0, 8.0))) * 16;
	vec2 lp = floor(fract(UV * vec2(4.0, 8.0)) * 16.0);
	vec2 cell = floor(wpos.xz);
	vec2 sh = lava ? vec2(floor(TIME * 1.5), floor(TIME * 0.9 + sin(TIME * 0.5) * 2.0)) : vec2(floor(TIME * 5.0), floor(sin(TIME * 1.2 + cell.x * 0.7) * 1.5));
	ivec2 q = ivec2(mod(lp + sh, 16.0));
	vec4 t = texelFetch(atlas, tile0 + q, 0);
	float n = do_cut ? max(floor(d - fog_depth + 0.01), 0.0) : 0.0;
	// 3 layers behind the player stay clearly readable, then the depth fog closes in faster
	float f = min(n <= 3.0 ? n * 0.06 : 0.18 + (n - 3.0) / fog_len * 0.8, 0.3);  // far layers stay readable (max 30 % fog)
	vec3 c = t.rgb * vcol.r;
	float wave = sin(wpos.x * 1.7 + wpos.z * 1.1 + lp.x * 0.39 + lp.y * 0.2 - TIME * 2.4);
	if (!lava && wave > 0.93) { c += vec3(0.18, 0.24, 0.3); }  // moving glints
	ALBEDO = mix(c, fog_color, f * 0.85) * fade;
	float pulse = 1.0;
	if (lava) {
		float lum = dot(t.rgb, vec3(0.3, 0.5, 0.2));
		pulse = 0.85 + 0.2 * sin(TIME * 1.6 + wpos.x * 0.6 + wpos.z * 0.45) + 0.6 * step(0.7, lum) * (0.5 + 0.5 * wave);
	}
	EMISSION = t.rgb * vcol.g * 2.5 * pulse * (1.0 - f * 0.6) * fade;
	EMISSION += c * plight_col * plight(wpos, wnrm) * plight_k * 0.7 * fade * (1.0 - f * 0.6);
	ALPHA = mix(0.62, 1.0, vcol.g) * ghost;
	if (fow_on) {  // fog of war (own cell)
		float fs = fow_at(ivec3(floor(wpos - wnrm * 0.02)));
		if (fs < 0.25) { ALBEDO = vec3(0.0); EMISSION = vec3(0.0); ALPHA = 1.0; }
		else {
			float k = fs > 0.75 ? 1.0 - smoothstep(fow_r - 5.0, fow_r, distance(wpos, plight_pos)) : 0.0;
			vec3 memc = vec3(dot(c, vec3(0.3, 0.5, 0.2))) * vec3(0.5, 0.55, 0.7) * 0.3;
			ALBEDO *= k;
			EMISSION = EMISSION * k + memc * (1.0 - k);
		}
	}
}
