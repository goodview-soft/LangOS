class_name NN
extends RefCounted
## Mini réseau (MLP, 1 couche cachée tanh) pour choisir le but de vie d'une IA. Quelques µs par décision, sans GPU.

var n_in := 0
var n_hid := 0
var n_out := 0
var w: PackedFloat32Array  # W1 (hid*in) | b1 (hid) | W2 (out*hid) | b2 (out)

static func size_for(i: int, h: int, o: int) -> int:
	return h * i + h + o * h + o

func _init(i := 11, h := 12, o := 5) -> void:
	n_in = i; n_hid = h; n_out = o
	w = PackedFloat32Array(); w.resize(size_for(i, h, o))

func randomize_w(rng: RandomNumberGenerator, s := 0.5) -> void:
	for k in w.size():
		w[k] = rng.randfn(0.0, s)

## Renvoie les scores de sortie (un par but).
func forward(x: Array) -> Array:
	var hid := []
	var o1 := n_hid * n_in
	var b1 := o1
	var o2 := b1 + n_hid
	var b2 := o2 + n_out * n_hid
	for h in n_hid:
		var s: float = w[b1 + h]
		for i in n_in:
			s += w[h * n_in + i] * float(x[i])
		hid.append(tanh(s))
	var out := []
	for o in n_out:
		var s: float = w[b2 + o]
		for h in n_hid:
			s += w[o2 + o * n_hid + h] * hid[h]
		out.append(s)
	return out

func argmax(x: Array) -> int:
	var o := forward(x)
	var best := 0
	for i in o.size():
		if o[i] > o[best]:
			best = i
	return best

func save(path: String) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(JSON.stringify({"i": n_in, "h": n_hid, "o": n_out, "w": Array(w)}))

static func load_file(path: String) -> NN:
	if not FileAccess.file_exists(path):
		return null
	var d = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(d) != TYPE_DICTIONARY:
		return null
	var n := NN.new(int(d.i), int(d.h), int(d.o))
	n.w = PackedFloat32Array(d.w)
	return n
