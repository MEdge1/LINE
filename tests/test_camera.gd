extends SceneTree

# Run with: godot --headless --path . --script res://tests/test_camera.gd

const VIEWPORT := Vector2(720.0, 1280.0)
# Usable band: below the header (y 140), above the inspector's top edge (y 840).
const BAND := Rect2(0.0, 140.0, 720.0, 700.0)
const TOLERANCE := 0.001

var _failures := 0


func _init() -> void:
	_test_fully_visible_node_causes_no_movement()
	_test_obscured_node_moves_only_as_far_as_needed()
	_test_correction_respects_zoom()
	_test_correction_is_animated_with_ease_out()
	_test_repeated_selection_does_not_drift()
	_test_upward_navigation_does_not_recentre()
	_test_pan_cancels_a_correction_in_progress()
	_test_pinch_zoom_cancels_and_still_zooms()
	_test_too_small_band_reveals_the_node_centre()

	if _failures == 0:
		print("All camera tests passed.")
	else:
		printerr("%d camera assertion(s) failed." % _failures)

	quit(1 if _failures > 0 else 0)


func _assert_equal(actual: Variant, expected: Variant, message: String) -> void:
	if actual != expected:
		_failures += 1
		printerr("FAIL: %s (expected %s, got %s)" % [message, expected, actual])


func _assert_near(actual: float, expected: float, message: String) -> void:
	_assert_equal(absf(actual - expected) < TOLERANCE, true, "%s (expected %.3f, got %.3f)" % [message, expected, actual])


func _camera() -> WorkspaceCamera:
	var camera := WorkspaceCamera.new()
	camera.setup(VIEWPORT, WorkspaceLayout.get_half_extent())
	return camera


# Places a world point so that it appears at `screen` for the camera's current zoom and offset.
func _world_at_screen(camera: WorkspaceCamera, screen: Vector2) -> Vector2:
	return camera.screen_to_world(screen)


func _settle(camera: WorkspaceCamera) -> void:
	for _i in range(30):
		camera.advance(1.0 / 60.0)


func _test_fully_visible_node_causes_no_movement() -> void:
	var camera := _camera()
	var before := camera.offset
	camera.reveal_node(_world_at_screen(camera, Vector2(360.0, 500.0)), BAND)
	_assert_equal(camera.offset, before, "selecting a fully visible node leaves the camera exactly where it was")
	_assert_equal(camera.is_revealing(), false, "a visible node starts no correction")


func _test_obscured_node_moves_only_as_far_as_needed() -> void:
	var camera := _camera()
	var before := camera.offset
	# The node's bottom edge sits at 854, below the inspector top (840). Its margin needs it at 816 or higher.
	var node_screen := Vector2(360.0, 800.0)
	camera.reveal_node(_world_at_screen(camera, node_screen), BAND)
	_settle(camera)

	var expected_shift := (BAND.end.y - 24.0 - WorkspaceCamera.REVEAL_NODE_RADIUS * camera.zoom) - node_screen.y
	_assert_near(camera.offset.y - before.y, expected_shift, "an obscured node moves up by exactly the displacement needed")
	_assert_near(camera.offset.x, before.x, "a node that is already horizontally visible does not move sideways")


func _test_correction_respects_zoom() -> void:
	var small := _camera()
	small.zoom = 0.6
	var large := _camera()
	large.zoom = 1.6
	var node_screen := Vector2(360.0, 800.0)
	var small_before := small.offset
	var large_before := large.offset
	small.reveal_node(_world_at_screen(small, node_screen), BAND)
	large.reveal_node(_world_at_screen(large, node_screen), BAND)
	_settle(small)
	_settle(large)

	var small_expected := (BAND.end.y - 24.0 - WorkspaceCamera.REVEAL_NODE_RADIUS * 0.6) - node_screen.y
	var large_expected := (BAND.end.y - 24.0 - WorkspaceCamera.REVEAL_NODE_RADIUS * 1.6) - node_screen.y
	_assert_near(small.offset.y - small_before.y, small_expected, "at low zoom the correction uses the on-screen radius")
	_assert_near(large.offset.y - large_before.y, large_expected, "at high zoom the correction uses the on-screen radius")


func _test_correction_is_animated_with_ease_out() -> void:
	var camera := _camera()
	var from := camera.offset
	camera.reveal_node(_world_at_screen(camera, Vector2(360.0, 800.0)), BAND)
	# The node needs to move up 38 px to clear the inspector with its margin.
	var target_y := from.y - 38.0

	camera.advance(WorkspaceCamera.REVEAL_SECONDS * 0.5)
	var midway := camera.offset.y
	_assert_equal(camera.is_revealing(), true, "a correction is still running halfway through its time")
	_assert_equal(midway < from.y and midway > target_y, true, "the midway position lies between start and target")

	camera.advance(WorkspaceCamera.REVEAL_SECONDS)
	_assert_equal(camera.is_revealing(), false, "the correction finishes within its set duration")
	_assert_near(camera.offset.y, target_y, "the correction ends exactly at its target")

	# Ease-out: the first half of the time covers more than half of the distance.
	var halfway_camera := _camera()
	var start_y := halfway_camera.offset.y
	halfway_camera.reveal_node(_world_at_screen(halfway_camera, Vector2(360.0, 800.0)), BAND)
	halfway_camera.advance(WorkspaceCamera.REVEAL_SECONDS * 0.5)
	var covered := (halfway_camera.offset.y - start_y) / -38.0
	_assert_equal(covered > 0.5, true, "the motion eases out, covering most of the distance early")


func _test_repeated_selection_does_not_drift() -> void:
	var camera := _camera()
	var node_world := _world_at_screen(camera, Vector2(360.0, 800.0))
	camera.reveal_node(node_world, BAND)
	_settle(camera)
	var settled := camera.offset
	for _i in range(5):
		camera.reveal_node(node_world, BAND)
		_settle(camera)
	_assert_equal(camera.offset, settled, "re-selecting a node that is now visible does not move the camera again")


func _test_upward_navigation_does_not_recentre() -> void:
	var camera := _camera()
	var before := camera.offset
	# Walking up the grid through visible nodes: each selection is comfortably on screen.
	for screen_y in [700.0, 600.0, 500.0, 400.0, 300.0]:
		camera.reveal_node(_world_at_screen(camera, Vector2(360.0, screen_y)), BAND)
		_settle(camera)
	_assert_equal(camera.offset, before, "selecting visible nodes upward never recentres the view")


func _test_pan_cancels_a_correction_in_progress() -> void:
	var camera := _camera()
	camera.reveal_node(_world_at_screen(camera, Vector2(360.0, 800.0)), BAND)
	camera.advance(WorkspaceCamera.REVEAL_SECONDS * 0.3)
	var stopped := camera.offset

	camera.pan(Vector2(12.0, -4.0))
	_assert_equal(camera.is_revealing(), false, "a deliberate pan stops the automatic correction")
	var after_pan := camera.offset
	_assert_equal(after_pan, stopped + Vector2(12.0, -4.0), "the pan applies to where the player was looking")

	camera.advance(WorkspaceCamera.REVEAL_SECONDS)
	_assert_equal(camera.offset, after_pan, "the cancelled correction never moves the camera again")


func _test_pinch_zoom_cancels_and_still_zooms() -> void:
	var camera := _camera()
	camera.reveal_node(_world_at_screen(camera, Vector2(360.0, 800.0)), BAND)
	camera.advance(WorkspaceCamera.REVEAL_SECONDS * 0.3)
	var zoom_before := camera.zoom

	camera.zoom_at(Vector2(360.0, 500.0), 1.2)
	_assert_equal(camera.is_revealing(), false, "a pinch zoom takes control from the correction")
	_assert_equal(camera.zoom > zoom_before, true, "pinch zoom still changes the zoom level")


func _test_too_small_band_reveals_the_node_centre() -> void:
	var tiny := Rect2(0.0, 0.0, 720.0, 60.0)
	var shift := WorkspaceCamera.reveal_delta(Vector2(360.0, 400.0), 60.0, tiny, 24.0)
	_assert_near(shift.y, 30.0 - 400.0, "a band too small for the node centres the node in it")
	_assert_equal(WorkspaceCamera.reveal_delta(Vector2(360.0, 15.0), 10.0, BAND, 24.0) == Vector2.ZERO, false,
		"a node outside the band is always corrected")
