class_name NetworkView
extends Node2D

# Draws the workspace from graph, layout, and simulation state. It owns only visual effects
# (flow particles, status rings, payout text, flashes, drag preview) and never changes network state.

const NODE_RADIUS := 40.0
const SELECTION_RADIUS := 54.0
const STATUS_RING_RADIUS := 52.0
const HANDLE_RADIUS := 11.0
const UNIT_RADIUS := 9.0
const CONNECTION_WIDTH := 6.0
const ARROW_SIZE := 14.0
const GRID_DOT_RADIUS := 2.5
const GRID_DOT_ALPHA := 0.25
const GRID_DOT_HINT_ALPHA := 0.6
const LABEL_FONT_SIZE := 18
const BADGE_FONT_SIZE := 16
const PAYOUT_FONT_SIZE := 26
const PAYOUT_DURATION := 0.9
const PAYOUT_RISE := 80.0
const PAYOUT_SPREAD := 40.0
const PAYOUT_SLOTS := 3
const PAYOUT_GLOW_ALPHA := 0.35
const PAYOUT_NAME_OFFSET := 26.0
const GLOW_HALO_SCALE := 2.2
const GLOW_HALO_ALPHA := 0.3
const FLASH_DURATION := 0.5
const WAITING_DOT_SPACING := 16.0
const BOOSTER_LINK_WIDTH := 3.0
const BOOSTER_LINK_ALPHA := 0.45
const STAR_INNER_RATIO := 0.5

class FloatingPayout:
	var amount: LargeNumber
	var output_id: int
	var complexity: int
	var lateral_offset: float
	var age: float = 0.0

	func _init(payout_amount: LargeNumber, node_id: int, payout_complexity: int, offset: float) -> void:
		amount = payout_amount
		output_id = node_id
		complexity = payout_complexity
		lateral_offset = offset


class Flash:
	var age: float = 0.0
	var cell: Vector2i = Vector2i.ZERO
	var from_id: int = 0
	var to_id: int = 0


var simulation: ProductionSimulation
var graph: NetworkGraph
var layout: WorkspaceLayout
var camera: WorkspaceCamera
var selected_id: int = 0
# Brightens empty cells while the player is choosing a destination.
var placement_hint: bool = false
# Live drag-to-connect preview, set by the controller each frame.
var preview_source_id: int = 0
var preview_pointer := Vector2.ZERO
var preview_target_id: int = 0
var preview_target_valid: bool = false

var _payouts: Array[FloatingPayout] = []
var _cell_flashes: Array[Flash] = []
var _connection_flashes: Array[Flash] = []


func _process(delta: float) -> void:
	_advance_effects(delta)
	queue_redraw()


func show_payout(amount: LargeNumber, output_id: int, complexity: int) -> void:
	# Cycle lateral slots so payouts arriving close together do not overlap.
	var slot := _payouts.size() % PAYOUT_SLOTS
	var lateral := (float(slot) - float(PAYOUT_SLOTS - 1) * 0.5) * PAYOUT_SPREAD
	_payouts.append(FloatingPayout.new(amount, output_id, complexity, lateral))

	if _payouts.size() > VisualLimits.PAYOUT_INDICATORS:
		_payouts.pop_front()


func flash_cell(cell: Vector2i) -> void:
	var flash := Flash.new()
	flash.cell = cell
	_cell_flashes.append(flash)


func flash_connection(from_id: int, to_id: int) -> void:
	var flash := Flash.new()
	flash.from_id = from_id
	flash.to_id = to_id
	_connection_flashes.append(flash)


# Representative particles to draw this frame, capped per connection and in total.
# Each entry is {from, to, along, position, color, radius, glow, trail, quantity, badge}. Totals in the simulation are unaffected.
func plan_particles() -> Array:
	var plan: Array = []
	var per_connection: Dictionary = {}

	for batch in simulation.in_flight:
		if plan.size() >= VisualLimits.PARTICLES_TOTAL:
			break

		var connection := Vector2i(batch.from_id, batch.to_id)
		var used: int = per_connection.get(connection, 0)
		var room := mini(VisualLimits.PARTICLES_PER_CONNECTION - used, VisualLimits.PARTICLES_TOTAL - plan.size())
		if room <= 0:
			continue

		var count := mini(FlowDensity.representative_count(batch.quantity), room)
		per_connection[connection] = used + count

		var large := FlowDensity.is_large(batch.quantity)
		var radius := UNIT_RADIUS * (1.4 if large else 1.0) * ComplexityStyle.radius_scale(batch.complexity)
		var color := ComplexityStyle.color(batch.complexity)
		var from_position := _node_position(batch.from_id)
		var to_position := _node_position(batch.to_id)
		var phase := fposmod(float(batch.from_id * 31 + batch.to_id * 17), 1.0) * VisualLimits.PHASE_SPREAD
		var lead := batch.progress + phase

		for index in range(count):
			# Trailing particles follow the leader, so a batch reads as a stream rather than a stack.
			var along := lead - index * VisualLimits.PARTICLE_STAGGER
			if along < 0.0:
				break
			plan.append({
				"from": from_position,
				"to": to_position,
				"along": clampf(along, 0.0, 1.0),
				"position": from_position.lerp(to_position, clampf(along, 0.0, 1.0)),
				"color": color,
				"radius": radius,
				"glow": ComplexityStyle.glow_alpha(batch.complexity),
				"trail": ComplexityStyle.trail_ghosts(batch.complexity),
				"quantity": batch.quantity,
				"badge": index == 0 and used == 0 and batch.quantity.compare(LargeNumber.from_int(1)) > 0,
			})
	return plan


func _draw() -> void:
	if graph == null or layout == null or camera == null:
		return

	draw_set_transform(camera.offset, 0.0, Vector2.ONE * camera.zoom)
	var flow := _count_flow_per_connection()
	_draw_grid()
	_draw_booster_links()
	_draw_connections(flow)
	_draw_drag_preview()
	_draw_nodes()
	_draw_waiting_queues()
	_draw_particles()
	_draw_flashes()
	_draw_payouts()


func _advance_effects(delta: float) -> void:
	_advance_flashes(_cell_flashes, delta)
	_advance_flashes(_connection_flashes, delta)

	for index in range(_payouts.size() - 1, -1, -1):
		_payouts[index].age += delta
		if _payouts[index].age >= PAYOUT_DURATION:
			_payouts.remove_at(index)


func _advance_flashes(flashes: Array[Flash], delta: float) -> void:
	for index in range(flashes.size() - 1, -1, -1):
		flashes[index].age += delta
		if flashes[index].age >= FLASH_DURATION:
			flashes.remove_at(index)


func _node_position(id: int) -> Vector2:
	return layout.get_cell_center(layout.get_node_cell(id))


func _count_flow_per_connection() -> Dictionary:
	var flow: Dictionary = {}
	for batch in simulation.in_flight:
		var connection := Vector2i(batch.from_id, batch.to_id)
		flow[connection] = flow.get(connection, 0) + FlowDensity.representative_count(batch.quantity)
	return flow


func _draw_grid() -> void:
	for column in range(WorkspaceLayout.COLUMNS):
		for row in range(WorkspaceLayout.ROWS):
			var cell := Vector2i(column, row)
			var color := LinePalette.GRID_DOT
			color.a = GRID_DOT_HINT_ALPHA if placement_hint and layout.is_cell_free(cell) else GRID_DOT_ALPHA
			draw_circle(layout.get_cell_center(cell), GRID_DOT_RADIUS, color)


# Faint links from each Booster to the Processors it boosts. Drawn beneath connections.
func _draw_booster_links() -> void:
	for id in graph.get_node_ids():
		if graph.get_node(id).type != NodeDefinitions.Type.BOOSTER:
			continue
		var color := LinePalette.BOOSTER_LINK
		color.a = BOOSTER_LINK_ALPHA
		for neighbour in layout.get_neighbor_ids(id):
			if graph.get_node(neighbour).boosted:
				draw_line(_node_position(id), _node_position(neighbour), color, BOOSTER_LINK_WIDTH, true)


# Connections brighten with flow, so a busy route reads as busy without extra objects.
func _draw_connections(flow: Dictionary) -> void:
	for connection in graph.get_connections():
		var strength := clampf(float(flow.get(connection, 0)) / VisualLimits.CONNECTION_GLOW_AT, 0.0, 1.0)
		var color := LinePalette.CONNECTION.lerp(LinePalette.FLOW_GLOW, strength)
		_draw_connection(_node_position(connection.x), _node_position(connection.y), color)

	for flash in _connection_flashes:
		if graph.has_node(flash.from_id) and graph.has_node(flash.to_id):
			var color := _faded(LinePalette.INVALID, flash)
			_draw_connection(_node_position(flash.from_id), _node_position(flash.to_id), color)


func _draw_connection(from: Vector2, to: Vector2, color: Color) -> void:
	draw_line(from, to, color, CONNECTION_WIDTH, true)

	var direction := (to - from).normalized()
	var perpendicular := direction.orthogonal()
	var tip := to - direction * (NODE_RADIUS + 6.0)
	var base := tip - direction * ARROW_SIZE
	draw_colored_polygon(
		PackedVector2Array([
			tip,
			base + perpendicular * ARROW_SIZE * 0.5,
			base - perpendicular * ARROW_SIZE * 0.5,
		]),
		color
	)


func _draw_drag_preview() -> void:
	if preview_source_id == 0 or not graph.has_node(preview_source_id):
		return

	var from := _node_position(preview_source_id)
	var color := LinePalette.TEXT
	var to := preview_pointer

	if preview_target_id != 0:
		to = _node_position(preview_target_id)
		color = LinePalette.OUTPUT if preview_target_valid else LinePalette.INVALID
		draw_arc(to, SELECTION_RADIUS, 0.0, TAU, 48, color, 4.0, true)

	draw_line(from, to, color, CONNECTION_WIDTH, true)
	if preview_target_id == 0:
		draw_circle(to, HANDLE_RADIUS, color)


func _draw_nodes() -> void:
	for id in graph.get_node_ids():
		var node := graph.get_node(id)
		var center := _node_position(id)

		if id == selected_id:
			draw_arc(center, SELECTION_RADIUS, 0.0, TAU, 48, LinePalette.SELECTION, 4.0, true)

		_draw_status_ring(id, center)
		_draw_node_shape(node, center)
		if node.boosted:
			draw_arc(center, NODE_RADIUS + 8.0, 0.0, TAU, 40, LinePalette.BOOSTER_LINK, 2.0, true)

		_draw_label(center, NodeDefinitions.get_display_name(node.type))

	_draw_output_handle()


# Restrained status cues: amber for a busy node, red for a bottleneck or a blocked node.
func _draw_status_ring(id: int, center: Vector2) -> void:
	var status := simulation.get_status(id)
	if status == ProductionSimulation.Status.BOTTLENECK:
		draw_arc(center, STATUS_RING_RADIUS, 0.0, TAU, 48, LinePalette.BOTTLENECK, 5.0, true)
	elif status == ProductionSimulation.Status.BLOCKED:
		var blocked := LinePalette.BOTTLENECK
		blocked.a = 0.5
		draw_arc(center, STATUS_RING_RADIUS, 0.0, TAU, 48, blocked, 3.0, true)
	elif status == ProductionSimulation.Status.SATURATED:
		var busy := LinePalette.WARNING
		busy.a = 0.6
		draw_arc(center, STATUS_RING_RADIUS, 0.0, TAU, 48, busy, 3.0, true)


func _draw_node_shape(node: NetworkGraph.NetworkNode, center: Vector2) -> void:
	var color := LinePalette.for_node_type(node.type)
	match node.type:
		NodeDefinitions.Type.GENERATOR:
			draw_circle(center, NODE_RADIUS, color)
		NodeDefinitions.Type.PROCESSOR:
			draw_colored_polygon(_diamond(center), color)
		NodeDefinitions.Type.SPLITTER:
			draw_colored_polygon(_triangle(center, true), color)
		NodeDefinitions.Type.MERGER:
			draw_colored_polygon(_triangle(center, false), color)
		NodeDefinitions.Type.BOOSTER:
			draw_colored_polygon(_star(center), color)
		_:
			draw_rect(
				Rect2(center - Vector2(NODE_RADIUS, NODE_RADIUS), Vector2(NODE_RADIUS, NODE_RADIUS) * 2.0),
				color,
				true
			)


func _diamond(center: Vector2) -> PackedVector2Array:
	return PackedVector2Array([
		center + Vector2(0.0, -NODE_RADIUS),
		center + Vector2(NODE_RADIUS, 0.0),
		center + Vector2(0.0, NODE_RADIUS),
		center + Vector2(-NODE_RADIUS, 0.0),
	])


func _triangle(center: Vector2, point_up: bool) -> PackedVector2Array:
	var tip := -NODE_RADIUS if point_up else NODE_RADIUS
	var base := NODE_RADIUS if point_up else -NODE_RADIUS
	return PackedVector2Array([
		center + Vector2(0.0, tip),
		center + Vector2(NODE_RADIUS, base),
		center + Vector2(-NODE_RADIUS, base),
	])


func _star(center: Vector2) -> PackedVector2Array:
	var points := PackedVector2Array()
	for index in range(10):
		var radius := NODE_RADIUS if index % 2 == 0 else NODE_RADIUS * STAR_INNER_RATIO
		var angle := -PI * 0.5 + index * PI / 5.0
		points.append(center + Vector2(cos(angle), sin(angle)) * radius)
	return points


# The handle appears only on the selected node, and only while it has a free output.
func _draw_output_handle() -> void:
	if selected_id == 0 or not graph.has_node(selected_id) or placement_hint:
		return
	if not graph.has_free_output(selected_id):
		return

	var handle := _node_position(selected_id) + Vector2(WorkspaceController.OUTPUT_HANDLE_OFFSET, 0.0)
	draw_circle(handle, HANDLE_RADIUS, LinePalette.TEXT)


func _draw_label(center: Vector2, text: String) -> void:
	draw_string(
		ThemeDB.fallback_font,
		center + Vector2(-80.0, NODE_RADIUS + 34.0),
		text,
		HORIZONTAL_ALIGNMENT_CENTER,
		160.0,
		LABEL_FONT_SIZE,
		LinePalette.TEXT
	)


# Queues show a fixed number of dots plus one fill badge, however large the queue is.
func _draw_waiting_queues() -> void:
	for node_id in simulation.get_waiting_node_ids():
		if not graph.has_node(node_id):
			continue

		var center := _node_position(node_id)
		var batches := mini(simulation.get_waiting(node_id).size(), VisualLimits.WAITING_DOTS_PER_NODE)
		for dot in range(maxi(batches, 1)):
			draw_circle(
				center + Vector2(NODE_RADIUS + 18.0 + dot * WAITING_DOT_SPACING, 0.0),
				UNIT_RADIUS * 0.7,
				LinePalette.UNIT
			)

		draw_string(
			ThemeDB.fallback_font,
			center + Vector2(-80.0, -NODE_RADIUS - 12.0),
			"Queue %s/%d" % [NumberFormat.compact(simulation.get_waiting_total(node_id)), LineBalance.BUFFER_CAPACITY],
			HORIZONTAL_ALIGNMENT_CENTER,
			160.0,
			BADGE_FONT_SIZE,
			LinePalette.PROCESSED_UNIT
		)


func _draw_particles() -> void:
	for particle in plan_particles():
		var glow: Color = particle["color"]
		glow.a = particle["glow"] * GLOW_HALO_ALPHA
		draw_circle(particle["position"], particle["radius"] * GLOW_HALO_SCALE, glow)

		# Faint trailing ghosts are purely visual: no state, no extra resources.
		for trail_index in range(int(particle["trail"])):
			var behind: float = particle["along"] - VisualLimits.TRAIL_OFFSET * float(trail_index + 1)
			if behind < 0.0:
				break
			var ghost_color: Color = particle["color"]
			ghost_color.a = VisualLimits.TRAIL_ALPHAS[trail_index]
			draw_circle(particle["from"].lerp(particle["to"], behind), particle["radius"] * 0.8, ghost_color)
		draw_circle(particle["position"], particle["radius"], particle["color"])
		if particle["badge"]:
			draw_string(
				ThemeDB.fallback_font,
				particle["position"] + Vector2(-60.0, -UNIT_RADIUS - 8.0),
				"×%s" % NumberFormat.compact(particle["quantity"]),
				HORIZONTAL_ALIGNMENT_CENTER,
				120.0,
				BADGE_FONT_SIZE,
				LinePalette.TEXT
			)


func _draw_flashes() -> void:
	for flash in _cell_flashes:
		var size := Vector2.ONE * (WorkspaceLayout.CELL_SIZE - 16.0)
		var center := layout.get_cell_center(flash.cell)
		draw_rect(Rect2(center - size * 0.5, size), _faded(LinePalette.INVALID, flash), false, 4.0)


func _draw_payouts() -> void:
	for payout in _payouts:
		if not graph.has_node(payout.output_id):
			continue

		var progress := clampf(payout.age / PAYOUT_DURATION, 0.0, 1.0)
		var eased := 1.0 - pow(1.0 - progress, 3.0)
		var origin := _node_position(payout.output_id) + Vector2(payout.lateral_offset, -NODE_RADIUS - 24.0)
		var rise := origin + Vector2(-100.0, -PAYOUT_RISE * eased)
		var color := ComplexityStyle.payout_color(payout.complexity)
		color.a = 1.0 - progress * progress
		var size := ComplexityStyle.payout_font_size(PAYOUT_FONT_SIZE, payout.complexity)
		var text := "+%s" % NumberFormat.money(payout.amount)

		if ComplexityStyle.shows_glow(payout.complexity):
			# A faint offset copy reads as a soft glow without a shader or extra objects.
			var halo := color
			halo.a = color.a * PAYOUT_GLOW_ALPHA
			draw_string(ThemeDB.fallback_font, rise + Vector2(2.0, 2.0), text, HORIZONTAL_ALIGNMENT_CENTER, 200.0, size, halo)

		draw_string(ThemeDB.fallback_font, rise, text, HORIZONTAL_ALIGNMENT_CENTER, 200.0, size, color)

		if ComplexityStyle.shows_tier_name(payout.complexity):
			var name_color := ComplexityStyle.color(payout.complexity)
			name_color.a = color.a
			draw_string(
				ThemeDB.fallback_font,
				rise + Vector2(0.0, PAYOUT_NAME_OFFSET),
				ComplexityStyle.tier_name(payout.complexity),
				HORIZONTAL_ALIGNMENT_CENTER,
				200.0,
				BADGE_FONT_SIZE,
				name_color
			)


func _faded(color: Color, flash: Flash) -> Color:
	var faded := color
	faded.a = 1.0 - flash.age / FLASH_DURATION
	return faded
