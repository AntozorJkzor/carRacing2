extends RefCounted

## Visual layers the minimap camera does not include.
## Effects stay on the main view. Lights stay on the main view, but a camera that
## cannot see the light never builds that light's shadow map.
const EFFECTS := 1 << 1
const LIGHTS := 1 << 19
const ALL := 0xFFFFF
