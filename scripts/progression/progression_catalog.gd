class_name ProgressionCatalog
extends RefCounted

# Progression data: technologies, objectives, and workspace expansions. Algorithms live in
# ProgressionManager, ObjectiveManager, and StatisticsManager. Money values are exact texts so
# large targets never pass through float. Rates and seconds are prototype values to be playtested.

const STAGE_FLOW := "FLOW"
const STAGE_VALUE := "VALUE"
const STAGE_ROUTING := "ROUTING"
const STAGE_OPTIMIZATION := "OPTIMIZATION"
const STAGE_SCALE := "SCALE"

# Technologies are keyed by node type name. Start technologies cost nothing and are unlocked at the start.
const TECHNOLOGIES := [
	{"id": "GENERATOR", "cost": 0, "prerequisite": "", "summary": "Produces resources"},
	{"id": "OUTPUT", "cost": 0, "prerequisite": "", "summary": "Pays money for resources"},
	{"id": "PROCESSOR", "cost": 1, "prerequisite": "", "summary": "Value ×2 · Complexity +1"},
	{"id": "SPLITTER", "cost": 1, "prerequisite": "PROCESSOR", "summary": "Branches one stream into two"},
	{"id": "MERGER", "cost": 1, "prerequisite": "SPLITTER", "summary": "Combines two streams into one"},
	{"id": "BOOSTER", "cost": 2, "prerequisite": "MERGER", "summary": "+25% to adjacent Processors"},
]

const START_TECHNOLOGIES := ["GENERATOR", "OUTPUT"]

# Cells unlocked at the start: columns 1-3, rows 3-5 of the 5×9 grid.
const START_CELLS := [
	Vector2i(1, 3), Vector2i(2, 3), Vector2i(3, 3),
	Vector2i(1, 4), Vector2i(2, 4), Vector2i(3, 4),
	Vector2i(1, 5), Vector2i(2, 5), Vector2i(3, 5),
]

# Workspace expansion steps, bought in order with money. Each step unlocks the listed cells.
const EXPANSIONS := [
	{"cost": 150, "cells": [Vector2i(1, 2), Vector2i(2, 2), Vector2i(3, 2)]},
	{"cost": 150, "cells": [Vector2i(1, 6), Vector2i(2, 6), Vector2i(3, 6)]},
	{"cost": 400, "cells": [Vector2i(0, 2), Vector2i(0, 3), Vector2i(0, 4), Vector2i(0, 5), Vector2i(0, 6)]},
	{"cost": 400, "cells": [Vector2i(4, 2), Vector2i(4, 3), Vector2i(4, 4), Vector2i(4, 5), Vector2i(4, 6)]},
	{"cost": 1000, "cells": [Vector2i(1, 1), Vector2i(2, 1), Vector2i(3, 1)]},
	{"cost": 1000, "cells": [Vector2i(1, 7), Vector2i(2, 7), Vector2i(3, 7)]},
	{"cost": 2000, "cells": [Vector2i(1, 0), Vector2i(2, 0), Vector2i(3, 0)]},
	{"cost": 2000, "cells": [Vector2i(1, 8), Vector2i(2, 8), Vector2i(3, 8)]},
	{"cost": 3000, "cells": [Vector2i(0, 0), Vector2i(0, 1), Vector2i(0, 7), Vector2i(0, 8)]},
	{"cost": 3000, "cells": [Vector2i(4, 0), Vector2i(4, 1), Vector2i(4, 7), Vector2i(4, 8)]},
]

# Conditions are the building blocks of objectives. Every condition in an objective must be met.
#   BUILD_NODE          count of a node type built since the objective became active
#   CONNECT             a connection from one node type to another exists now
#   EARN                lifetime payouts since the objective became active reach `amount`
#   UPGRADE             Generator upgrades since the objective became active reach `count`
#   UNLOCK_TECH         a technology is unlocked now
#   PROCESS             units processed by Processors since the objective became active reach `units`
#   DELIVER_COMPLEXITY  the highest Product Complexity paid out so far reaches `level`
#   REACH_THROUGHPUT    completed units per second now reach `units_per_sec`
#   REACH_REVENUE_RATE  network revenue per second now reaches `per_sec`
#   BOTTLENECK_FREE     seconds without any active bottleneck, counted from activation, reach `seconds`
#   USE_BOOSTER         Processors currently boosted reach `count`
#   NETWORK_SIZE        nodes currently on the grid reach `count`
#   WORKSPACE_CELLS     unlocked grid cells reach `count`
#   ALL_TECHNOLOGIES    every technology is unlocked
const OBJECTIVES := [
	{
		"id": "build_generator", "stage": STAGE_FLOW, "prerequisites": [],
		"title": "Build a Generator", "hint": "Tap BUILD, choose GENERATOR, then tap an empty cell",
		"reward_money": "20", "reward_rp": 0,
		"conditions": [{"type": "BUILD_NODE", "node": "GENERATOR", "count": 1}],
	},
	{
		"id": "build_output", "stage": STAGE_FLOW, "prerequisites": ["build_generator"],
		"title": "Build an Output", "hint": "Outputs pay money for resources that reach them",
		"reward_money": "20", "reward_rp": 0,
		"conditions": [{"type": "BUILD_NODE", "node": "OUTPUT", "count": 1}],
	},
	{
		"id": "connect_line", "stage": STAGE_FLOW, "prerequisites": ["build_output"],
		"title": "Connect the line", "hint": "Select the Generator, then drag from its handle to the Output",
		"reward_money": "30", "reward_rp": 1,
		"conditions": [{"type": "CONNECT", "from": "GENERATOR", "to": "OUTPUT"}],
	},
	{
		"id": "earn_100", "stage": STAGE_FLOW, "prerequisites": ["connect_line"],
		"title": "Earn $100", "hint": "Let the line run and watch the money grow",
		"reward_money": "50", "reward_rp": 0,
		"conditions": [{"type": "EARN", "amount": "100"}],
	},
	{
		"id": "upgrade_generator", "stage": STAGE_FLOW, "prerequisites": ["earn_100"],
		"title": "Upgrade your Generator", "hint": "Select the Generator and tap UPGRADE",
		"reward_money": "100", "reward_rp": 0,
		"conditions": [{"type": "UPGRADE", "count": 1}],
	},
	{
		"id": "unlock_processing", "stage": STAGE_VALUE, "prerequisites": ["upgrade_generator"],
		"title": "Unlock Processing", "hint": "Open PROGRESS and unlock PROCESSOR with Research Points",
		"reward_money": "50", "reward_rp": 1,
		"conditions": [{"type": "UNLOCK_TECH", "tech": "PROCESSOR"}],
	},
	{
		"id": "build_processor", "stage": STAGE_VALUE, "prerequisites": ["unlock_processing"],
		"title": "Build a Processor", "hint": "Place it between the Generator and the Output",
		"reward_money": "75", "reward_rp": 0,
		"conditions": [{"type": "BUILD_NODE", "node": "PROCESSOR", "count": 1}],
	},
	{
		"id": "process_10", "stage": STAGE_VALUE, "prerequisites": ["build_processor"],
		"title": "Process 10 units", "hint": "Each Processor doubles what it carries",
		"reward_money": "150", "reward_rp": 1,
		"conditions": [{"type": "PROCESS", "units": "10"}],
	},
	{
		"id": "complexity_1", "stage": STAGE_VALUE, "prerequisites": ["process_10"],
		"title": "Deliver Complexity 1", "hint": "Processed resources arrive with higher complexity",
		"reward_money": "200", "reward_rp": 0,
		"conditions": [{"type": "DELIVER_COMPLEXITY", "level": 1}],
	},
	{
		"id": "unlock_splitting", "stage": STAGE_ROUTING, "prerequisites": ["complexity_1"],
		"title": "Unlock Splitting", "hint": "Open PROGRESS and unlock SPLITTER",
		"reward_money": "0", "reward_rp": 0,
		"conditions": [{"type": "UNLOCK_TECH", "tech": "SPLITTER"}],
	},
	{
		"id": "build_splitter", "stage": STAGE_ROUTING, "prerequisites": ["unlock_splitting"],
		"title": "Build a Splitter", "hint": "A Splitter sends its stream down two branches",
		"reward_money": "150", "reward_rp": 0,
		"conditions": [{"type": "BUILD_NODE", "node": "SPLITTER", "count": 1}],
	},
	{
		"id": "build_branches", "stage": STAGE_ROUTING, "prerequisites": ["build_splitter"],
		"title": "Build two more Processors", "hint": "Run each branch through its own Processor",
		"reward_money": "250", "reward_rp": 1,
		"conditions": [{"type": "BUILD_NODE", "node": "PROCESSOR", "count": 2}],
	},
	{
		"id": "unlock_merging", "stage": STAGE_ROUTING, "prerequisites": ["build_branches"],
		"title": "Unlock Merging", "hint": "Open PROGRESS and unlock MERGER",
		"reward_money": "0", "reward_rp": 0,
		"conditions": [{"type": "UNLOCK_TECH", "tech": "MERGER"}],
	},
	{
		"id": "build_merger", "stage": STAGE_ROUTING, "prerequisites": ["unlock_merging"],
		"title": "Build a Merger", "hint": "A Merger joins two streams into one route",
		"reward_money": "200", "reward_rp": 0,
		"conditions": [{"type": "BUILD_NODE", "node": "MERGER", "count": 1}],
	},
	{
		"id": "throughput_2", "stage": STAGE_OPTIMIZATION, "prerequisites": ["build_merger"],
		"title": "Reach 2 units per second", "hint": "Completed units per second are shown in the header",
		"reward_money": "500", "reward_rp": 1,
		"conditions": [{"type": "REACH_THROUGHPUT", "units_per_sec": 2.0}],
	},
	{
		"id": "unlock_boosting", "stage": STAGE_OPTIMIZATION, "prerequisites": ["throughput_2"],
		"title": "Unlock Boosting", "hint": "Open PROGRESS and unlock BOOSTER",
		"reward_money": "0", "reward_rp": 0,
		"conditions": [{"type": "UNLOCK_TECH", "tech": "BOOSTER"}],
	},
	{
		"id": "use_booster", "stage": STAGE_OPTIMIZATION, "prerequisites": ["unlock_boosting"],
		"title": "Boost a Processor", "hint": "Place a Booster beside a Processor",
		"reward_money": "800", "reward_rp": 1,
		"conditions": [
			{"type": "BUILD_NODE", "node": "BOOSTER", "count": 1},
			{"type": "USE_BOOSTER", "count": 1},
		],
	},
	{
		"id": "bottleneck_free", "stage": STAGE_OPTIMIZATION, "prerequisites": ["use_booster"],
		"title": "Hold steady for 30 seconds", "hint": "Clear every bottleneck and keep the line moving",
		"reward_money": "1000", "reward_rp": 1,
		"conditions": [{"type": "BOTTLENECK_FREE", "seconds": 30.0}],
	},
	{
		"id": "expand_space", "stage": STAGE_SCALE, "prerequisites": ["bottleneck_free"],
		"title": "Expand the workspace", "hint": "Open PROGRESS and buy more space",
		"reward_money": "500", "reward_rp": 0,
		"conditions": [{"type": "WORKSPACE_CELLS", "count": 15}],
	},
	{
		"id": "network_stable", "stage": STAGE_SCALE, "prerequisites": ["expand_space"],
		"title": "Network Stable", "hint": "Master every system to finish the prototype",
		"reward_money": "5000", "reward_rp": 0,
		"conditions": [
			{"type": "ALL_TECHNOLOGIES"},
			{"type": "REACH_REVENUE_RATE", "per_sec": 1000.0},
			{"type": "DELIVER_COMPLEXITY", "level": 5},
			{"type": "NETWORK_SIZE", "count": 12},
			{"type": "WORKSPACE_CELLS", "count": 25},
			{"type": "BOTTLENECK_FREE", "seconds": 30.0},
		],
	},
]

const FINAL_OBJECTIVE := "network_stable"


static func technology_index(id: String) -> int:
	for index in range(TECHNOLOGIES.size()):
		if TECHNOLOGIES[index]["id"] == id:
			return index
	return -1


static func objective_index(id: String) -> int:
	for index in range(OBJECTIVES.size()):
		if OBJECTIVES[index]["id"] == id:
			return index
	return -1


static func node_type_for(name: String) -> int:
	for type in range(NodeDefinitions.TYPE_DATA.size()):
		if NodeDefinitions.get_display_name(type) == name:
			return type
	return -1
