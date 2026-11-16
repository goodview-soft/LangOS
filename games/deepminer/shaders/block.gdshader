shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled, diffuse_lambert, specular_disabled;

uniform sampler2D atlas : source_color, filter_nearest;
uniform float stone_on = 1.0;  // calepinage de pierres (/pierres on|off)
uniform vec3 cut_dir = vec3(0.0, 0.0, -1.0);
uniform float cut_depth = -1000.0;  // animated discard plane
uniform float fog_depth = -1000.0;  // player's layer plane (integer): fog steps start here
uniform float fog_len = 10.0;       // layers until full fog
uniform vec3 fog_color : source_color = vec3(0.02, 0.025, 0.05);
uniform float feet_y = -1000.0;     // front cut height: the player's ground level (integer, stable during jumps)
uniform float front_max = 64.0;     // camera-side layers shown (the whole front of the map stays; only the nearest layers are cut open)

#include "res://games/deepminer/shaders/view_cut.gdshaderinc"

varying vec3 wpos;
varying vec3 wnrm;
varying vec4 vcol;
varying float vstyle;  // style de zone (UV2.x) : 0 normal, 1 dalles, 2 strates, 3 gravats

float hash12(vec2 p) {
	return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

// --- procedural autotiling: convex edges of a face (the face stops, air beyond) get a 1-2 texel dark outline
// with a little irregularity, convex corners are rounded (radius 3.5 texels). Returns (e, w, top):
// e = texel distance to the nearest convex edge/arc (< 0: outside the rounded corner), w = outline width,
// top = 1 when the nearest edge is the upper one (floor line on caps).
vec3 shape(vec3 wp, vec3 wn, bool capm, bool sl) {
	if (max(max(abs(wn.x), abs(wn.y)), abs(wn.z)) < 0.99) { return vec3(99.0, 0.0, 0.0); }
	ivec3 N = ivec3(round(wn));
	ivec3 c = ivec3(floor(wp - wn * 0.02));
	ivec3 a = c + N;
	ivec3 t1; ivec3 t2; vec2 q;
	if (N.y != 0) { t1 = ivec3(1, 0, 0); t2 = ivec3(0, 0, 1); q = wp.xz; }
	else if (N.x != 0) { t1 = ivec3(0, 0, 1); t2 = ivec3(0, 1, 0); q = wp.zy; }
	else { t1 = ivec3(1, 0, 0); t2 = ivec3(0, 1, 0); q = wp.xy; }
	vec2 p = floor(fract(q) * 16.0) + 0.5;
	bool x0 = !vox_solid(c - t1, sl) && (capm || !vox_solid(a - t1, sl));
	bool x1 = !vox_solid(c + t1, sl) && (capm || !vox_solid(a + t1, sl));
	bool y0 = !vox_solid(c - t2, sl) && (capm || !vox_solid(a - t2, sl));
	bool y1 = !vox_solid(c + t2, sl) && (capm || !vox_solid(a + t2, sl));
	float e = 99.0;
	float top = 0.0;
	if (x0) { e = min(e, p.x - 0.5); }
	if (x1) { e = min(e, 15.5 - p.x); }
	if (y0) { e = min(e, p.y - 0.5); }
	if (y1) { float ey = 15.5 - p.y; if (ey <= e) { top = t2.y > 0 ? 1.0 : 0.0; } e = min(e, ey); }
	const float R = 5.0;
	vec2 lo = vec2(R);
	vec2 hi = vec2(16.0 - R);
	if (x0 && y0 && p.x < lo.x && p.y < lo.y) { e = R - 0.5 - length(p - lo); }
	if (x1 && y0 && p.x > hi.x && p.y < lo.y) { e = R - 0.5 - length(p - vec2(hi.x, lo.y)); }
	if (x0 && y1 && p.x < lo.x && p.y > hi.y) { e = R - 0.5 - length(p - vec2(lo.x, hi.y)); }
	if (x1 && y1 && p.x > hi.x && p.y > hi.y) { e = R - 0.5 - length(p - hi); }
	// irregular outline: 1 or 2 texels, per 4-texel segment and per block
	float seg = floor((p.x + p.y) / 4.0);
	float w = 1.0 + step(0.7, hash12(vec2(float(c.x * 7 + c.z * 13 + c.y * 3), seg)));
	return vec3(e, w, top);
}

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	VERTEX += warp_pos(wpos) - wpos + jitter_pos(wpos) + bend_pos(wpos, CAMERA_POSITION_WORLD);  // chunks sit at the origin (model = world)
	wnrm = (MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz;
	vcol = COLOR;
	vstyle = UV2.x;
}

// ---- calepinage : rangées de pierres de hauteurs et largeurs variables (indépendant de la grille des blocs)
// q = coordonnées monde dans le plan de la face ; H/W = hauteur / largeur moyennes (blocs). Retourne l'id de la pierre ;
// sz = taille de la pierre (blocs), loc = position 0..1 dans la pierre.
float stone_pat(vec2 q, float H, float W, out vec2 sz, out vec2 loc) {
	float band = floor(q.y / (2.0 * H));
	float bh = hash12(vec2(band, 5.3));
	float fy = q.y / (2.0 * H) - band;
	float rowh; float ry; float rowid;
	if (bh < 0.35) { rowh = 2.0 * H; ry = fy; rowid = band * 2.0; }  // rangée haute : grosses pierres
	else { float hf = step(0.5, fy); rowh = H; ry = fy * 2.0 - hf; rowid = band * 2.0 + hf; }
	float rw = W * mix(0.7, 1.45, hash12(vec2(rowid, 9.1)));
	float off = hash12(vec2(rowid, 2.2)) * rw;
	float cu = (q.x + off) / rw;
	float c0 = floor(cu);
	float b0 = c0 + (hash12(vec2(c0, rowid)) - 0.5) * 0.55;
	float idx = cu < b0 ? c0 - 1.0 : c0;
	float bs = idx + (hash12(vec2(idx, rowid)) - 0.5) * 0.55;
	float be = idx + 1.0 + (hash12(vec2(idx + 1.0, rowid)) - 0.5) * 0.55;
	sz = vec2((be - bs) * rw, rowh);
	loc = vec2((cu - bs) / (be - bs), ry);
	return hash12(vec2(idx * 1.13, rowid + 17.0));
}

// bruit de valeur continu (indépendant de la grille des blocs) : grandes plaques de teinte sur la roche
float vnoise(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = hash12(i.xy + i.z * 31.7);
	float b = hash12(i.xy + vec2(1.0, 0.0) + i.z * 31.7);
	float c = hash12(i.xy + vec2(0.0, 1.0) + i.z * 31.7);
	float d = hash12(i.xy + vec2(1.0, 1.0) + i.z * 31.7);
	float a2 = hash12(i.xy + (i.z + 1.0) * 31.7);
	float b2 = hash12(i.xy + vec2(1.0, 0.0) + (i.z + 1.0) * 31.7);
	float c2 = hash12(i.xy + vec2(0.0, 1.0) + (i.z + 1.0) * 31.7);
	float d2 = hash12(i.xy + vec2(1.0, 1.0) + (i.z + 1.0) * 31.7);
	return mix(mix(mix(a, b, f.x), mix(c, d, f.x), f.y), mix(mix(a2, b2, f.x), mix(c2, d2, f.x), f.y), f.z);
}

void fragment() {
	// lighting normal: cross-quads (flowers, mushrooms, torches) are lit like an upward surface, never black
	vec3 ln = (abs(wnrm.y) < 0.5 && abs(abs(wnrm.x) - abs(wnrm.z)) < 0.3) ? vec3(0.0, 1.0, 0.0) : wnrm;
	vec2 tuv = UV;
	float sty = floor(vstyle + 0.5);
	bool patd = false;
	vec3 patm = vec3(1.0);
	bool plain = vcol.g < 0.01 && vcol.b < 0.05 && vcol.a > 0.5;
	bool axisn = max(max(abs(wnrm.x), abs(wnrm.y)), abs(wnrm.z)) > 0.9;
	if (plain && axisn && stone_on > 0.5) {
		vec3 an = abs(wnrm);
		vec2 q = an.y > 0.7 ? wpos.xz : (an.x > 0.7 ? wpos.zy : wpos.xy);
		vec2 hw = sty < 0.5 ? vec2(0.5, 1.1) : (sty < 1.5 ? vec2(1.0, 2.2) : (sty < 2.5 ? vec2(0.3, 3.2) : vec2(0.3, 0.5)));
		hw *= mix(0.75, 1.45, hash12(floor(q / 6.0) + sty * 3.0));  // secteurs de maçonnerie différents
		vec2 sz; vec2 loc;
		float sid = stone_pat(q, hw.x, hw.y, sz, loc);
		float e = min(min(loc.x, 1.0 - loc.x) * sz.x, min(loc.y, 1.0 - loc.y) * sz.y);
		float gap = smoothstep(0.0, 0.04, e);                  // joint sombre
		float dome = smoothstep(0.0, 0.17, e);                 // bord arrondi, centre aplati
		float topl = smoothstep(0.15, 0.0, (1.0 - loc.y) * sz.y);
		float botl = smoothstep(0.15, 0.0, loc.y * sz.y);
		patm = vec3(mix(0.45, 1.0, gap) * mix(0.76, 1.0, dome) * (1.0 + topl * 0.16 - botl * 0.20));
		patm *= vec3(1.0 + (sid - 0.5) * 0.18, 1.0 + (sid - 0.5) * 0.13, 1.0 + (0.5 - sid) * 0.13);  // chaque pierre a sa teinte
		vec2 gl = fract(loc * sz * 0.9 + vec2(sid, fract(sid * 7.3)));  // grain de la pierre
		if (sid > 0.5) { gl.x = 1.0 - gl.x; }
		vec2 base = floor(UV * vec2(4.0, 8.0));
		tuv = (base + clamp(gl, vec2(0.004), vec2(0.996))) / vec2(4.0, 8.0);
		patd = true;
	} else if (plain && sty > 0.5 && axisn) {
		// zone de style : le motif ne suit plus la grille des blocs (coordonnées monde, échelle propre au style)
		vec3 an = abs(wnrm);
		vec2 q = an.y > 0.7 ? wpos.xz : (an.x > 0.7 ? wpos.zy : wpos.xy);
		vec2 scl = sty < 1.5 ? vec2(2.0, 2.0) : (sty < 2.5 ? vec2(4.0, 1.0) : vec2(0.5, 0.5));  // dalles 2x2, strates étirées, gravats fins
		vec2 cell = floor(q / scl);
		float hh = hash12(cell * 1.37 + sty * 11.0);
		vec2 loc = fract(q / scl);
		if (hh > 0.5) { loc.x = 1.0 - loc.x; }
		if (fract(hh * 7.0) > 0.5 && sty < 2.5) { loc.y = 1.0 - loc.y; }
		vec2 base = floor(UV * vec2(4.0, 8.0));
		tuv = (base + clamp(loc, vec2(0.004), vec2(0.996))) / vec2(4.0, 8.0);
	} else if (vcol.g < 0.01 && vcol.b < 0.05 && vcol.a > 0.5) {  // roche / terre ordinaires : tuile retournée au hasard par bloc (casse le damier)
		vec3 fb = floor(wpos - wnrm * 0.02);
		float h = hash12(fb.xz * 1.91 + fb.y * 7.13);
		vec2 base = floor(UV * vec2(4.0, 8.0));
		vec2 loc = UV * vec2(4.0, 8.0) - base;
		if (h > 0.5) { loc.x = 1.0 - loc.x; }
		if (fract(h * 7.0) > 0.5) { loc.y = 1.0 - loc.y; }
		tuv = (base + clamp(loc, vec2(0.004), vec2(0.996))) / vec2(4.0, 8.0);
	}
	if (vcol.b > 0.4 && vcol.b < 0.6 && abs(wnrm.y) < 0.5 && abs(abs(wnrm.x) - abs(wnrm.z)) < 0.3) {  // flamme (torche = croisillon) : ondule (decalage par rangee, plus fort vers la pointe) et vacille
		vec2 tb = floor(UV * vec2(4.0, 8.0));
		float fy = floor(fract(UV.y * 8.0) * 16.0);
		if (fy < 9.0) {
			float ph0 = hash12(floor(wpos.xz) + floor(wpos.y) * 7.13);
			float sw = sin(TIME * 7.0 + ph0 * 9.0 + fy * 0.7) * 0.6 + sin(TIME * 13.0 + ph0 * 5.0 - fy) * 0.4;
			float sh0 = round(sw * (9.0 - fy) / 9.0 * 1.6);
			tuv.x = clamp(tuv.x + sh0 / 64.0, tb.x * 0.25 + 0.002, tb.x * 0.25 + 0.248);
		}
	}
	vec4 t = texture(atlas, tuv);
	if (t.a < 0.5) { discard; }  // before any branch (back-face caps included): transparent texels never write
	bool crossq = ln.y > 0.5 && abs(wnrm.y) < 0.5;  // cross-quads: both sides are the plant, never a cap
	bool cap = vcol.a < 0.5;  // --- VIEW --- cut rock face (built by IsoView)
	vec2 sh = vec2(1.0, 0.0);
	float below = 0.0;
	// --- VIEW --- per-camera rules (see view_cut.gdshaderinc)
	bool do_slice = slice_main;
	bool do_cut = cut_main;
	if (do_slice) {
		if (slice_hidden(ivec3(floor(wpos - wnrm * 0.02)), true)) { discard; }
		below = clamp((float(lvl_y) - wpos.y) / 9.0, 0.0, 1.0);  // deeper = darker: pits read as pits
	}
	float oh = 1.0;  // floor under an overhang: solid at +1 very dark, at +2 slightly dark (top faces only)
	if (ln.y > 0.5) {
		ivec3 ac = ivec3(int(floor(wpos.x)), int(floor(wpos.y + 0.02)), int(floor(wpos.z)));
		if (vox_solid(ac + ivec3(0, 1, 0), do_slice)) { oh = 0.35; }
		else if (vox_solid(ac + ivec3(0, 2, 0), do_slice)) { oh = 0.7; }
	}
	if (ao_main) { sh = vox_shade(wpos, ln, cap, do_slice); }
	float d = dot(wpos, cut_dir);
	float ahead = do_cut ? cut_depth - d : 0.0;  // > 0: in front of the cut (camera side)
	// the layers right in front of the player are cut open; farther ones stay, and the blocks in the line of sight become see-through
	float fr0 = ahead > 0.003 ? ceil(ahead - 0.003) : 0.0;
	bool inslab = fr0 > 0.0 && (narrow || fr0 <= 2.0);  // the 2 layers nearest to the player's plane: always cut open
	if (((do_cut && ahead > 0.003) || occl_3d) && occludes(wpos, wnrm, CAMERA_POSITION_WORLD) && ((int(FRAGCOORD.x) + int(FRAGCOORD.y)) & 1) == 0) { discard; }  // blocks between us and the player: see-through
	bool buried = false;
	if (ahead > 0.003 && inslab) {  // buried ore seen through the cut (front layers): plain rock, ores must be dug up to be found
		int o1 = vox_id(ivec3(floor(wpos - wnrm * 0.02)));
		int o2 = vox_id(ivec3(floor(wpos + wnrm * 0.02)));
		if ((o1 >= 3 && o1 <= 6) || (o2 >= 3 && o2 <= 6)) {
			t.rgb = vec3(0.12, 0.15, 0.27) * (0.7 + dot(t.rgb, vec3(0.3, 0.5, 0.2)) * 0.4);
			buried = true;
		}
	}
	float front = 0.0;
	float fade = 1.0;
	float edge_k = 1.0;  // player light on outlines / borders
	if (ahead > 0.003) {
		front = ceil(ahead - 0.003);
		// camera-side layers are cut at the player's ground level: floor, water and holes stay visible up to the
		// camera, everything above the feet is removed. The cut tops are closed by the back faces (black caps).
		if (front > front_max || (inslab && wpos.y > feet_y + 0.01)) { discard; }  // the nearest layers (or all, in a tight spot): cut open
		if (wpos.y > feet_y + 0.01) {  // farther in front: natural rock above the feet is hidden, built things stay (bricks, torches, signs, chests)
			int sid = vox_id(ivec3(floor(wpos - wnrm * 0.02)));
			if (!(sid == 17 || sid == 10 || sid == 16 || (sid >= 18 && sid != 23 && sid != 24))) { discard; }
		}
		fade = 1.0;  // no darkening of the layers in front
	}
	if (!FRONT_FACING && crossq) { discard; }  // plant planes come in back-to-back pairs: drawing both z-fights (flicker)
	if (!FRONT_FACING && !crossq) {  // back faces: only as caps of the cut camera-side rock (no hole, no inside visible)
		if (ahead <= 0.003) {
			if (do_cut) { discard; }
			// 3rd person / FPS: a back face is only seen from INSIDE a block (camera clipping): black, never see-through
			ALBEDO = vec3(0.0);
			EMISSION = vec3(0.0);
		} else {
		// cut top of a camera-side block: shown as the block's own top (textured, a bit darker), never see-through
		ALBEDO = t.rgb * vcol.r * 0.62;
		NORMAL = (VIEW_MATRIX * vec4(0.0, 1.0, 0.0, 0.0)).xyz;
		EMISSION = vec3(0.0);
		}
	} else {
	// one flat tint per layer (pixel-art depth steps)
	float n = do_cut ? max(floor(d - fog_depth + 0.01), 0.0) : 0.0;
	// 3 layers behind the player stay clearly readable, then the depth fog closes in faster
	float f = min(n <= 3.0 ? n * 0.06 : 0.18 + (n - 3.0) / fog_len * 0.8, 0.3);  // far layers stay readable (max 30 % fog)
	vec3 c = t.rgb * vcol.r;
	// cold grade with depth (low altitude)
	float cold = clamp((26.0 - wpos.y) / 26.0, 0.0, 1.0) * 0.3;
	c *= mix(vec3(1.0), vec3(0.86, 0.95, 1.12), cold);
	vec3 fogc = fog_color + vec3(0.0, 0.004, 0.012) * n;
	vec3 col = mix(c, fogc, f * 0.8) * oh;
	// face shading, no drawn contour: tops lighter, sides, undersides dark; faces turned away from the player darker
	if (!cap && !do_cut) {  // 3D views: warm floors, cool walls, so surfaces read at a glance
		col *= ln.y > 0.5 ? vec3(1.08, 1.04, 0.95) : vec3(0.91, 0.95, 1.05);
	}
	if (do_cut && !cap) {
		float ori = ln.y > 0.5 ? 1.12 : (ln.y < -0.5 ? 0.55 : 0.8);
		vec3 Lp = normalize(plight_pos - wpos);
		col *= ori * (0.6 + 0.4 * clamp(dot(ln, Lp) * 0.5 + 0.5, 0.0, 1.0));
		sh = vec2(vox_shade(wpos, ln, false, false).x, 0.0);  // ambient occlusion in corners / at wall feet
	}
	if (patd && !cap) { col *= patm; }
	if (!cap && !patd) {  // rounded convex corners (autotiling via vox), in every view: soft darkening, no outline
		vec3 sp = shape(wpos, wnrm, false, do_slice);
		if (sp.x < 0.0) { col *= 0.45; edge_k = 0.4; }
		else if (sp.x < 2.0 && ln.y > 0.5) { col *= 1.0 + 0.10 * (1.0 - sp.x / 2.0); }  // soft light catching the rounded top edges
	}
	if (!cap && vcol.g < 0.01) {  // plaques de teinte continues : la roche ne se lit plus bloc par bloc
		float nz = vnoise(wpos * 0.45) * 0.65 + vnoise(wpos * 1.6 + 11.0) * 0.35;
		col *= vec3(1.0 + (nz - 0.5) * 0.22, 1.0 + (nz - 0.5) * 0.17, 1.0 + (0.5 - nz) * 0.14);
	}
	if (!cap && vcol.g < 0.01 && sty > 0.5) {  // teinte propre à chaque zone
		if (sty < 1.5) { col *= vec3(0.94, 0.98, 1.06); }  // dalles : froides
		else if (sty < 2.5) {  // strates : bandes de couleur par couche
			float band = hash12(vec2(floor(wpos.y * 1.0), 3.7));
			col *= vec3(1.0 + (band - 0.5) * 0.30, 1.0 + (band - 0.5) * 0.18, 1.0 - (band - 0.5) * 0.20);
		} else { col *= vec3(1.08, 0.98, 0.88); }  // gravats : ocre
	}
	if (!patd) {  // every block gets its own small tint (the grid stops reading as identical dice)
		vec3 bc = floor(wpos - wnrm * 0.02);
		float h1 = hash12(bc.xz + bc.y * 17.31);
		float h2 = hash12(bc.zx * 1.37 + bc.y * 5.71 + 3.0);
		col *= vec3(1.0 + (h1 - 0.5) * 0.08, 1.0 + (h2 - 0.5) * 0.05, 1.0 + (0.5 - h1) * 0.05);
	}
	col = mix(col * fade, vec3(0.05, 0.07, 0.12), (1.0 - fade) * 0.5);
	// animated emission
	float em = buried ? 0.0 : vcol.g * 2.2;
	vec2 lp = floor(fract(UV * vec2(4.0, 8.0)) * 16.0);
	float ph = hash12(floor(wpos.xz) + floor(wpos.y) * 7.13);
	float lum = dot(t.rgb, vec3(0.3, 0.5, 0.2));
	if (buried) {
	} else if (vcol.b > 0.6) {          // glow pulse (plants, mushrooms)
		em *= 0.8 + 0.25 * sin(TIME * 1.7 + ph * 6.28);
	} else if (vcol.b > 0.4) {   // torch flicker
		float fh = (lp.y < 9.0 || abs(wnrm.y) > 0.5 || abs(abs(wnrm.x) - abs(wnrm.z)) > 0.3) ? 1.0 : 0.25;  // la flamme brille, le manche peu
		em *= fh * (0.82 + 0.12 * sin(TIME * 13.0 + ph * 9.0) + 0.08 * sin(TIME * 23.0 + ph * 4.0) + 0.06 * sin(TIME * 37.0 + lp.y * 1.3 + ph));
	} else if (vcol.b > 0.1 && vcol.b < 0.2) {  // luminous veins / ore glints: only the bright texels glow, slow wave + rare twinkle
		em *= smoothstep(0.3, 0.55, lum) * (0.75 + 0.25 * sin(TIME * 0.9 + ph * 6.28 + float(lp.x) * 0.35));
		if (lum > 0.6) {
			em += 1.2 * pow(max(sin(TIME * 1.9 + hash12(lp + ph * 31.0) * 40.0), 0.0), 20.0);
		}
	} else if (vcol.b > 0.1) {   // crystal sparkle on the bright facets
		em *= 0.8 + 0.2 * lum;
		float tw = hash12(lp + ph * 31.0);
		if (lum > 0.75) {
			em += 3.0 * pow(max(sin(TIME * 2.3 + tw * 40.0), 0.0), 16.0);
		}
	}
	col *= sh.x * (1.0 - 0.6 * below);
	col += vec3(0.16, 0.15, 0.13) * sh.y * clamp(ln.y + 0.4, 0.0, 1.0) * (1.0 - below);
	ALBEDO = col;
	EMISSION = t.rgb * em * (1.0 - f * 0.7) * mix(1.0, 0.4, step(0.5, front));
	if (plight_k > 0.0) {  // player light (shader): every visible block, soft 3D falloff, vox occlusion
		EMISSION += c * plight_col * plight(wpos, ln) * plight_k * edge_k * fade * (1.0 - f * 0.6);
	}
	if (fow_on && !cap) {  // fog of war: unknown = pure black, explored = dim memory (no dynamic light)
		float fs = fow_at(fow_cell(wpos, wnrm));
		if (fs < 0.25) {
			ALBEDO = vec3(0.0);
			EMISSION = vec3(0.0);
		} else {
			float k = fs > 0.75 ? 1.0 - smoothstep(fow_r - 5.0, fow_r, distance(wpos, plight_pos)) : 0.0;
			vec3 memc = vec3(dot(c, vec3(0.3, 0.5, 0.2))) * vec3(0.5, 0.55, 0.7) * 0.3 * sh.x * (1.0 - f * 0.5);
			ALBEDO *= k;
			EMISSION = EMISSION * k + memc * (1.0 - k);
		}
	}
	if (cap) {  // cut block: drawn as the block's own top (its texture, slightly darker) so it never looks hollow
		ALBEDO = t.rgb * 0.62 * sh.x;
		EMISSION = t.rgb * 0.05;
		if (fow_at(ivec3(floor(wpos - wnrm * 0.02))) < 0.25) { ALBEDO = vec3(0.0); EMISSION = vec3(0.0); }
	}
	}
}
