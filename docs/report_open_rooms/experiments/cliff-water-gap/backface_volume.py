#!/usr/bin/env python3
"""Диагностическая верхняя оценка невидимых задних граней для объёма камеры.

Проверяются координаты и порядок вершин исходного glTF, а не импортированный
Godot ArrayMesh и не рендер. Файл не меняет ресурсы игры.
"""
import importlib.util
from pathlib import Path


def load_analysis():
    path = Path(__file__).with_name("analyze.py")
    spec = importlib.util.spec_from_file_location("cliff_analysis", path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def main():
    api = load_analysis()
    positions, normals, _, triangles = api.read_mesh("Environment_Cliff1")
    _, transforms, _ = api.mesh_counts(api.ROOT / "rooms/backdrop_midgard.tscn")
    same = opposite = ambiguous = 0
    for a, b, c in triangles:
        face = api.cross(api.sub(positions[b], positions[a]), api.sub(positions[c], positions[a]))
        direction = api.dot(face, normals[a])
        same += direction > 1e-10
        opposite += direction < -1e-10
        ambiguous += abs(direction) <= 1e-10
    print("source winding vs first vertex normal: same", same, "opposite", opposite, "ambiguous", ambiguous)
    boxes = {
        "wide": ((-20.0, -25.0, -20.0), (20.0, 50.0, 20.0)),
        "room_01_example": ((-13.0, -2.0, -18.0), (13.0, 26.0, 13.0)),
    }
    for label, (low, high) in boxes.items():
        center = tuple((a + b) * 0.5 for a, b in zip(low, high))
        half = tuple((b - a) * 0.5 for a, b in zip(low, high))
        print("camera volume", label, low, high)
        total = 0
        for name, matrices in sorted(transforms.items()):
            if not name.startswith("Cliff1_"):
                continue
            matrix = matrices[0]
            determinant = (matrix[0] * (matrix[5] * matrix[10] - matrix[6] * matrix[9])
                           - matrix[1] * (matrix[4] * matrix[10] - matrix[6] * matrix[8])
                           + matrix[2] * (matrix[4] * matrix[9] - matrix[5] * matrix[8]))
            if determinant <= 0.0:
                raise ValueError(f"{name} has a reflected or singular transform; require original mesh")
            vertices = [api.point(matrix, p) for p in positions]
            count = 0
            for indices in triangles:
                a, b, c = (vertices[i] for i in indices)
                normal = api.cross(api.sub(b, a), api.sub(c, a))
                offset = api.dot(normal, api.sub(center, a))
                extent = sum(abs(n) * h for n, h in zip(normal, half))
                maximum = offset + extent
                margin = 1e-5 * max(abs(offset) + extent, 1.0)
                if maximum < -margin:
                    count += 1
            total += count
            print(name, "determinant", round(determinant, 3), "geometrically backfacing", count, "of", len(triangles))
        print("total", total, "of", len(triangles) * 6,
              "nominal compared with 1.42m monitor", round(100 * total / 1_420_000, 3), "% (not a measured saving)")


if __name__ == "__main__":
    main()
