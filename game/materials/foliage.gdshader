shader_type spatial;
render_mode cull_disabled, diffuse_burley, specular_schlick_ggx;
uniform vec4 dry_color : source_color = vec4(0.48,0.43,0.22,1.0);
uniform vec4 fresh_color : source_color = vec4(0.29,0.37,0.17,1.0);
uniform float vitality : hint_range(0.0,1.0) = 0.35;
uniform float wind_strength = 0.07;
uniform float crop_mode = 0.0;
varying float shade;
varying float tip;
void vertex() {
	vec3 world=(MODEL_MATRIX*vec4(VERTEX,1.0)).xyz;
	tip=UV.y;
	float phase=world.x*0.63+world.z*0.37;
	VERTEX.x += sin(TIME*1.8+phase)*wind_strength*UV.y;
	VERTEX.z += cos(TIME*1.1+phase*0.6)*wind_strength*UV.y*0.45;
	VERTEX.y *= mix(1.0,mix(0.18,1.0,vitality),crop_mode);
	shade = COLOR.r;
}
void fragment() {
	vec3 base=mix(dry_color.rgb,fresh_color.rgb,vitality);
	ALBEDO=base*mix(0.72,1.17,shade)*mix(0.65,1.12,tip);
	ROUGHNESS=0.88;
	BACKLIGHT=base*0.3;
	SPECULAR=0.22;
}
