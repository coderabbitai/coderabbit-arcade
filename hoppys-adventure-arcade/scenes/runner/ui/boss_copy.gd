extends RefCounted
## The only narrative copy table. Tool eligibility is always read from BossDefs.
const BossDefs = preload("res://scenes/runner/boss/boss_defs.gd")
const ToolDefs = preload("res://scenes/runner/powerups/tool_defs.gd")
const COPY := {
	&"flaky_test_swarm": {"epithet": "The Nondeterministic Horde", "threat": "Passed locally. Fails on CI.", "path": "tests/ci/pipeline.spec:42", "hint": "WAIT FOR THE FLICKER TO COMMIT"},
	&"merge_conflict_hydra": {"epithet": "Three Branches, Zero Agreement", "threat": "<<<<<<< HEAD: cut one, two more rebase.", "path": "src/branches/merge.ts:128"},
	&"legacy_monolith": {"epithet": "@deprecated Since 2011", "threat": "Still in production. Still load-bearing.", "path": "legacy/core/production.ts:2011"},
}

## cycle is human-facing: first lap = 1, second lap = 2.
static func epithet(kind: StringName, cycle: int = 1) -> String:
	var text := String(COPY.get(kind, {}).get("epithet", "Unresolved issue"))
	return text + (" · REGRESSED v%d" % cycle if cycle >= 2 else "")

static func threat(kind: StringName) -> String:
	return String(COPY.get(kind, {}).get("threat", "Review required."))

static func source_path(kind: StringName) -> String:
	return String(COPY.get(kind, {}).get("path", "src/unknown:1"))

## One row per phase, using the resolved accepted_tools list from BossDefs.
static func hint_rows(def: Dictionary) -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	var count := int(def.get("phase_count", BossDefs.PHASE_COUNT))
	for phase in range(1, count + 1):
		var accepted := BossDefs.accepted_tools(def, phase)
		var tools: Array = Array(accepted)
		var all_tools := tools.size() == ToolDefs.kinds().size()
		var names := PackedStringArray()
		for tool: StringName in tools: names.append(ToolDefs.label(tool).to_upper())
		var hint := String(COPY.get(StringName(def.get("kind", &"")), {}).get("hint", ""))
		var text := (hint + " · " if not hint.is_empty() else "") + "EVERY TOOL LANDS" if all_tools else " + ".join(names)
		rows.append({"phase": phase, "accepted_tools": accepted.duplicate(), "tools": tools,
			"all_tools": all_tools, "hint": hint, "text": text})
	return rows
