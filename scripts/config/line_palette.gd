class_name LinePalette

# Centralized prototype colors. Change them here only.

const BACKGROUND := Color("#0b1020")
const CONNECTION := Color("#64748b")
const FLOW_GLOW := Color("#bae6fd")
const GENERATOR := Color("#38bdf8")
const PROCESSOR := Color("#a855f7")
const OUTPUT := Color("#22c55e")
const UNIT := Color("#f8fafc")
const PROCESSED_UNIT := Color("#67e8f9")
const SELECTION := Color("#f59e0b")
const TEXT := Color("#e2e8f0")
const PANEL := Color("#111827")
const PAYOUT_HIGHLIGHT := Color("#fbbf24")
const GRID_DOT := Color("#334155")
const INVALID := Color("#ef4444")


static func for_node_type(type: int) -> Color:
	if type == NodeDefinitions.Type.GENERATOR:
		return GENERATOR
	if type == NodeDefinitions.Type.PROCESSOR:
		return PROCESSOR
	return OUTPUT
