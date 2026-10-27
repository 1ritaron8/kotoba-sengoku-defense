shader_type canvas_item;
render_mode unshaded;

uniform vec4 source_region;
uniform vec2 source_shift;
uniform sampler2D object_mask : filter_linear;
uniform sampler2D restoration_map : source_color, filter_linear;
varying vec4 surface_tint;

void vertex() {
	surface_tint = COLOR;
}

float source_coverage(vec2 point) {
	vec2 inside = min(point - source_region.xy, source_region.xy + source_region.zw - point);
	if (inside.x < 0.0 || inside.y < 0.0) { return 0.0; }
	// The full-canvas SVG is rasterized once as functional alpha support.
	// This is a constant texture lookup, not a per-fragment polygon loop.
	return texture(object_mask, point).a;
}

void fragment() {
	vec4 authored = texture(TEXTURE, UV);
	float old_footprint = source_coverage(UV);
	if (old_footprint > 0.0) {
		// Restore only the original irregular island footprint. All unrelated
		// map pixels remain the untouched authored texture.
		authored = mix(authored, texture(restoration_map, UV), old_footprint);
	}
	vec2 moved_source = UV - source_shift;
	float moved_footprint = source_coverage(moved_source);
	if (moved_footprint > 0.0) {
		// Move original object RGB, not generated geometry or surrounding
		// rectangular grass. The foreground rail uses these same source pixels.
		authored = mix(authored, texture(TEXTURE, moved_source), moved_footprint);
	}
	COLOR = authored * surface_tint;
}
