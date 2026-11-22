# -*- coding: utf-8 -*-
"""把 Natural Earth 的 GeoJSON 转成 App 用的 world_countries.json。

用法：
  1) 手动下载 50m 数据（浏览器打开，另存为 tools/data/ne_50m.geojson）：
     https://raw.githubusercontent.com/nvkelso/natural-earth-vector/master/geojson/ne_50m_admin_0_countries.geojson
     备用：
     https://cdn.jsdelivr.net/gh/nvkelso/natural-earth-vector@master/geojson/ne_50m_admin_0_countries.geojson
  2) python tools/gen_world_countries.py

输出：assets/world_countries.json（覆盖）
格式与 App 约定一致：
  {"countries": [{"n": 名称, "p": [[[lng, lat], ...], ...]}, ...]}
"""
import json
import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, "tools", "data", "ne_50m.geojson")
OUT = os.path.join(ROOT, "assets", "world_countries.json")

# 名称字段优先级：中文名 → 英文名。中国在旧数据里就是「中国」，保持一致。
NAME_KEYS = ["NAME_ZH", "NAME_CN", "NAME", "ADMIN", "name"]


def pick_name(props):
    for k in NAME_KEYS:
        v = props.get(k)
        if isinstance(v, str) and v.strip():
            return v.strip()
    return "Unknown"


def rings(geometry):
    """把 Polygon / MultiPolygon 统一成「环的列表」。"""
    t = geometry.get("type")
    coords = geometry.get("coordinates") or []
    if t == "Polygon":
        return [ring for ring in coords if len(ring) >= 4]
    if t == "MultiPolygon":
        out = []
        for poly in coords:
            for ring in poly:
                if len(ring) >= 4:
                    out.append(ring)
        return out
    return []


def simplify(ring, step):
    """按步长抽稀（50m 全量约 5MB，抽稀后 ~1MB，视觉上仍够用）。"""
    if step <= 1:
        return ring
    out = ring[::step]
    if out[-1] != ring[-1]:
        out.append(ring[-1])
    return out


def main():
    if not os.path.exists(SRC):
        print("缺少源文件：", SRC)
        print("请先按脚本顶部注释里的地址下载 ne_50m.geojson")
        sys.exit(1)

    raw = json.load(open(SRC, encoding="utf-8"))
    feats = raw.get("features") or []
    if not feats:
        print("GeoJSON 里没有 features")
        sys.exit(1)

    # 目标体积控制在 ~1.2MB：先按 2 抽稀，还大就再抽
    for step in (1, 2, 3):
        countries = []
        for f in feats:
            props = f.get("properties") or {}
            geom = f.get("geometry") or {}
            rs = rings(geom)
            if not rs:
                continue
            polys = [[[round(x, 3), round(y, 3)] for x, y in simplify(r, step)]
                     for r in rs]
            if not polys:
                continue
            countries.append({"n": pick_name(props), "p": polys})
        blob = json.dumps({"countries": countries}, ensure_ascii=False,
                          separators=(",", ":"))
        size = len(blob.encode("utf-8"))
        print(f"step={step} countries={len(countries)} size={size/1024:.0f}KB")
        if size <= 1.6 * 1024 * 1024:
            break

    with open(OUT, "w", encoding="utf-8") as fp:
        fp.write(blob)
    print("已写入", OUT)


if __name__ == "__main__":
    main()
