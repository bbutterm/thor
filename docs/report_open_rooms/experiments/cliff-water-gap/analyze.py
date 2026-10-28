#!/usr/bin/env python3
"""Статическая оценка исходных мешей и луча к Cliff1; Godot не запускается.

Счётчик треугольников не равен RENDER_TOTAL_PRIMITIVES_IN_FRAME. Луч проверяет
только перечисленные непрозрачные поверхности и два фоновых меша; полная сцена,
LOD, клиппинг, пиксели и перекрытия другими объектами здесь не моделируются.
"""
from base64 import b64decode
from collections import Counter, defaultdict
from itertools import product
from pathlib import Path
import json
import math
import re
import struct

ROOT = Path(__file__).resolve().parents[4]
CAMERA = (0.0, 1.7, 0.0)
PIRATE = ROOT / "assets/quaternius/pirate"


def sections(path):
    return re.split(r"(?=^\[(?:sub_resource|node)\b)", path.read_text(), flags=re.M)


def mesh_counts(path):
    parts = sections(path)
    meshes = {}
    for block in parts:
        match = re.match(r'\[sub_resource type="ArrayMesh" id="([^"]+)"\]', block)
        if not match:
            continue
        index_counts = re.findall(r'^"index_count": (\d+),?$', block, re.M)
        vertex_counts = re.findall(r'^"vertex_count": (\d+),?$', block, re.M)
        if len(vertex_counts) == 1:
            meshes[match.group(1)] = int(index_counts[0] if index_counts else vertex_counts[0]) // 3
    result = defaultdict(lambda: [0, 0, 0])
    transforms = {}
    instances = Counter()
    for block in parts:
        name = re.match(r'\[node name="([^"]+)" type="MultiMeshInstance3D"[^\n]*\]', block)
        if not name:
            continue
        mesh = re.search(r'^mesh = SubResource\("([^"]+)"\)', block, re.M)
        values = re.search(r'^xforms = PackedFloat32Array\(([^\n]*)\)', block, re.M)
        if not mesh or not values or mesh.group(1) not in meshes:
            raise ValueError(f"cannot decode {name.group(1)} in {path}")
        values = list(map(float, values.group(1).split(",")))
        if len(values) % 12:
            raise ValueError(f"invalid transform buffer for {name.group(1)}")
        matrices = [values[i : i + 12] for i in range(0, len(values), 12)]
        transforms[name.group(1)] = matrices
        material = re.search(r'^material_override = (.+)$', block, re.M)
        for matrix in matrices:
            instances[(mesh.group(1), material.group(1) if material else None, tuple(matrix))] += 1
        category = re.sub(r"_[-\d]+_[-\d]+$", "", name.group(1))
        result[category][0] += 1
        result[category][1] += len(matrices)
        result[category][2] += len(matrices) * meshes[mesh.group(1)]
    duplicates = sum(count - 1 for count in instances.values() if count > 1)
    return result, transforms, duplicates


def read_mesh(name):
    doc = json.loads((PIRATE / f"{name}.gltf").read_text())
    if any(any(key in node for key in ("translation", "rotation", "scale", "matrix")) for node in doc["nodes"]):
        raise ValueError(f"unexpected node transform in {name}")
    raw = b64decode(doc["buffers"][0]["uri"].split(",", 1)[1])
    primitive = doc["meshes"][0]["primitives"][0]

    def read(index):
        accessor = doc["accessors"][index]
        view = doc["bufferViews"][accessor["bufferView"]]
        offset = view.get("byteOffset", 0) + accessor.get("byteOffset", 0)
        kind = {5121: "B", 5123: "H", 5125: "I", 5126: "f"}[accessor["componentType"]]
        size = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4}[accessor["type"]]
        stride = view.get("byteStride", struct.calcsize(kind) * size)
        return [struct.unpack_from("<" + kind * size, raw, offset + i * stride) for i in range(accessor["count"])]

    positions = read(primitive["attributes"]["POSITION"])
    normals = read(primitive["attributes"]["NORMAL"])
    uvs = read(primitive["attributes"]["TEXCOORD_0"])
    indexes = [value[0] for value in read(primitive["indices"])]
    return positions, normals, uvs, list(zip(indexes[::3], indexes[1::3], indexes[2::3]))


def add(a, b):
    return tuple(x + y for x, y in zip(a, b))


def sub(a, b):
    return tuple(x - y for x, y in zip(a, b))


def cross(a, b):
    return (a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0])


def dot(a, b):
    return sum(x * y for x, y in zip(a, b))


def point(t, v):
    x, y, z = v
    return (t[0] * x + t[1] * y + t[2] * z + t[3],
            t[4] * x + t[5] * y + t[6] * z + t[7],
            t[8] * x + t[9] * y + t[10] * z + t[11])


def multi_aabb_hits(path, target):
    parts = sections(path)
    bounds = {}
    for block in parts:
        mesh = re.match(r'\[sub_resource type="ArrayMesh" id="([^"]+)"\]', block)
        aabb = re.search(r'^"aabb": AABB\(([^\n]+)\)', block, re.M)
        if mesh and aabb:
            bounds[mesh.group(1)] = list(map(float, aabb.group(1).split(",")))
    direction = sub(target, CAMERA)
    hits = []
    for block in parts:
        name = re.match(r'\[node name="([^"]+)" type="MultiMeshInstance3D"[^\n]*\]', block)
        if not name or name.group(1).startswith("Cliff1_0_2"):
            continue
        mesh = re.search(r'^mesh = SubResource\("([^"]+)"\)', block, re.M)
        values = re.search(r'^xforms = PackedFloat32Array\(([^\n]*)\)', block, re.M)
        if not mesh or not values or mesh.group(1) not in bounds or re.search(r'^transform = ', block, re.M):
            raise ValueError(f"unexpected mesh or node transform for {name.group(1)}")
        aabb = bounds[mesh.group(1)]
        low = aabb[:3]
        high = [aabb[i] + aabb[i + 3] for i in range(3)]
        numbers = list(map(float, values.group(1).split(",")))
        for offset in range(0, len(numbers), 12):
            transform = numbers[offset : offset + 12]
            corners = [point(transform, xyz) for xyz in product(*[(low[i], high[i]) for i in range(3)])]
            box = [(min(corner[i] for corner in corners), max(corner[i] for corner in corners)) for i in range(3)]
            near, far = 0.0, 1.0
            for origin, vector, (lower, upper) in zip(CAMERA, direction, box):
                if abs(vector) < 1e-12:
                    if not lower <= origin <= upper:
                        near, far = 1.0, 0.0
                        break
                else:
                    a, b = (lower - origin) / vector, (upper - origin) / vector
                    near, far = max(near, min(a, b)), min(far, max(a, b))
                    if near > far:
                        break
            if near <= far:
                hits.append((name.group(1), offset // 12))
    return hits


def ray_hit(a, b, c, target, cull_back=False):
    direction = sub(target, CAMERA)
    e1, e2 = sub(b, a), sub(c, a)
    q = cross(direction, e2)
    det = dot(e1, q)
    if (cull_back and det <= 1e-8) or (not cull_back and abs(det) < 1e-8):
        return False
    inv = 1.0 / det
    source = sub(CAMERA, a)
    u = inv * dot(source, q)
    if not 0.0 <= u <= 1.0:
        return False
    q2 = cross(source, e1)
    v = inv * dot(direction, q2)
    if v < 0.0 or u + v > 1.0:
        return False
    distance = inv * dot(e2, q2)
    return 0.0 < distance < 1.0 - 1e-5


def ring_factor(x, z):
    angle = math.atan2(z, x) % (2.0 * math.pi)
    sector = 2.0 * math.pi / 40.0
    mid = (math.floor(angle / sector) + 0.5) * sector
    return math.cos(math.pi / 40.0) / math.cos(angle - mid)


def under_and_gap(tri):
    if not all(v[1] < -1.10001 for v in tri):
        return False, None
    center = tuple(sum(v[i] for v in tri) / 3.0 for i in range(3))
    radius = math.hypot(center[0], center[2])
    factor = ring_factor(center[0], center[2])
    water_cross = radius * (CAMERA[1] + 1.1) / (CAMERA[1] - center[1])
    ground_outer = 78.0 * factor
    ray_at_outer = CAMERA[1] + (center[1] - CAMERA[1]) * ground_outer / radius
    if water_cross < 70.0 * factor and ray_at_outer > -1.5:
        return True, (center, water_cross, 70.0 * factor, ground_outer, ray_at_outer)
    return True, None


def pine_triangles():
    result = []

    def band(y0, y1, r0, r1, n):
        for i in range(n):
            a, b = 2 * math.pi * i / n, 2 * math.pi * (i + 1) / n
            p = [(math.cos(a) * r0, y0, math.sin(a) * r0), (math.cos(b) * r0, y0, math.sin(b) * r0),
                 (math.cos(b) * r1, y1, math.sin(b) * r1), (math.cos(a) * r1, y1, math.sin(a) * r1)]
            result.extend(((p[0], p[1], p[2]), (p[0], p[2], p[3])))

    def disc(y, radius, n):
        for i in range(n):
            a, b = 2 * math.pi * i / n, 2 * math.pi * (i + 1) / n
            result.append(((0, y, 0), (math.cos(a) * radius, y, math.sin(a) * radius),
                           (math.cos(b) * radius, y, math.sin(b) * radius)))

    band(0, 2.2, 0.28, 0.2, 6)
    for y0, y1, radius in ((1.4, 4.6, 2.6), (3.6, 6.6, 2.1), (5.6, 8.4, 1.6), (7.4, 10.0, 1.05)):
        band(y0, y1, radius, 0.02, 9)
        disc(y0, radius, 9)
    return result


def main():
    print("Nominal mesh triangles (no frustum/LOD/pass accounting):")
    backdrop, transforms, backdrop_duplicates = mesh_counts(ROOT / "rooms/backdrop_midgard.tscn")
    room, _, room_duplicates = mesh_counts(ROOT / "rooms/room_01.tscn")
    for label, counts, duplicates in (("backdrop", backdrop, backdrop_duplicates), ("room_scatter", room, room_duplicates)):
        print(label, "groups", sum(v[0] for v in counts.values()), "instances", sum(v[1] for v in counts.values()),
              "triangles", sum(v[2] for v in counts.values()), "exact_duplicate_instances", duplicates)
        for name, stats in sorted(counts.items(), key=lambda item: -item[1][2]):
            print(" ", name, "groups/instances/triangles", *stats)

    print("Source duplicate / exact-degenerate check:")
    for name in ("Environment_Cliff1", *(f"Environment_Rock_{i}" for i in range(1, 6))):
        pos, normal, uv, tris = read_mesh(name)
        unique = Counter()
        degenerate = 0
        for indexes in tris:
            coords = [pos[i] for i in indexes]
            degenerate += len(set(coords)) < 3
            vertices = [(pos[i], normal[i], uv[i]) for i in indexes]
            key = min(tuple(vertices), tuple(vertices[1:] + vertices[:1]), tuple(vertices[2:] + vertices[:2]))
            unique[key] += 1
        duplicates = sum(count - 1 for count in unique.values() if count > 1)
        print(" ", name, "triangles", len(tris), "repeated-position-degenerate", degenerate, "identical-same-winding", duplicates)

    pos, _, _, tris = read_mesh("Environment_Cliff1")
    scales = [matrix[5] for name, matrices in transforms.items() if name.startswith("Cliff1_") for matrix in matrices]
    if len(scales) != 6 or min(scales) <= 0:
        raise ValueError("expected six upright cliffs with positive vertical scale")
    common_threshold = 0.9 / max(scales)
    common_underwater = sum(all(pos[i][1] < common_threshold - 1e-5 for i in face) for face in tris)
    print("common triangles below water on all six cliffs", common_underwater, "per instance,", 6 * common_underwater, "total")
    candidates = []
    for name, matrices in sorted(transforms.items()):
        if not name.startswith("Cliff1_"):
            continue
        if len(matrices) != 1:
            raise ValueError(f"expected one cliff per group: {name}")
        t = matrices[0]
        if any(abs(t[i]) > 1e-8 for i in (1, 4, 6, 9)) or abs(t[7] + 2.0) > 1e-6:
            raise ValueError(f"unexpected tilt/height on {name}")
        vertices = [point(t, p) for p in pos]
        underwater = 0
        no_ground_water = []
        for index, face in enumerate(tris):
            tri = [vertices[i] for i in face]
            under, info = under_and_gap(tri)
            underwater += under
            if info is not None:
                normal = cross(sub(tri[1], tri[0]), sub(tri[2], tri[0]))
                facing = dot(normal, sub(CAMERA, info[0])) > 0
                no_ground_water.append((index, info, facing))
        print(name, "fully under water", underwater, "centroids not blocked by water/ground", len(no_ground_water),
              "facing source winding", sum(row[2] for row in no_ground_water))
        if name == "Cliff1_0_2":
            candidates = [(index, info) for index, info, facing in no_ground_water if facing]
            world_cliff = vertices

    if not candidates:
        raise ValueError("expected gap candidates disappeared; update the analysis")
    open_faces = []
    for index, info in candidates:
        target = info[0]
        if not any(ray_hit(*(world_cliff[i] for i in face), target, cull_back=True)
                   for j, face in enumerate(tris) if j != index):
            open_faces.append((index, info))
    print("Cliff1_0_2 facing candidates not blocked by own front faces", len(open_faces))
    example, info = open_faces[0]
    target, water_cross, water_inner, ground_outer, ray_y = info
    print("example triangle", example, "world center", tuple(round(v, 3) for v in target),
          "water crossing radius", round(water_cross, 3), "water inner radius", round(water_inner, 3),
          "ground outer radius", round(ground_outer, 3), "ray y there", round(ray_y, 3), "ground y -1.5")
    print("room scatter AABBs hit", multi_aabb_hits(ROOT / "rooms/room_01.tscn", target))
    print("backdrop scatter AABBs hit", multi_aabb_hits(ROOT / "rooms/backdrop_midgard.tscn", target))
    for label, geometry, transform in (
        ("Pine_0_1[11]", pine_triangles(), transforms["Pine_0_1"][11]),
        ("Rock5_0_1[0]", None, transforms["Rock5_0_1"][0]),
    ):
        if geometry is None:
            rock, _, _, rock_faces = read_mesh("Environment_Rock_5")
            geometry = [tuple(rock[i] for i in face) for face in rock_faces]
        hits = sum(ray_hit(*(point(transform, vertex) for vertex in face), target) for face in geometry)
        print(label, "two-sided triangle hits before target", hits)
    print("Other room geometry, particles, LOD, fog and actual pixels are NOT checked.")


if __name__ == "__main__":
    main()
