// --- VIEW --- level cut (3rd person, X): ONE global roof cut, aligned on the grid (cells at y >= cut_y are hidden),
// the same everywhere. It only moves when the player's floor changes by 2+ blocks (IsoView), so the scenery is stable.
// A cell is either fully drawn or fully hidden; caps are real geometry built by IsoView (vertex alpha 0).
// vox: R8 3D texture of the block ids (x, y, z), used for the cut, per-texel AO and edge outlines.
uniform bool slice_main = false; // main view applies the level cut
uniform bool ao_main = false;  // main view uses AO (3rd person, FPS)
uniform bool cut_main = true;  // main view is 2D
uniform highp sampler3D vox : filter_nearest;
uniform int lvl_y = -1000;   // player's (hysteresis) floor level
uniform int cut_y = 100000;
uniform vec2 pxz = vec2(0.0);  // player position (view radius)
// "Grow far" (2D view): layers behind the player's plane are enlarged around the player (x/y/z perpendicular to the
// view axis), the more the farther they are. Depth order is untouched. Only the vertices move (picking, cut and light
// keep using the real world position).
uniform float ppos_y = 0.0;
uniform bool occl_3d = false;  // 3rd person camera: blocks between the camera and the player are see-through too
uniform bool narrow = false;  // the player is in a tight spot: cut every layer in front (side view stays readable)
// Blocks that stand between the camera and the player (the whole cell, not a round window) are ghosted.
bool occludes(vec3 wp, vec3 wn, vec3 cam) {
	vec3 cc = floor(wp - wn * 0.02) + 0.5;
	vec3 pc = vec3(pxz.x, ppos_y, pxz.y);
	vec3 ab = pc - cam;
	float t = dot(cc - cam, ab) / max(dot(ab, ab), 0.0001);
	if (t <= 0.0 || t >= 1.0) { return false; }
	float dl = length(cc - (cam + ab * t));
	return dl < 1.15 && length(cc - pc) > 0.9;
}
uniform float warp_k = 0.0;     // growth per layer beyond warp_free (0 = off)
const float WARP_FREE = 2.0;    // layers around the player that keep their normal size
const float WARP_MAX = 2.4;
// Organic wobble: every grid corner is nudged by a small stable offset (same corner = same offset, so no cracks).
uniform float jitter = 0.0;
vec3 jitter_hash(vec3 k) {
	float a = fract(sin(dot(k, vec3(12.9898, 78.233, 37.719))) * 43758.5453);
	float b = fract(sin(dot(k, vec3(39.346, 11.135, 83.155))) * 24634.6345);
	float c = fract(sin(dot(k, vec3(73.156, 52.235, 9.151))) * 31415.9265);
	return vec3(a, b, c) - 0.5;
}
// décalage des sommets : valeur de hachage aux coins entiers, INTERPOLÉE (trilinéaire) entre eux : continu, donc les faces voisines
// restent soudées même quand une face est subdivisée (relief du sol) et qu'une autre ne l'est pas.
vec3 jitter_pos(vec3 wp) {
	if (jitter <= 0.0) { return vec3(0.0); }
	vec3 i = floor(wp);
	vec3 f = fract(wp);
	vec3 r000 = jitter_hash(i);
	vec3 r100 = jitter_hash(i + vec3(1.0, 0.0, 0.0));
	vec3 r010 = jitter_hash(i + vec3(0.0, 1.0, 0.0));
	vec3 r110 = jitter_hash(i + vec3(1.0, 1.0, 0.0));
	vec3 r001 = jitter_hash(i + vec3(0.0, 0.0, 1.0));
	vec3 r101 = jitter_hash(i + vec3(1.0, 0.0, 1.0));
	vec3 r011 = jitter_hash(i + vec3(0.0, 1.0, 1.0));
	vec3 r111 = jitter_hash(i + vec3(1.0, 1.0, 1.0));
	vec3 j = mix(mix(mix(r000, r100, f.x), mix(r010, r110, f.x), f.y), mix(mix(r001, r101, f.x), mix(r011, r111, f.x), f.y), f.z);
	return j * 2.0 * jitter * vec3(1.0, 0.8, 1.0);
}
// 3rd person: the world bends away with the horizontal distance to the camera (far = lower and smaller, a longer view).
uniform float bend_k = 0.0;
vec3 bend_pos(vec3 wp, vec3 cam) {
	if (bend_k <= 0.0) { return vec3(0.0); }
	vec2 d = wp.xz - cam.xz;
	return vec3(0.0, -bend_k * dot(d, d), 0.0);
}
uniform float curve_k = 0.0;    // world curvature: far layers also rise, like a small planet's horizon
vec3 warp_pos(vec3 wp) {
	if ((warp_k <= 0.0 && curve_k <= 0.0) || !cut_main) { return wp; }
	float dd = dot(wp, cut_dir) - cut_depth;  // > 0: behind the player's plane
	float far = max(dd - WARP_FREE, 0.0);
	if (far <= 0.0) { return wp; }
	float s = min(1.0 + warp_k * far, WARP_MAX);
	vec3 c = vec3(pxz.x, ppos_y, pxz.y);
	vec3 off = wp - c;
	vec3 along = cut_dir * dot(off, cut_dir);
	vec3 r = c + along + (off - along) * s;
	r.y += curve_k * far * far;
	return r;
}

const int VKIND[19] = int[19](0, 1, 1, 1, 1, 1, 1, 2, 2, 1, 3, 3, 1, 3, 3, 3, 1, 1, 4);

const ivec3 WORLD_SIZE = ivec3(160, 64, 80);  // = World.SX, SY, SZ (garder identique à world.gd)

int vox_id(ivec3 c) {
	if (c.x < 0 || c.y < 0 || c.z < 0 || c.x >= WORLD_SIZE.x || c.y >= WORLD_SIZE.y || c.z >= WORLD_SIZE.z) { return 9; }
	return min(int(texelFetch(vox, c, 0).r * 255.0 + 0.5), 18);
}

bool slice_hidden(ivec3 c, bool sl) {
	return sl && c.y >= cut_y;
}

bool vox_solid(ivec3 c, bool sl) {
	return VKIND[vox_id(c)] == 1 && !slice_hidden(c, sl);
}

float vox_ao(float s1, float s2, float c) {
	return (s1 > 0.5 && s2 > 0.5) ? 0.0 : 3.0 - (s1 + s2 + c);
}

// Minecraft-style ambient occlusion, interpolated per texel, plus a 1-texel rim on convex edges.
// Returns (ao factor, rim strength 0..1).
vec2 vox_shade(vec3 wp, vec3 wn, bool cap, bool sl) {
	if (max(max(abs(wn.x), abs(wn.y)), abs(wn.z)) < 0.99) { return vec2(1.0, 0.0); }
	ivec3 N = ivec3(round(wn));
	ivec3 c = ivec3(floor(wp - wn * 0.02));
	ivec3 a = c + N;
	ivec3 t1;
	ivec3 t2;
	vec2 q;
	if (N.y != 0) { t1 = ivec3(1, 0, 0); t2 = ivec3(0, 0, 1); q = wp.xz; }
	else if (N.x != 0) { t1 = ivec3(0, 0, 1); t2 = ivec3(0, 1, 0); q = wp.zy; }
	else { t1 = ivec3(1, 0, 0); t2 = ivec3(0, 1, 0); q = wp.xy; }
	q = (floor(fract(q) * 16.0) + 0.5) / 16.0;
	if (cap) {  // cut faces: no AO; rim only where real air (a cave) borders the cut, never on hidden rock
		float e0 = 1.0 / 16.0;
		bool r = (q.x < e0 && VKIND[vox_id(c - t1)] != 1) || (q.x > 1.0 - e0 && VKIND[vox_id(c + t1)] != 1)
			|| (q.y < e0 && VKIND[vox_id(c - t2)] != 1) || (q.y > 1.0 - e0 && VKIND[vox_id(c + t2)] != 1);
		return vec2(1.0, r ? 1.0 : 0.0);
	}
	float xm = float(vox_solid(a - t1, sl));
	float xp = float(vox_solid(a + t1, sl));
	float ym = float(vox_solid(a - t2, sl));
	float yp = float(vox_solid(a + t2, sl));
	float v00 = vox_ao(xm, ym, float(vox_solid(a - t1 - t2, sl)));
	float v10 = vox_ao(xp, ym, float(vox_solid(a + t1 - t2, sl)));
	float v01 = vox_ao(xm, yp, float(vox_solid(a - t1 + t2, sl)));
	float v11 = vox_ao(xp, yp, float(vox_solid(a + t1 + t2, sl)));
	float av = mix(mix(v00, v10, q.x), mix(v01, v11, q.x), q.y);
	float ao = mix(0.5, 1.0, av / 3.0);
	float e = 1.0 / 16.0;
	float rim = 0.0;
	if (q.x < e && xm < 0.5 && !vox_solid(c - t1, sl)) { rim = 1.0; }
	if (q.x > 1.0 - e && xp < 0.5 && !vox_solid(c + t1, sl)) { rim = 1.0; }
	if (q.y < e && ym < 0.5 && !vox_solid(c - t2, sl)) { rim = 1.0; }
	if (q.y > 1.0 - e && yp < 0.5 && !vox_solid(c + t2, sl)) { rim = 1.0; }
	return vec2(ao, rim);
}

// --- player light, computed per fragment: soft falloff with the 3D distance to the player, every visible block
// (front, behind, below), stronger on the nearest blocks, dimmed by the solid cells crossed (vox).
uniform vec3 plight_pos = vec3(-9999.0);
uniform float plight_r = 12.0;
uniform vec3 plight_col : source_color = vec3(1.0, 0.86, 0.64);
uniform float plight_k = 0.9;

float plight(vec3 wp, vec3 wn) {
	vec3 dv = plight_pos - wp;
	float dist = length(dv);
	if (dist > plight_r) { return 0.0; }
	float x = dist / plight_r;
	float a = (1.0 - x * x) * (1.0 - x * x);       // soft edge at plight_r
	a *= 0.45 + 0.55 / (1.0 + dist * dist * 0.18);  // strong on the neighbouring blocks
	vec3 L = dv / max(dist, 0.001);
	a *= 0.55 + 0.45 * max(dot(wn, L), 0.0);
	// occlusion: march through the voxel grid toward the player, each solid cell crossed dims the light
	vec3 p0 = wp + wn * 0.05;
	ivec3 own = ivec3(floor(wp - wn * 0.02));
	float occ = 1.0;
	for (int i = 1; i < 8; i++) {
		vec3 sp = mix(p0, plight_pos, float(i) / 8.0);
		ivec3 c = ivec3(floor(sp));
		if (c != own && VKIND[vox_id(c)] == 1) { occ *= 0.62; }
	}
	return a * occ;
}

// --- voxel fog of war (FogOfWar, scripts/view/fog.gd): 0 = unknown, 0.5 = explored (memory), 1 = seen now
uniform bool fow_on = false;
uniform highp sampler3D fow : filter_nearest;
uniform float fow_r = 22.0;

float fow_at(ivec3 c) {
	if (!fow_on || c.x < 0 || c.y < 0 || c.z < 0 || c.x >= WORLD_SIZE.x || c.y >= WORLD_SIZE.y || c.z >= WORLD_SIZE.z) { return 1.0; }
	return texelFetch(fow, c, 0).r;
}

// cell whose visibility decides a face: the air side of a cube face, the own cell otherwise (plants, fluids)
ivec3 fow_cell(vec3 wp, vec3 wn) {
	if (max(max(abs(wn.x), abs(wn.y)), abs(wn.z)) > 0.99) { return ivec3(floor(wp + wn * 0.5)); }
	return ivec3(floor(wp - wn * 0.02));
}
