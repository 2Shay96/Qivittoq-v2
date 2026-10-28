shader_type sky;
// The overcast sky. Its colors come from scripts/look.gd through the shared globals, so the haze,
// the sky and the mountains all agree.

#include "res://shaders/common.gdshaderinc"

void sky() {
	COLOR = sky_color(EYEDIR);
}
