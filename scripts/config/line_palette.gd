class_name LinePalette

# Centralized prototype colors. Change them here only.

const BACKGROUND := Color("#0b1020")
const CONNECTION := Color("#64748b")
const FLOW_GLOW := Color("#bae6fd")
const GENERATOR := Color("#38bdf8")
const PROCESSOR := Color("#a855f7")
const OUTPUT := Color("#22c55e")
const SPLITTER := Color("#f472b6")
const MERGER := Color("#2dd4bf")
const BOOSTER := Color("#fb923c")
const BOOSTER_LINK := Color("#fdba74")
const UNIT := Color("#f8fafc")
const PROCESSED_UNIT := Color("#67e8f9")
const SELECTION := Color("#f59e0b")
const WARNING := Color("#f59e0b")
const BOTTLENECK := Color("#ef4444")
const TEXT := Color("#e2e8f0")
const PANEL := Color("#111827")
const PAYOUT_HIGHLIGHT := Color("#fbbf24")
const GRID_DOT := Color("#334155")
const INVALID := Color("#ef4444")

# One colour stop per ComplexityVisuals.TIER_STARTS entry. Colours are interpolated between stops.
const COMPLEXITY_TIER_COLORS := [
	Color("#e0f7ff"),
	Color("#60a5fa"),
	Color("#a78bfa"),
	Color("#e879f9"),
	Color("#f97316"),
	Color("#fef08a"),
]


static func for_node_type(type: int) -> Color:
	match type:
		NodeDefinitions.Type.GENERATOR:
			return GENERATOR
		NodeDefinitions.Type.PROCESSOR:
			return PROCESSOR
		NodeDefinitions.Type.SPLITTER:
			return SPLITTER
		NodeDefinitions.Type.MERGER:
			return MERGER
		NodeDefinitions.Type.BOOSTER:
			return BOOSTER
		_:
			return OUTPUT
