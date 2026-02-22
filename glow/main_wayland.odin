#+build linux

package glow

import "glow_wayland"

main :: proc() {
	glow_wayland.main()
}
