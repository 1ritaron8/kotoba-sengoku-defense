shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;

// One page is deliberately small enough for Compatibility uniform limits.
uniform int circle_count = 0;
uniform vec4 circles[16]; // normalized X/Z centre, radius, full line width in pixels
uniform vec4 fill_colors[16] : source_color;
uniform vec4 outline_colors[16] : source_color;
uniform float surface_bias = 0.002;

void vertex() {
	// Common presentation-only vertical bias; X/Z and combat surfaces are untouched.
	VERTEX.y += surface_bias;
}

void fragment() {
	vec4 accumulated = vec4(0.0); // premultiplied, composed in descriptor order
	for (int index = 0; index < 16; index++) {
		if (index < circle_count) {
			float signed_distance = length(UV - circles[index].xy) - circles[index].z;
			float pixel = max(length(vec2(dFdx(signed_distance), dFdy(signed_distance))), 0.00000001);
			float fill_coverage = 1.0 - smoothstep(-0.5 * pixel, 0.5 * pixel, signed_distance);
			float half_width = 0.5 * circles[index].w * pixel;
			float ring_coverage = 1.0 - smoothstep(half_width - 0.5 * pixel, half_width + 0.5 * pixel, abs(signed_distance));
			float fill_alpha = fill_colors[index].a * fill_coverage;
			accumulated.rgb = fill_colors[index].rgb * fill_alpha + accumulated.rgb * (1.0 - fill_alpha);
			accumulated.a = fill_alpha + accumulated.a * (1.0 - fill_alpha);
			float outline_alpha = outline_colors[index].a * ring_coverage;
			accumulated.rgb = outline_colors[index].rgb * outline_alpha + accumulated.rgb * (1.0 - outline_alpha);
			accumulated.a = outline_alpha + accumulated.a * (1.0 - outline_alpha);
		}
	}
	// Mesh coverage supplies holes and boundaries. No polygon edge creates an outline.
	if (accumulated.a <= 0.000001) { discard; }
	ALBEDO = accumulated.rgb / max(accumulated.a, 0.000001);
	ALPHA = accumulated.a;
}
