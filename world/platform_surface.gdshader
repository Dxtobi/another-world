shader_type canvas_item;
// Dry platform surface (rock / ground / moss / snow / sand).
//
// The implementation lives in platform_surface_impl.gdshaderinc so the water
// wrapper can share it. This wrapper deliberately does NOT define
// ENABLE_REFLECTIONS: dry surfaces must not declare or sample the screen
// texture, because doing so makes Godot take a backbuffer copy for every
// rock and ground piece -- and an early copy is also what gave the lake a
// stale, pre-forest backbuffer. Only platform_water.gdshader opts in.
//
// NOTE: .gdshader accepts // comments only.

#include "res://world/platform_surface_impl.gdshaderinc"
