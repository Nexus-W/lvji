# -*- coding: utf-8 -*-
"""生成「旅迹」产品介绍 PDF（App Store 详情页风格）。

设计取向：白底、大留白、大字标题、灰阶为主、单一强调色。
运行：python docs/build_brochure.py
输出：docs/旅迹-产品介绍.pdf
"""
import os
from reportlab.lib import colors
from reportlab.lib.pagesizes import A4
from reportlab.lib.styles import ParagraphStyle
from reportlab.lib.units import mm
from reportlab.pdfbase import pdfmetrics
from reportlab.pdfbase.ttfonts import TTFont
from reportlab.platypus import (BaseDocTemplate, Frame, PageTemplate, Paragraph,
                                Spacer, Table, TableStyle, KeepTogether, PageBreak)
from reportlab.graphics.shapes import Drawing, Rect, String, Circle

FONT_DIR = r"C:\Windows\Fonts"
pdfmetrics.registerFont(TTFont("YaHei", os.path.join(FONT_DIR, "msyh.ttc")))
pdfmetrics.registerFont(TTFont("YaHeiBold", os.path.join(FONT_DIR, "msyhbd.ttc")))

# 配色（Apple 风格的克制灰阶 + 一个强调色）
INK = colors.HexColor("#0B0B0C")
SUB = colors.HexColor("#6E6E73")
LINE = colors.HexColor("#E5E5E7")
BG_SOFT = colors.HexColor("#F5F5F7")
ACCENT = colors.HexColor("#2F7D5D")   # 旅迹的墨绿

PAGE_W, PAGE_H = A4
MARGIN = 22 * mm

OUT = os.path.join(os.path.dirname(__file__), "旅迹-产品介绍.pdf")


def style(name, size, leading=None, color=INK, font="YaHei", space=0, align=0):
    return ParagraphStyle(
        name, fontName=font, fontSize=size,
        leading=leading or size * 1.55, textColor=color,
        spaceAfter=space, alignment=align, wordWrap="CJK",
    )


S_HERO = style("hero", 44, 56, font="YaHeiBold")
S_TITLE = style("title", 26, 34, font="YaHeiBold", space=8)
S_LEAD = style("lead", 13, 24, SUB)
S_BODY = style("body", 10.5, 19, colors.HexColor("#3A3A3C"))
S_SMALL = style("small", 9, 16, SUB)
S_LABEL = style("label", 8.5, 14, SUB, font="YaHeiBold")
S_QUOTE = style("quote", 15, 27, INK)


def hr(width=MARGIN * 2 - 2 * MARGIN, color=LINE, thickness=0.6):
    d = Drawing(PAGE_W - 2 * MARGIN, 1)
    d.add(Rect(0, 0, PAGE_W - 2 * MARGIN, thickness, fillColor=color, strokeColor=None))
    return d


def hero_cover():
    """封面：大字 + 一句话 + 版本信息 + 截图占位。"""
    els = []
    els.append(Spacer(1, 26 * mm))
    els.append(Paragraph("旅迹", S_HERO))
    els.append(Spacer(1, 3 * mm))
    els.append(Paragraph("把一次旅行，留成一张会发光的地图。", S_QUOTE))
    els.append(Spacer(1, 6 * mm))
    els.append(Paragraph(
        "本地优先的旅行相册。照片、地点与时间全部留在你的设备上，"
        "无需账号，不上传云端。", S_LEAD))
    els.append(Spacer(1, 12 * mm))

    # 截图占位（三台手机并排的观感）
    els.append(phone_row())
    els.append(Spacer(1, 9 * mm))

    els.append(hr())
    els.append(Spacer(1, 4 * mm))
    meta = Table(
        [[Paragraph("版本", S_LABEL), Paragraph("V1.0.12", S_BODY),
          Paragraph("开发者", S_LABEL), Paragraph("Aeon", S_BODY),
          Paragraph("平台", S_LABEL), Paragraph("Android", S_BODY)]],
        colWidths=[16 * mm, 30 * mm, 16 * mm, 28 * mm, 14 * mm, 30 * mm],
    )
    meta.setStyle(TableStyle([
        ("VALIGN", (0, 0), (-1, -1), "MIDDLE"),
        ("LEFTPADDING", (0, 0), (-1, -1), 0),
        ("BOTTOMPADDING", (0, 0), (-1, -1), 0),
    ]))
    els.append(meta)
    els.append(PageBreak())
    return els


def phone_row():
    """三个圆角矩形模拟手机截图位，内部留白等用户放图。"""
    w = PAGE_W - 2 * MARGIN
    h = 88 * mm
    d = Drawing(w, h)
    gap = 7 * mm
    pw = (w - gap * 2) / 3
    for i in range(3):
        x = i * (pw + gap)
        d.add(Rect(x, 0, pw, h, rx=5 * mm, ry=5 * mm,
                   fillColor=BG_SOFT, strokeColor=LINE, strokeWidth=0.8))
        d.add(String(x + pw / 2, h / 2 + 8 * mm, f"0{i + 1}",
                     fontName="YaHeiBold", fontSize=26,
                     fillColor=colors.HexColor("#C7C7CC"), textAnchor="middle"))
        d.add(String(x + pw / 2, h / 2 + 1 * mm, "截图位",
                     fontName="YaHei", fontSize=8.5, fillColor=SUB,
                     textAnchor="middle"))
    return d


def feature(icon_text, title, body):
    """一个功能块：小标签 + 标题 + 描述。"""
    return [
        Paragraph(icon_text, S_LABEL),
        Spacer(1, 1.5 * mm),
        Paragraph(title, style("ft", 15, 21, font="YaHeiBold")),
        Spacer(1, 1.5 * mm),
        Paragraph(body, S_BODY),
    ]


def features_page():
    els = [Paragraph("功能", S_TITLE),
           Paragraph("六个模块，覆盖一次旅行从导入到回看的全过程。", S_LEAD),
           Spacer(1, 8 * mm)]

    items = [
        ("01  导入", "读懂每一张照片",
         "支持 JPG 与 HEIC。读取原始 EXIF 的拍摄时间与 GPS，"
         "自动按天归组；重复导入自动去重，删掉的照片重新导入即可恢复。"),
        ("02  地图", "照片落在它该在的地方",
         "按城市聚合气泡，点开即见当天全部照片。"
         "下滑时间轴，地图随日期移动；长按可多选，批量加精选或删除。"),
        ("03  精选", "值得单独留下的那几张",
         "全部与精选双视图切换。按城市生成跳转标签，同城不重复；"
         "长按进入多选，一次处理多张。"),
        ("04  足迹", "把去过的地方点亮",
         "国家 → 行程 → 城市三级穿透。世界地图按到访城市点亮，"
         "一眼看见自己的旅行版图。"),
        ("05  补位置", "没有 GPS 也不会丢",
         "批量设置时间与地点，支持地名反查坐标。"
         "微信传图丢失 EXIF 时，可从文件名推断拍摄时间。"),
        ("06  分享", "一张图，替你说完这趟旅程",
         "九宫格导出，固定 1080×1080。可直接存入系统相册，"
         "或调起系统分享面板。"),
    ]

    rows = []
    for i in range(0, len(items), 2):
        pair = items[i:i + 2]
        cells = [feature(*p) for p in pair]
        while len(cells) < 2:
            cells.append([])
        rows.append(cells)

    t = Table(rows, colWidths=[(PAGE_W - 2 * MARGIN) / 2 - 5 * mm] * 2)
    t.setStyle(TableStyle([
        ("VALIGN", (0, 0), (-1, -1), "TOP"),
        ("LEFTPADDING", (0, 0), (-1, -1), 0),
        ("RIGHTPADDING", (0, 0), (-1, -1), 10 * mm),
        ("TOPPADDING", (0, 0), (-1, -1), 7 * mm),
        ("BOTTOMPADDING", (0, 0), (-1, -1), 4 * mm),
        ("LINEBELOW", (0, 0), (-1, -2), 0.5, LINE),
    ]))
    els.append(t)
    els.append(PageBreak())
    return els


def design_page():
    els = [Paragraph("设计", S_TITLE),
           Paragraph("克制的颜色，让照片成为唯一的主角。", S_LEAD),
           Spacer(1, 8 * mm)]

    # 色彩
    els.append(Paragraph("色彩", S_LABEL))
    els.append(Spacer(1, 3 * mm))
    swatches = [
        ("#0B0B0C", "墨", "文字与标题"),
        ("#6E6E73", "灰", "辅助信息"),
        ("#F5F5F7", "纸", "卡片底色"),
        ("#2F7D5D", "青", "强调与点亮"),
    ]
    d = Drawing(PAGE_W - 2 * MARGIN, 32 * mm)
    sw = 30 * mm
    for i, (hexv, name, desc) in enumerate(swatches):
        x = i * (sw + 6 * mm)
        d.add(Rect(x, 14 * mm, sw, 14 * mm, rx=2.5 * mm, ry=2.5 * mm,
                   fillColor=colors.HexColor(hexv),
                   strokeColor=LINE if hexv == "#F5F5F7" else None,
                   strokeWidth=0.8 if hexv == "#F5F5F7" else 0))
        d.add(String(x, 9 * mm, name, fontName="YaHeiBold", fontSize=9, fillColor=INK))
        d.add(String(x, 4.5 * mm, desc, fontName="YaHei", fontSize=7.5, fillColor=SUB))
    els.append(d)
    els.append(Spacer(1, 6 * mm))

    # 排版与原则
    els.append(Paragraph("排版", S_LABEL))
    els.append(Spacer(1, 2 * mm))
    els.append(Paragraph(
        "标题用系统无衬线体的大字号与负字距，正文保持 1.8 倍行高；"
        "信息层级只靠字号与灰度区分，不额外加框、加线、加阴影。"
        "每一屏只保留一个视觉重点，其余元素退到背景。", S_BODY))
    els.append(Spacer(1, 6 * mm))

    els.append(Paragraph("三条原则", S_LABEL))
    els.append(Spacer(1, 2 * mm))
    principles = [
        ("照片优先", "界面不抢照片的颜色。除强调色外，全站只用灰阶。"),
        ("少即是多", "能用一个手势完成的，不放两个按钮。"),
        ("本地优先", "不登录、不上传。数据在设备里，卸载即消失。"),
    ]
    for t, b in principles:
        els.append(Paragraph(f"<b>{t}</b>", S_BODY))
        els.append(Paragraph(b, S_SMALL))
        els.append(Spacer(1, 1.5 * mm))
    els.append(PageBreak())
    return els


def tech_page():
    els = [Paragraph("技术", S_TITLE),
           Paragraph("几处不显眼、但决定体验的地方。", S_LEAD),
           Spacer(1, 8 * mm)]
    rows = [
        ("EXIF 解析", "自写 JPEG / HEIC 解析器，不经第三方库，"
                     "在 AOT 编译下也能稳定读出原始经纬度与拍摄时间。"),
        ("坐标纠偏", "照片的 WGS-84 统一转为 GCJ-02 后入库，"
                   "境外坐标自动跳过偏移。"),
        ("读取原图", "Android 10+ 的分区存储会隐藏照片位置，"
                   "通过 ACCESS_MEDIA_LOCATION 取回原始数据。"),
        ("完全本地", "SQLite 单文件存储，无网络请求也能完整使用；"
                   "删除进入 7 天回收站，过期自动清理。"),
    ]
    for t, b in rows:
        els.append(Paragraph(t, style("tt", 11, 16, font="YaHeiBold")))
        els.append(Spacer(1, 1 * mm))
        els.append(Paragraph(b, S_BODY))
        els.append(Spacer(1, 5 * mm))
        els.append(hr())
        els.append(Spacer(1, 4 * mm))
    els.append(PageBreak())
    return els


def closing_page():
    els = [Spacer(1, 30 * mm)]
    els.append(Paragraph("照片会褪色，<br/>地点会忘记。", S_TITLE))
    els.append(Spacer(1, 4 * mm))
    els.append(Paragraph("把它们放在一张地图上，就不会了。", S_LEAD))
    els.append(Spacer(1, 12 * mm))
    els.append(hr())
    els.append(Spacer(1, 5 * mm))
    els.append(Paragraph("旅迹　V1.0.12", S_BODY))
    els.append(Paragraph("开发者　Aeon", S_BODY))
    els.append(Paragraph("本地优先 · 无需账号 · 不上传云端", S_SMALL))
    return els


def build():
    doc = BaseDocTemplate(
        OUT, pagesize=A4,
        leftMargin=MARGIN, rightMargin=MARGIN,
        topMargin=MARGIN, bottomMargin=MARGIN,
        title="旅迹 · 产品介绍", author="Aeon",
    )
    frame = Frame(MARGIN, MARGIN, PAGE_W - 2 * MARGIN, PAGE_H - 2 * MARGIN, id="f")

    def on_page(canv, d):
        canv.saveState()
        canv.setFont("YaHei", 7.5)
        canv.setFillColor(SUB)
        canv.drawString(MARGIN, 12 * mm, "旅迹 · 产品介绍")
        canv.drawRightString(PAGE_W - MARGIN, 12 * mm, f"{canv.getPageNumber():02d}")
        canv.restoreState()

    doc.addPageTemplates([PageTemplate(id="main", frames=[frame], onPage=on_page)])

    story = []
    story += hero_cover()
    story += features_page()
    story += design_page()
    story += tech_page()
    story += closing_page()
    doc.build(story)
    print("生成:", OUT)


if __name__ == "__main__":
    build()
