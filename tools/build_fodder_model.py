"""Rebuild the single skinned fodder mesh from the project's CC0 Quaternius parts.

Run from the project root: blender -b -t 1 --python-exit-code 1 --python tools/build_fodder_model.py
The source models/textures are read-only. The atlas is temporary and embedded in the GLB.
"""
import os
import tempfile
from pathlib import Path
import bpy
import bmesh
import numpy as np

PROJECT = Path(__file__).resolve().parent.parent
ROOT = str(PROJECT / 'assets/quaternius/characters')
OUT = str(PROJECT / 'assets/quaternius/characters/base')
TEMP = tempfile.TemporaryDirectory(prefix='thor-fodder-atlas-')
TILE, PAD = 256, 4
CELL = TILE + PAD * 2
ATLAS_W, ATLAS_H = 4 * CELL, 2 * CELL

bpy.ops.object.select_all(action='SELECT')
bpy.ops.object.delete(use_global=False)

def import_objects(path):
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=path)
    return [o for o in bpy.data.objects if o not in before]

base = import_objects(os.path.join(ROOT, 'base/Superhero_Male_FullBody.gltf'))
body_armature = next(o for o in base if o.type == 'ARMATURE')
base_meshes = [o for o in base if o.type == 'MESH' and o.parent == body_armature]
assert len(base_meshes) == 3, [o.name for o in base_meshes]
outfit = import_objects(os.path.join(ROOT, 'outfits/Male_Peasant.gltf'))
armature = next(o for o in outfit if o.type == 'ARMATURE')
clothes = [o for o in outfit if o.type == 'MESH' and o.parent == armature]
assert len(clothes) == 4, [o.name for o in clothes]

# The outfit and head/neck have equal bind poses. Remove the original body's
# triangles below the same 83% height cutoff as HumanoidModel._head_only. Also
# remove any surviving arm-weighted triangle: those joints have different bind
# poses in the two source rigs and are already covered by the outfit.
head = next(o for o in base_meshes if o.name.startswith('SuperHero_Male'))
arm_groups = {g.index for g in head.vertex_groups if any(
    t in g.name for t in ('clavicle_', 'upperarm_', 'lowerarm_', 'hand_',
                           'index_', 'middle_', 'pinky_', 'ring_', 'thumb_'))}
arm_vertices = {v.index for v in head.data.vertices if any(g.group in arm_groups and g.weight > 0.001 for g in v.groups)}
ymax = max(v.co.z for v in head.data.vertices)
cut = ymax * 0.83
bm = bmesh.new()
bm.from_mesh(head.data)
bm.verts.ensure_lookup_table()
bad = [f for f in bm.faces if any(v.co.z < cut or v.index in arm_vertices for v in f.verts)]
bmesh.ops.delete(bm, geom=bad, context='FACES')
bm.to_mesh(head.data)
bm.free()
assert len(head.data.polygons) > 100, 'head cut removed too much geometry'

for obj in base_meshes:
    matrix = obj.matrix_world.copy()
    obj.parent = armature
    obj.matrix_world = matrix
    for modifier in obj.modifiers:
        if modifier.type == 'ARMATURE':
            modifier.object = armature
bpy.data.objects.remove(body_armature, do_unlink=True)
armature.name = 'Armature'  # UAL tracks target Armature/Skeleton3D.

meshes = base_meshes + clothes
materials = {}
for obj in meshes:
    for mat in obj.data.materials:
        if mat:
            materials[mat.name.split('.')[0]] = mat

# One repeated eye tile keeps the original U > 1 UVs continuous.
specs = {
    'MI_Superhero_Male': (0, 0, (0.5, 0.6, 0.62), False),
    'MI_Hair_1': (1, 0, (0.5, 0.6, 0.62), False),
    'MI_Regular_Male': (2, 0, (0.5, 0.6, 0.62), False),
    'MI_Peasant': (3, 0, (0.42, 0.4, 0.36), False),
    'MI_Eyes': (0, 1, (0.5, 0.6, 0.62), True),
}
assert set(specs) <= set(materials), (set(specs) - set(materials))
atlas = np.ones((ATLAS_H, ATLAS_W, 4), dtype=np.float32)
for name, (col, row, tint, repeat_u) in specs.items():
    mat = materials[name]
    images = [n.image for n in mat.node_tree.nodes if n.type == 'TEX_IMAGE' and n.image]
    assert images, name
    image = images[0].copy()
    image.scale(TILE, TILE)
    pixels = np.empty(TILE * TILE * 4, dtype=np.float32)
    image.pixels.foreach_get(pixels)
    pixels = pixels.reshape((TILE, TILE, 4))
    pixels[:, :, :3] *= np.asarray(tint, dtype=np.float32)
    pixels[:, :, 3] = 1.0
    width = 2 * TILE if repeat_u else TILE
    repeated = np.concatenate([pixels, pixels], axis=1) if repeat_u else pixels
    # Wrapped gutters preserve filtering at edges without bleeding adjacent materials.
    padded = np.pad(repeated, ((PAD, PAD), (PAD, PAD), (0, 0)), mode='wrap')
    x, y = col * CELL, row * CELL
    atlas[y:y + TILE + 2 * PAD, x:x + width + 2 * PAD] = padded
    bpy.data.images.remove(image)

atlas_img = bpy.data.images.new('Fodder_Midgard_Atlas', width=ATLAS_W, height=ATLAS_H, alpha=False)
atlas_img.pixels.foreach_set(atlas.reshape(-1))
atlas_img.filepath_raw = os.path.join(TEMP.name, 'fodder_atlas.png')
atlas_img.file_format = 'PNG'
atlas_img.save()
atlas_img.pack()

for obj in meshes:
    uv = obj.data.uv_layers.active
    assert uv, obj.name
    for poly in obj.data.polygons:
        material = obj.data.materials[poly.material_index]
        name = material.name.split('.')[0]
        col, row, _, repeat_u = specs[name]
        for li in poly.loop_indices:
            val = uv.data[li].uv
            assert -0.001 <= val.x <= (2.0 if repeat_u else 1.001) and -0.001 <= val.y <= 1.001, (name, tuple(val))
            val.x = (col * CELL + PAD + val.x * TILE) / ATLAS_W
            val.y = (row * CELL + PAD + val.y * TILE) / ATLAS_H
    # glTF exporter uses the first UV channel; the atlas is the only one needed.
    keep_uv_name = uv.name
    for layer_name in [layer.name for layer in obj.data.uv_layers if layer.name != keep_uv_name]:
        obj.data.uv_layers.remove(obj.data.uv_layers[layer_name])

bpy.ops.object.select_all(action='DESELECT')
for obj in meshes:
    obj.select_set(True)
bpy.context.view_layer.objects.active = clothes[0]
bpy.ops.object.join()
combined = bpy.context.view_layer.objects.active
combined.name = 'Fodder_Midgard'
combined.data.name = 'Fodder_Midgard_Mesh'
combined.parent = armature

mat = bpy.data.materials.new('Fodder_Midgard_Atlas')
mat.use_nodes = True
bsdf = mat.node_tree.nodes.get('Principled BSDF')
image_node = mat.node_tree.nodes.new('ShaderNodeTexImage')
image_node.image = atlas_img
mat.node_tree.links.new(image_node.outputs['Color'], bsdf.inputs['Base Color'])
bsdf.inputs['Roughness'].default_value = 0.85
combined.data.materials.clear()
combined.data.materials.append(mat)
for poly in combined.data.polygons:
    poly.material_index = 0

bpy.ops.object.select_all(action='DESELECT')
armature.select_set(True)
combined.select_set(True)
bpy.context.view_layer.objects.active = armature
output = os.path.join(OUT, 'Fodder_Midgard.glb')
bpy.ops.export_scene.gltf(filepath=output, export_format='GLB', use_selection=True,
                          export_animations=False, export_skins=True, export_yup=True)
print('COMBINED', output, 'vertices', len(combined.data.vertices), 'triangles', len(combined.data.polygons), 'materials', len(combined.data.materials))
TEMP.cleanup()
