#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
proc-mesh.py — 程序化有机网格生成器（给 EffectCraft / VectorCraft / 任何吃模型文件的管线用）

为什么存在：
    EffectCraft 的图元只有 cube/sphere/plane/torus/cone/cylinder，材质通道里没有
    normal / bump / displacement / 贴图。所以「橘皮」「石面」「布褶」这类表面起伏，
    在参数里表达不出来 —— 只能把形状和材质烘进一个模型文件，再用 layer.newModel 导入。
    一句话：形状归代码，光影归引擎。

用法：
    python proc-mesh.py --preset orange --out designs/<slug>/3d/orange
    python proc-mesh.py --preset stone  --out ... --radius 1.0 --detail 256x128
    python proc-mesh.py --preset orange --format gltf --out ...
    python proc-mesh.py --preset custom --amplitude 0.03 --frequency 18 --dimples 22 ...

产出（--out 给的是不带扩展名的前缀）：
    <out>.obj + <out>.mtl + <out>_albedo.png + <out>_normal.png + <out>_rough.png
    <out>.gltf + <out>.bin + 同样的贴图          （--format gltf 时）
    <out>.json                                  生成参数快照，便于复现和迭代

设计约束（照做，别改）：
    * 只用 numpy + Pillow，不依赖 trimesh / scipy / 网络。
    * 顶点法线自己算（位移之后必须重算，否则光照是假的）。
    * UV 用等距柱状（spherical），接缝在背面；有机体一律能接受。
    * 纹理尺寸默认 1024，印刷稿可给 2048；再大纯属浪费。
"""

from __future__ import annotations

import argparse
import json
import math
import os
import sys

import numpy as np
from PIL import Image, ImageFilter


# ----------------------------------------------------------------------------
# 1. 噪声：多倍频值噪声（value noise），向量化，够用且不引入依赖
# ----------------------------------------------------------------------------

def _hash3(ix, iy, iz, seed):
    """把整数格点映射到 [0,1) 的伪随机值。"""
    h = (ix * 374761393 + iy * 668265263 + iz * 2147483647 + seed * 971) & 0xFFFFFFFF
    h = (h ^ (h >> 13)) * 1274126177 & 0xFFFFFFFF
    h = h ^ (h >> 16)
    return (h & 0xFFFFFF) / float(0x1000000)


def value_noise(p, seed=0):
    """p: (N,3) float 数组，返回 (N,) ∈ [0,1] 的三线性值噪声。"""
    p = np.asarray(p, dtype=np.float64)
    i = np.floor(p).astype(np.int64)
    f = p - i
    # smoothstep，避免方块感
    f = f * f * (3.0 - 2.0 * f)

    c = np.zeros((p.shape[0], 8), dtype=np.float64)
    k = 0
    for dz in (0, 1):
        for dy in (0, 1):
            for dx in (0, 1):
                c[:, k] = _hash3(i[:, 0] + dx, i[:, 1] + dy, i[:, 2] + dz, seed)
                k += 1

    fx, fy, fz = f[:, 0], f[:, 1], f[:, 2]
    # 三线性插值，按 8 个角点的索引顺序 x 最快、z 最慢
    x00 = c[:, 0] * (1 - fx) + c[:, 1] * fx
    x10 = c[:, 2] * (1 - fx) + c[:, 3] * fx
    x01 = c[:, 4] * (1 - fx) + c[:, 5] * fx
    x11 = c[:, 6] * (1 - fx) + c[:, 7] * fx
    y0 = x00 * (1 - fy) + x10 * fy
    y1 = x01 * (1 - fy) + x11 * fy
    return y0 * (1 - fz) + y1 * fz


def fbm(p, octaves=4, frequency=6.0, lacunarity=2.1, gain=0.5, seed=0):
    """分形叠加，返回 (N,) 大致 ∈ [0,1]。"""
    total = np.zeros(p.shape[0], dtype=np.float64)
    amp = 1.0
    norm = 0.0
    freq = float(frequency)
    for o in range(octaves):
        total += amp * value_noise(p * freq, seed=seed + o * 37)
        norm += amp
        amp *= gain
        freq *= lacunarity
    return total / max(norm, 1e-9)


# ----------------------------------------------------------------------------
# 2. 球面网格 + 位移
# ----------------------------------------------------------------------------

def sphere_grid(segments=192, rings=128):
    """返回 UV 球顶点 (N,3)、UV (N,2)、四边形索引 (M,4)（顶点索引，未展平）。"""
    us = np.linspace(0.0, 1.0, segments, endpoint=False)
    vs = np.linspace(0.0, 1.0, rings)

    uu, vv = np.meshgrid(us, vs, indexing="xy")  # (rings, segments)
    theta = uu * 2.0 * math.pi
    phi = vv * math.pi

    x = np.sin(phi) * np.cos(theta)
    y = np.cos(phi)
    z = np.sin(phi) * np.sin(theta)

    verts = np.stack([x, y, z], axis=-1).reshape(-1, 3)
    uv = np.stack([uu, 1.0 - vv], axis=-1).reshape(-1, 2)

    idx = np.arange(rings * segments).reshape(rings, segments)
    quads = []
    for r in range(rings - 1):
        a = idx[r]
        b = idx[r + 1]
        q = np.stack([a, np.roll(a, -1), np.roll(b, -1), b], axis=-1)
        quads.append(q)
    quads = np.concatenate(quads, axis=0)
    return verts, uv, quads


def dimple_field(p, count=18.0, depth=1.0, seed=5):
    """
    橘皮式凹点：在球面上撒 count^2 个近似均匀的点，每个点做高斯凹陷。
    用「随机方向 + 角度距离」算，避免极点挤压。
    """
    n = int(max(4, round(count)))
    rng = np.random.default_rng(seed)
    dirs = rng.normal(size=(n * n, 3))
    dirs /= np.linalg.norm(dirs, axis=1, keepdims=True)
    # 每个凹点的角半径略有差异，避免机器感
    radii = rng.uniform(0.55, 1.25, size=(n * n, 1)) * (math.pi / (n * 1.6))

    cosang = np.clip(p @ dirs.T, -1.0, 1.0)          # (N, n*n)
    ang = np.arccos(cosang)
    falloff = np.exp(-(ang / radii.T) ** 2)
    return falloff.max(axis=1) * depth


def displacement(dirs, P):
    """
    给定单位方向 dirs (N,3)，返回相对位移 h (N,)，半径 = P['radius'] * (1 + h)。
    几何与贴图共用这一个函数 —— 保证法线图与真实几何严格对齐。
    """
    low = fbm(dirs, octaves=2, frequency=1.6, gain=0.55, seed=P["seed"] + 11)
    shape = (low - 0.5) * (P["amplitude"] * 3.2)

    det = (fbm(dirs, octaves=P["octaves"], frequency=P["frequency"], seed=P["seed"]) - 0.5) * P["amplitude"]
    if P["dimple_count"]:
        det = det - dimple_field(dirs, count=P["dimple_count"],
                                 depth=P["dimple_depth"], seed=P["seed"] + 3)
    return shape + det


def build_organic(preset, detail, radius, amplitude, frequency, octaves,
                  dimple_count, dimple_depth, seed):
    segments, rings = detail
    verts, uv, quads = sphere_grid(segments, rings)

    if preset == "orange":
        amp = amplitude if amplitude is not None else 0.009
        freq = frequency if frequency is not None else 7.0
        octv = octaves or 4
        dc = dimple_count if dimple_count is not None else 30
        dd = dimple_depth if dimple_depth is not None else 0.016
    elif preset == "stone":
        amp, freq, octv = amplitude or 0.055, frequency or 4.0, octaves or 5
        dc, dd = dimple_count or 8, dimple_depth or 0.02
    elif preset == "fabric":
        amp, freq, octv = amplitude or 0.010, frequency or 22.0, octaves or 3
        dc, dd = dimple_count or 26, dimple_depth or 0.004
    else:  # custom
        amp, freq, octv = amplitude or 0.02, frequency or 8.0, octaves or 4
        dc, dd = dimple_count or 0.0, dimple_depth or 0.0

    P = dict(radius=radius, amplitude=amp, frequency=freq, octaves=int(octv),
             dimple_count=dc, dimple_depth=dd, seed=seed)

    out = verts * (radius * (1.0 + displacement(verts, P)))[:, None]

    P.update({
        "preset": preset,
        "detail": [int(segments), int(rings)],
        "vertices": int(out.shape[0]),
        "quads": int(quads.shape[0]),
    })
    return out, uv, quads, P


# ----------------------------------------------------------------------------
# 3. 法线 / 面积统计
# ----------------------------------------------------------------------------

def vertex_normals(positions, quads):
    """面法线面积加权平均到顶点——位移之后必须重算，否则高光是假的。"""
    tri = np.concatenate([quads[:, [0, 1, 2]], quads[:, [0, 2, 3]]], axis=0)
    a, b, c = positions[tri[:, 0]], positions[tri[:, 1]], positions[tri[:, 2]]
    fn = np.cross(b - a, c - a)  # 长度 ∝ 面积，正好当权重

    n = np.zeros_like(positions)
    for k in range(3):
        np.add.at(n, tri[:, k], fn)
    ln = np.linalg.norm(n, axis=1, keepdims=True)
    ln[ln < 1e-12] = 1.0
    return n / ln


def surface_stats(positions, uv, radius):
    """给交付说明用的可核查数字：真实半径变异、圆度。"""
    r = np.linalg.norm(positions, axis=1)
    return {
        "radius_min": float(r.min()),
        "radius_max": float(r.max()),
        "radius_mean": float(r.mean()),
        "radius_rel_spread": float((r.max() - r.min()) / max(radius, 1e-9)),
        "silhouette_is_perfect_circle": bool((r.max() - r.min()) / radius < 1e-4),
    }


# ----------------------------------------------------------------------------
# 4. 贴图烘焙（albedo / normal / roughness）
# ----------------------------------------------------------------------------

def _to_u8(arr):
    return np.clip(arr * 255.0 + 0.5, 0, 255).astype(np.uint8)


def bake_textures(out_prefix, P, recipe, tex_size, base_rgb):
    """
    逐像素解析烘焙：对每个纹素 (u,v) 反解球面方向，用与几何同源的噪声求高度。

    分工（重要，别改）：
      * 凹点（dimple）已经烘进**几何**了，这里不再重复计算 —— 否则 1M 纹素 × 上百个凹点会慢 20 倍，
        而且法线图会与几何互相打架。
      * 贴图只负责**几何分辨率装不下的细部**：油胞孔隙、色斑、粗糙度起伏。
    """
    W = Hh = int(tex_size)
    base = np.asarray(base_rgb, dtype=np.float64)

    us = np.linspace(0.0, 1.0, W)
    vs = np.linspace(0.0, 1.0, Hh)
    uu, vv = np.meshgrid(us, vs, indexing="xy")

    theta = uu * 2.0 * math.pi
    phi = vv * math.pi
    dirs = np.stack([
        np.sin(phi) * np.cos(theta),
        np.cos(phi),
        np.sin(phi) * np.sin(theta),
    ], axis=-1).reshape(-1, 3)

    # 只取高频细部：比几何频率再高一档，两倍频程
    freq = max(P["frequency"] * 2.2, 24.0)
    fine = (fbm(dirs, octaves=2, frequency=freq, seed=P["seed"] + 101) - 0.5) * P["amplitude"]
    fine = fine.reshape(Hh, W)
    hmap = (fine - fine.min()) / max(fine.max() - fine.min(), 1e-9)

    # albedo：基色 + 细尺度色斑（轻微不匀，不制造大片霉斑）
    mottle = fbm(np.stack([uu * 3.0, vv * 3.0, np.zeros_like(uu)], axis=-1).reshape(-1, 3),
                 octaves=3, frequency=9.0, seed=P["seed"] + 7).reshape(Hh, W)
    shade = 1.0 + (mottle - 0.5) * float(recipe["color_variance"])
    shade = shade * (0.96 + 0.08 * hmap)
    albedo = np.clip(base[None, None, :] * shade[:, :, None], 0, 1)
    Image.fromarray(_to_u8(albedo), "RGB").save(out_prefix + "_albedo.png")

    # normal：对高度图求梯度，转切线空间
    gy, gx = np.gradient(hmap)
    strength = float(recipe["normal_strength"])
    nx = -gx * strength * W * 0.0040
    ny = -gy * strength * Hh * 0.0040
    nz = np.ones_like(nx)
    ln = np.sqrt(nx * nx + ny * ny + nz * nz)
    nrm = np.stack([nx / ln, ny / ln, nz / ln], axis=-1) * 0.5 + 0.5
    Image.fromarray(_to_u8(nrm), "RGB").save(out_prefix + "_normal.png")

    # roughness：凹处略粗糙（橘皮油胞的反光反差就来自这里）
    rough = np.clip(float(recipe["roughness"]) + (hmap - 0.5) * float(recipe["rough_variance"]), 0.05, 1.0)
    Image.fromarray(_to_u8(rough), "L").save(out_prefix + "_rough.png")

    # glTF 的 metallicRoughness 贴图通道约定：G = roughness，B = metallic。
    # 只写灰度图会让 B 也等于 roughness → 表面被当成金属。必须单独出一张 RGB。
    mr = np.zeros((Hh, W, 3), dtype=np.float64)
    mr[:, :, 0] = 1.0                      # R：遮蔽（不用）
    mr[:, :, 1] = rough                    # G：roughness
    mr[:, :, 2] = 0.0                      # B：metallic（有机物 = 0）
    Image.fromarray(_to_u8(mr), "RGB").save(out_prefix + "_mr.png")

    return {"albedo": out_prefix + "_albedo.png",
            "normal": out_prefix + "_normal.png",
            "rough": out_prefix + "_rough.png",
            "mr": out_prefix + "_mr.png"}


# ----------------------------------------------------------------------------
# 5. 导出：OBJ+MTL / glTF
# ----------------------------------------------------------------------------

def export_obj(out_prefix, positions, uv, normals, quads, tex, base_rgb, recipe):
    obj_path = out_prefix + ".obj"
    mtl_path = out_prefix + ".mtl"

    with open(obj_path, "w", encoding="utf-8", newline="\n") as f:
        f.write("# proc-mesh.py  %s  seed=%s\n" % (recipe["preset"], recipe["seed"]))
        f.write("mtllib %s\n" % os.path.basename(mtl_path))
        f.write("o %s\n" % os.path.basename(out_prefix))
        for p in positions:
            f.write("v %.6f %.6f %.6f\n" % (p[0], p[1], p[2]))
        for t in uv:
            f.write("vt %.6f %.6f\n" % (t[0], t[1]))
        for n in normals:
            f.write("vn %.6f %.6f %.6f\n" % (n[0], n[1], n[2]))
        f.write("usemtl procmesh\n")
        f.write("s 1\n")
        for q in quads:
            i = [int(x) + 1 for x in q]
            f.write("f %d/%d/%d %d/%d/%d %d/%d/%d %d/%d/%d\n" % (
                i[0], i[0], i[0], i[1], i[1], i[1],
                i[2], i[2], i[2], i[3], i[3], i[3]))

    with open(mtl_path, "w", encoding="utf-8", newline="\n") as f:
        f.write("# proc-mesh.py material\n")
        f.write("newmtl procmesh\n")
        f.write("Kd %.6f %.6f %.6f\n" % tuple(base_rgb))
        f.write("Ka 0 0 0\nKs 0.35 0.35 0.35\nNs 40\n")
        f.write("d 1.0\nillum 2\n")
        for key, tag in (("albedo", "map_Kd"), ("normal", "map_Bump"), ("rough", "map_Ns")):
            if key in tex:
                f.write("%s %s\n" % (tag, os.path.basename(tex[key])))
    return obj_path


def _geo_views(positions, normals, uv, tri):
    """建立几何 bufferViews / accessors，返回 (blob, views, accessors)。"""
    blob = bytearray()
    views = []

    def add(data, target=None):
        while len(blob) % 4:
            blob.append(0)
        off = len(blob)
        blob.extend(data)
        v = {"buffer": 0, "byteOffset": off, "byteLength": len(data)}
        if target:
            v["target"] = target
        views.append(v)
        return len(views) - 1

    pos = np.asarray(positions, dtype=np.float32)
    nrm = np.asarray(normals, dtype=np.float32)
    tc = np.asarray(uv, dtype=np.float32)

    v_pos = add(pos.tobytes(), 34962)
    v_nrm = add(nrm.tobytes(), 34962)
    v_uv = add(tc.tobytes(), 34962)
    v_idx = add(np.asarray(tri, dtype=np.uint32).tobytes(), 34963)

    accessors = [
        {"bufferView": v_pos, "componentType": 5126, "count": int(len(pos)), "type": "VEC3",
         "min": pos.min(axis=0).tolist(), "max": pos.max(axis=0).tolist()},
        {"bufferView": v_nrm, "componentType": 5126, "count": int(len(nrm)), "type": "VEC3"},
        {"bufferView": v_uv, "componentType": 5126, "count": int(len(tc)), "type": "VEC2"},
        {"bufferView": v_idx, "componentType": 5125, "count": int(np.asarray(tri).size), "type": "SCALAR"},
    ]
    return blob, views, accessors


def _material_and_textures(tex, base_rgb, has_textures):
    """
    glTF 的 factor × texture 是**相乘**关系，这里有两个会静默毁掉画面的坑：
      1. metallicFactor: 0 会把整张 metallicRoughness 贴图乘成 0 —— 粗糙度图直接失效。
      2. baseColorFactor 若不是 1，会把已经烘好颜色的 albedo 再乘一遍，整体发暗。
    所以：有贴图时 factor 一律给 1，颜色和粗糙度全部交给贴图。
    """
    mat = {"name": "procmesh", "doubleSided": True,
           "pbrMetallicRoughness": {
               "baseColorFactor": [1.0, 1.0, 1.0, 1.0] if "albedo" in tex else
                                  [float(base_rgb[0]), float(base_rgb[1]), float(base_rgb[2]), 1.0],
               "metallicFactor": 1.0 if "mr" in tex else 0.0,
               "roughnessFactor": 1.0 if "mr" in tex else 0.9,
           }}
    slot = {"albedo": "baseColorTexture", "mr": "metallicRoughnessTexture", "normal": "normalTexture"}
    order = [k for k in ("albedo", "normal", "mr") if k in tex]
    for i, key in enumerate(order):
        if key == "normal":
            mat["normalTexture"] = {"index": i}
        else:
            mat["pbrMetallicRoughness"][slot[key]] = {"index": i}
    return mat, order


def export_gltf(out_prefix, positions, uv, normals, quads, tex, base_rgb, recipe, embed=False):
    """
    embed=False → .gltf + .bin + 外部贴图（便于人工检查）
    embed=True  → 单个 .glb，贴图全部塞进 BIN chunk（推荐给 EffectCraft：一次 layer.newModel，无路径解析）
    """
    tri = np.concatenate([quads[:, [0, 1, 2]], quads[:, [0, 2, 3]]], axis=0)
    blob, views, accessors = _geo_views(positions, normals, uv, tri)
    mat, order = _material_and_textures(tex, base_rgb, True)

    images, textures = [], []
    for i, key in enumerate(order):
        if embed:
            while len(blob) % 4:
                blob.append(0)
            off = len(blob)
            data = open(tex[key], "rb").read()
            blob.extend(data)
            views.append({"buffer": 0, "byteOffset": off, "byteLength": len(data)})
            images.append({"bufferView": len(views) - 1, "mimeType": "image/png"})
        else:
            images.append({"uri": os.path.basename(tex[key])})
        textures.append({"source": i, "sampler": 0})

    doc = {
        "asset": {"version": "2.0", "generator": "proc-mesh.py"},
        "scene": 0,
        "scenes": [{"nodes": [0]}],
        "nodes": [{"mesh": 0, "name": os.path.basename(out_prefix)}],
        "meshes": [{"name": "procmesh", "primitives": [{
            "attributes": {"POSITION": 0, "NORMAL": 1, "TEXCOORD_0": 2},
            "indices": 3, "material": 0, "mode": 4}]}],
        "materials": [mat],
        "accessors": accessors,
        "bufferViews": views,
        "buffers": [{"byteLength": len(blob)}],
        "samplers": [{"magFilter": 9729, "minFilter": 9987, "wrapS": 10497, "wrapT": 10497}],
        "images": images,
        "textures": textures,
    }

    if not embed:
        bin_path = out_prefix + ".bin"
        with open(bin_path, "wb") as f:
            f.write(bytes(blob))
        doc["buffers"][0]["uri"] = os.path.basename(bin_path)
        path = out_prefix + ".gltf"
        with open(path, "w", encoding="utf-8", newline="\n") as f:
            json.dump(doc, f, ensure_ascii=False, indent=1)
        return path

    # ---- GLB ----
    import struct
    js = json.dumps(doc, ensure_ascii=False, separators=(",", ":")).encode("utf-8")
    while len(js) % 4:
        js += b" "
    while len(blob) % 4:
        blob.append(0)
    total = 12 + 8 + len(js) + 8 + len(blob)
    path = out_prefix + ".glb"
    with open(path, "wb") as f:
        f.write(struct.pack("<III", 0x46546C67, 2, total))
        f.write(struct.pack("<II", len(js), 0x4E4F534A))
        f.write(js)
        f.write(struct.pack("<II", len(blob), 0x004E4942))
        f.write(bytes(blob))
    return path


# ----------------------------------------------------------------------------
# 6. CLI
# ----------------------------------------------------------------------------

PRESETS = {
    # 基色按 0–1 给，脚本内部不再做色彩管理
    "orange": dict(base=(0.949, 0.416, 0.106), roughness=0.62, rough_variance=0.16,
                   color_variance=0.09, normal_strength=0.8),
    "stone": dict(base=(0.62, 0.60, 0.56), roughness=0.85, rough_variance=0.20,
                  color_variance=0.30, normal_strength=1.6),
    "fabric": dict(base=(0.80, 0.78, 0.74), roughness=0.92, rough_variance=0.12,
                   color_variance=0.10, normal_strength=0.7),
    "custom": dict(base=(0.75, 0.45, 0.30), roughness=0.60, rough_variance=0.25,
                   color_variance=0.15, normal_strength=1.0),
}


def parse_detail(s):
    try:
        a, b = s.lower().replace(" ", "").split("x")
        return int(a), int(b)
    except Exception:
        raise argparse.ArgumentTypeError("--detail 要写成 192x128（经度x纬度）")


def main(argv=None):
    ap = argparse.ArgumentParser(description="程序化有机网格生成器（球面 + 多倍频位移 + 贴图烘焙）")
    ap.add_argument("--preset", default="orange", choices=sorted(PRESETS))
    ap.add_argument("--out", required=True, help="不带扩展名的输出前缀")
    ap.add_argument("--format", default="glb", choices=["obj", "gltf", "glb", "both"],
                    help="glb=自包含单文件（推荐给 EffectCraft）；both=obj+glb")
    ap.add_argument("--detail", type=parse_detail, default=(192, 128), help="经度x纬度，默认 192x128")
    ap.add_argument("--radius", type=float, default=1.0)
    ap.add_argument("--amplitude", type=float, default=None, help="高频起伏幅度（相对半径）")
    ap.add_argument("--frequency", type=float, default=None)
    ap.add_argument("--octaves", type=int, default=None)
    ap.add_argument("--dimples", type=float, default=None, help="凹点密度（每边个数，0=关）")
    ap.add_argument("--dimple-depth", type=float, default=None)
    ap.add_argument("--seed", type=int, default=7)
    ap.add_argument("--tex", type=int, default=1024, help="贴图边长，1024 够用，2048 给印刷")
    ap.add_argument("--dry-run", action="store_true", help="只打印统计，不写文件")
    args = ap.parse_args(argv)

    out_prefix = os.path.abspath(args.out)
    os.makedirs(os.path.dirname(out_prefix) or ".", exist_ok=True)

    positions, uv, quads, recipe = build_organic(
        args.preset, args.detail, args.radius, args.amplitude, args.frequency,
        args.octaves, args.dimples, args.dimple_depth, args.seed)
    normals = vertex_normals(positions, quads)

    stats = surface_stats(positions, uv, args.radius)

    base = PRESETS[args.preset]
    tex_recipe = dict(seed=args.seed, normal_strength=base["normal_strength"],
                      roughness=base["roughness"], rough_variance=base["rough_variance"],
                      color_variance=base["color_variance"])

    report = {
        "output": out_prefix,
        "mesh": recipe,
        "surface": stats,
        "textures": {},
        "files": [],
    }

    if args.dry_run:
        print(json.dumps(report, ensure_ascii=False, indent=2))
        return 0

    tex = bake_textures(out_prefix, recipe, tex_recipe, args.tex, base["base"])
    report["textures"] = {k: os.path.basename(v) for k, v in tex.items()}

    if args.format in ("obj", "both"):
        report["files"].append(os.path.basename(
            export_obj(out_prefix, positions, uv, normals, quads, tex, base["base"], recipe)))
    if args.format != "obj":
        report["files"].append(os.path.basename(
            export_gltf(out_prefix, positions, uv, normals, quads, tex, base["base"], recipe,
                        embed=(args.format != "gltf"))))

    report["files"] += [os.path.basename(v) for v in tex.values()]
    with open(out_prefix + ".json", "w", encoding="utf-8", newline="\n") as f:
        json.dump(report, f, ensure_ascii=False, indent=2)
    report["files"].append(os.path.basename(out_prefix + ".json"))

    print(json.dumps(report, ensure_ascii=False, indent=2))
    print("\n[ok] %d vertices / %d quads, radius spread %.4f%%" % (
        recipe["vertices"], recipe["quads"], stats["radius_rel_spread"] * 100.0))
    return 0


if __name__ == "__main__":
    sys.exit(main())
