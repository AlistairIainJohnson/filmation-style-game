shader_type spatial;
render_mode cull_back, depth_draw_opaque;

global uniform vec3 player_world_pos;

uniform vec4 albedo_color : source_color = vec4(0.47, 0.46, 0.44, 1.0);
uniform float metallic_val : hint_range(0.0, 1.0) = 0.04;
uniform float roughness_val : hint_range(0.0, 1.0) = 0.78;
uniform float cutaway_radius : hint_range(0.2, 4.0) = 1.25;
uniform float cutaway_softness : hint_range(0.05, 1.5) = 0.45;
uniform float depth_bias : hint_range(0.0, 1.0) = 0.10;
uniform float max_cutaway_transparency : hint_range(0.0, 0.95) = 0.58;
uniform vec4 emission_color : source_color = vec4(0.0, 0.0, 0.0, 1.0);
uniform float emission_energy : hint_range(0.0, 8.0) = 0.0;
instance uniform float cutaway_active : hint_range(0.0, 1.0) = 0.0;

float bayer8(ivec2 p) {
	int x = p.x & 7;
	int y = p.y & 7;
	int idx = x + y * 8;
	const int M[64] = int[64](
		 0, 32,  8, 40,  2, 34, 10, 42,
		48, 16, 56, 24, 50, 18, 58, 26,
		12, 44,  4, 36, 14, 46,  6, 38,
		60, 28, 52, 20, 62, 30, 54, 22,
		 3, 35, 11, 43,  1, 33,  9, 41,
		51, 19, 59, 27, 49, 17, 57, 25,
		15, 47,  7, 39, 13, 45,  5, 37,
		63, 31, 55, 23, 61, 29, 53, 21
	);
	return (float(M[idx]) + 0.5) / 64.0;
}

void fragment() {
	if (cutaway_active > 0.001) {
		vec3 player_view = (VIEW_MATRIX * vec4(player_world_pos, 1.0)).xyz;
		// In camera view space (-Z is forward):
		// An occluder in FRONT of the player (between camera and player) has a LESS negative Z than the player.
		// VERTEX.z is in view space. Therefore VERTEX.z > player_view.z + depth_bias means occluder is closer to camera.
		if (VERTEX.z > player_view.z + depth_bias) {
			vec2 delta = VERTEX.xy - player_view.xy;
			// Only clip occluders directly covering the player capsule silhouette (not overhead arch tops or side walls):
			if (delta.y > -0.75 && delta.y < 0.65 && abs(delta.x) < 0.55) {
				vec2 norm_delta = vec2(delta.x / 0.50, delta.y / 0.65);
				float dist_capsule = length(norm_delta);
				float factor = (1.0 - smoothstep(0.65, 1.0, dist_capsule)) * cutaway_active * max_cutaway_transparency;
				if (factor > bayer8(ivec2(FRAGCOORD.xy))) {
					discard;
				}
			}
		}
	}

	ALBEDO = albedo_color.rgb;
	METALLIC = metallic_val;
	ROUGHNESS = roughness_val;
	if (emission_energy > 0.001) {
		EMISSION = emission_color.rgb * emission_energy;
	}
}
