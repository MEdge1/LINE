class_name WorkspaceVisuals
extends RefCounted

# Presentation-only tuning for the workspace: world boundary, unlocked and locked cell treatment,
# placement emphasis, and expansion feedback. Nothing here is read by the simulation or progression.

# Hard world boundary around the full 5×9 grid. Drawn at every zoom and at every unlock state.
const BOUNDARY_WIDTH := 5.0
const BOUNDARY_ALPHA := 0.55
const BOUNDARY_GLOW_WIDTH := 14.0
const BOUNDARY_GLOW_ALPHA := 0.08
const CORNER_LENGTH := 34.0

# Buildable cells: a small marker, a faint outline, and a very low tint.
const UNLOCKED_MARKER_RADIUS := 3.5
const UNLOCKED_MARKER_ALPHA := 0.5
const UNLOCKED_OUTLINE_ALPHA := 0.16
const UNLOCKED_TINT_ALPHA := 0.04
const CELL_INSET := 12.0

# Locked but expandable cells: darkened, with a dim point and no icon.
const LOCKED_MARKER_RADIUS := 2.0
const LOCKED_MARKER_ALPHA := 0.16
const LOCKED_FILL_ALPHA := 0.35

# Placement mode: valid empty cells are brightened. Invalid cells keep their normal treatment.
const PLACEMENT_VALID_OUTLINE_ALPHA := 0.6
const PLACEMENT_VALID_TINT_ALPHA := 0.1

# The next expansion's cells are outlined while the Progress sheet is open.
const PREVIEW_OUTLINE_ALPHA := 0.45

# Expansion feedback: locked cells brighten into unlocked cells, then a soft glow fades out.
const REVEAL_TRANSITION_SECONDS := 0.45
const REVEAL_SECONDS := 1.8
const REVEAL_GLOW_ALPHA := 0.35
