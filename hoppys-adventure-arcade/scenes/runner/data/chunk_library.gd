extends Resource
## The pool the spawner draws from: every authored chunk scene under scenes/runner/chunks/,
## listed in chunk_library.tres. The spawner filters the pool by each chunk's difficulty band.

@export var scenes: Array[PackedScene] = []
