extends Node2D

## V4.10c. One of map_view's projected layers: a child drawn in LON/LAT and
## projected by its own transform, which map_view sets on every re-record. A pan
## or a zoom moves the transform; it re-records nothing here, which is the whole
## lever (map-platform-model §11: the roster's fills and lines were 57 of the
## 83 ms a drag at the opening fit cost, all of it re-recording content the
## camera cannot change). map_view queues a layer only when what it paints
## moves.
##
## The painting stays in map_view, which owns the state it reads; this node is
## the canvas item and the counter. `generation` counts re-records, so a test
## can tell "moved" from "re-recorded" -- the difference this block is about.

var painter: Callable
var generation := 0


func _draw() -> void:
	generation += 1
	if painter.is_valid():
		painter.call(self)
