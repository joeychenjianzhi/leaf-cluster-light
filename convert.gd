extends SceneTree
## Leaf Cluster Light. Standalone GLB 2.0 converter. MIT License.
const Light = preload("res://leaf_cluster_light.gd")
const JSON_CHUNK = 0x4e4f534a
const BIN_CHUNK = 0x004e4942
var doc: Dictionary
var data: PackedByteArray
var error = ""

func _initialize():
	var args = OS.get_cmdline_user_args()
	if args.size() < 1 or args.size() > 3:
		printerr("Usage: input.glb [mesh-name|auto] [auto|outward|inward|blade]")
		quit(2)
		return
	var path = args[0]
	if not path.is_absolute_path(): path = ProjectSettings.globalize_path("res://" + path)
	var mode = args[2] if args.size()>2 else "auto"
	if mode not in ["auto","outward","inward","blade"]: error = "Unknown normal mode."
	var target = path.get_basename() + "-relit.glb"
	if FileAccess.file_exists(target): error = "Output already exists: " + target
	if error.is_empty(): read_glb(path)
	if error.is_empty(): convert_meshes(args[1] if args.size()>1 else "auto",mode)
	if error.is_empty(): write_glb(target)
	if not error.is_empty(): printerr(error); quit(1); return
	print("Wrote ",target)
	quit()

func read_glb(path:String):
	var blob = FileAccess.get_file_as_bytes(path)
	if blob.size()<28 or blob.decode_u32(0)!=0x46546c67 or blob.decode_u32(4)!=2 or blob.decode_u32(8)!=blob.size():
		error="Expected a GLB 2.0 file.";return
	var length_=blob.decode_u32(12)
	var next=20+length_
	if next+8>blob.size() or blob.decode_u32(16)!=JSON_CHUNK or blob.decode_u32(next+4)!=BIN_CHUNK or next+8+blob.decode_u32(next)!=blob.size():
		error="Expected exactly one JSON chunk and one embedded BIN chunk.";return
	var parsed=JSON.parse_string(blob.slice(20,next).get_string_from_utf8())
	if not parsed is Dictionary or not parsed.has_all(["buffers","bufferViews","accessors","meshes"]):
		error="Missing glTF mesh tables.";return
	doc=parsed
	if doc.buffers.size()!=1 or doc.buffers[0].has("uri"):error="Only embedded single-buffer GLB is supported.";return
	data=blob.slice(next+8)
	if int(doc.buffers[0].byteLength)>data.size():error="Truncated buffer."

func accessor(id:int, components:int, allowed:Array)->Dictionary:
	if id<0 or id>=doc.accessors.size():error="Invalid accessor index.";return {}
	var a=doc.accessors[id]
	if a.get("type")!=("VEC3" if components==3 else "SCALAR") or int(a.get("componentType",0)) not in allowed or a.has("sparse") or not a.has("bufferView"):
		error="Expected dense FLOAT VEC3 attributes or unsigned triangle indices.";return {}
	var vi=int(a.bufferView)
	if vi<0 or vi>=doc.bufferViews.size():error="Invalid buffer view.";return {}
	var v=doc.bufferViews[vi]
	if v.has("extensions") or int(v.get("buffer",-1))!=0:error="Compressed/external views are unsupported.";return {}
	var t=int(a.componentType)
	var bytes=1 if t==5121 else (2 if t==5123 else 4)
	var stride=int(v.get("byteStride",components*bytes))
	var base=int(v.get("byteOffset",0))
	var offset=int(a.get("byteOffset",0))
	var count=int(a.get("count",0))
	var size=int(v.get("byteLength",0))
	if count<=0 or base<0 or offset<0 or stride<components*bytes or offset+(count-1)*stride+components*bytes>size or base+size>data.size():
		error="Invalid accessor range.";return {}
	return {"start":base+offset,"count":count,"stride":stride,"type":t}

func vectors(id:int)->PackedVector3Array:
	var result=PackedVector3Array()
	var a=accessor(id,3,[5126])
	if a.is_empty():return result
	result.resize(a.count)
	for i in a.count:
		var p=a.start+i*a.stride
		result[i]=Vector3(data.decode_float(p),data.decode_float(p+4),data.decode_float(p+8))
		if not result[i].is_finite():error="Non-finite vertex attribute.";return PackedVector3Array()
	return result

func leader(parent:PackedInt32Array, i:int)->int:
	while parent[i]!=i:
		parent[i]=parent[parent[i]]
		i=parent[i]
	return i

func relight(primitive:Dictionary, mode:String):
	if int(primitive.get("mode",4))!=4 or primitive.has("extensions") or primitive.has("targets"):
		error="Use uncompressed triangle foliage without morph targets.";return
	var attr=primitive.get("attributes",{})
	var points=vectors(int(attr.get("POSITION",-1)))
	var previous=vectors(int(attr.get("NORMAL",-1)))
	if not error.is_empty():return
	if points.size()!=previous.size():error="POSITION and NORMAL counts differ.";return
	var parent=PackedInt32Array()
	var welded={}
	parent.resize(points.size())
	for i in points.size():
		var key=points[i].snapped(Vector3.ONE*.000001)
		parent[i]=welded.get(key,i)
		welded[key]=parent[i]
	var idx={}
	if primitive.has("indices"):
		idx=accessor(int(primitive.indices),1,[5121,5123,5125])
		if idx.is_empty():return
	var count=int(idx.get("count",points.size()))
	if count%3!=0:error="Incomplete triangles.";return
	var first=0
	for i in count:
		var k=i
		if not idx.is_empty():
			var off=idx.start+i*idx.stride
			k=data.decode_u8(off) if idx.type==5121 else (data.decode_u16(off) if idx.type==5123 else data.decode_u32(off))
		if k>=points.size():error="Out-of-range triangle index.";return
		if i%3==0:first=k
		else:parent[leader(parent,k)]=leader(parent,first)
	var groups=PackedInt32Array()
	var ids={}
	var boxes:Array[AABB]=[]
	for i in points.size():
		var root_id=leader(parent,i)
		if not ids.has(root_id):
			ids[root_id]=ids.size()
			boxes.append(AABB(points[i],Vector3.ZERO))
		var g:int=ids[root_id]
		groups.append(g)
		boxes[g]=boxes[g].expand(points[i])
	if mode=="auto":
		var score=0.0
		for i in points.size():score+=previous[i].dot((points[i]-boxes[groups[i]].get_center()).normalized())
		score/=points.size()
		mode="blade" if absf(score)<.25 else ("inward" if score<0 else "outward")
	var normals=Light.normals(points,previous,groups,mode)
	# A fresh accessor also works when the input normal stream is shared by
	# an untouched mesh, or interleaved with positions and texture coordinates.
	while data.size()%4!=0:data.append(0)
	var start=data.size()
	var stream=normals.to_byte_array()
	data.append_array(stream)
	doc.bufferViews.append({"buffer":0,"byteOffset":start,"byteLength":stream.size(),"target":34962})
	doc.accessors.append({"bufferView":doc.bufferViews.size()-1,"componentType":5126,"count":points.size(),"type":"VEC3"})
	attr.NORMAL=doc.accessors.size()-1
	print("  ",ids.size()," connected organs, ",points.size()," normals, ",mode)

func convert_meshes(selector:String,mode:String):
	var matches=0
	var names=PackedStringArray()
	for mesh in doc.meshes:
		var label=str(mesh.get("name",""))
		names.append(label)
		var auto=false
		for prefix in ["crown","foliage","leaves","leaf"]:
			if label.to_lower().begins_with(prefix):auto=true
		if not (auto if selector=="auto" else label==selector):continue
		matches+=1
		print(label)
		for primitive in mesh.primitives:
			relight(primitive,mode)
			if not error.is_empty():return
	if matches==0:error="No matching foliage mesh. Available: "+", ".join(names)
	doc.buffers[0].byteLength=data.size()

func write_glb(target:String):
	var header=JSON.stringify(doc,"",false,true).to_utf8_buffer()
	while header.size()%4!=0:header.append(32)
	while data.size()%4!=0:data.append(0)
	var file=FileAccess.open(target,FileAccess.WRITE)
	if not file:error="Cannot write output.";return
	for value in [0x46546c67,2,28+header.size()+data.size(),header.size(),JSON_CHUNK]:file.store_32(value)
	file.store_buffer(header)
	file.store_32(data.size());file.store_32(BIN_CHUNK);file.store_buffer(data)
	file.flush()
	if file.get_error()!=OK:error="Output write failed."
