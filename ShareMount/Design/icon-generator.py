import math, json

def icon(bg=("#2E384A", "#11161F"), ring=("#62E894", "#1CB3A6"), glow="#3BE08A", glow_op=0.40,
         body=("#FBFCFE", "#C5CEDC"), divider="#AEB8C9", led="#34D058", lines=("#A9B3C4", "#8C97AA"),
         style="two", ring_w=48, r=232, drive_w=336, drive_h=152, shine=0.10, tile_stroke=None):
    cx = cy = 512
    def pt(a): t = math.radians(a); return cx + r*math.cos(t), cy + r*math.sin(t)
    def arc(a0, a1):
        (x0, y0), (x1, y1) = pt(a0), pt(a1)
        large = 1 if (a1 - a0) % 360 > 180 else 0
        return f"M{x0:.1f} {y0:.1f} A{r} {r} 0 {large} 1 {x1:.1f} {y1:.1f}"
    def head(a, length=None, half=None):
        length = length or ring_w * 1.95; half = half or ring_w * 1.18
        t = math.radians(a); ex, ey = pt(a)
        tx, ty = -math.sin(t), math.cos(t); nx, ny = math.cos(t), math.sin(t)
        tip = (ex + tx*length, ey + ty*length)
        b1 = (ex + nx*half, ey + ny*half); b2 = (ex - nx*half, ey - ny*half)
        return f"M{tip[0]:.1f} {tip[1]:.1f} L{b1[0]:.1f} {b1[1]:.1f} L{b2[0]:.1f} {b2[1]:.1f} Z"
    if style == "two":
        segs = [(198, 318), (18, 138)]
    elif style == "one":
        segs = [(150, 410)]
    else:  # "four": short dashes, like a sync spinner
        segs = [(200, 250), (290, 340), (20, 70), (110, 160)]
    ring_svg = ""
    for a0, a1 in segs:
        ring_svg += f'<path d="{arc(a0, a1)}" fill="none" stroke="url(#ring)" stroke-width="{ring_w}" stroke-linecap="round"/>'
        if style != "four" or (a0, a1) in [(290, 340), (110, 160)]:
            ring_svg += f'<path d="{head(a1 % 360)}" fill="url(#ring)" stroke="url(#ring)" stroke-width="10" stroke-linejoin="round"/>'
    dx, dy = 512 - drive_w/2, 512 - drive_h/2
    rx = drive_h * 0.24
    q1, q3 = dy + drive_h*0.25, dy + drive_h*0.75
    lx = dx + drive_w*0.167; l0 = dx + drive_w*0.524; l1 = dx + drive_w*0.857
    stroke = f' stroke="{tile_stroke}" stroke-width="3"' if tile_stroke else ""
    return f'''<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" viewBox="0 0 1024 1024">
<defs>
<linearGradient id="bg" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="{bg[0]}"/><stop offset="1" stop-color="{bg[1]}"/></linearGradient>
<linearGradient id="ring" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="{ring[0]}"/><stop offset="1" stop-color="{ring[1]}"/></linearGradient>
<linearGradient id="body" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="{body[0]}"/><stop offset="1" stop-color="{body[1]}"/></linearGradient>
<linearGradient id="shine" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#FFFFFF" stop-opacity="{shine}"/><stop offset="0.5" stop-color="#FFFFFF" stop-opacity="0"/></linearGradient>
<filter id="sh" x="-20%" y="-20%" width="140%" height="140%"><feDropShadow dx="0" dy="14" stdDeviation="18" flood-color="#000" flood-opacity="0.32"/></filter>
<filter id="glow" x="-30%" y="-30%" width="160%" height="160%"><feDropShadow dx="0" dy="0" stdDeviation="16" flood-color="{glow}" flood-opacity="{glow_op}"/></filter>
<filter id="dsh" x="-20%" y="-30%" width="140%" height="180%"><feDropShadow dx="0" dy="10" stdDeviation="12" flood-color="#000" flood-opacity="0.38"/></filter>
</defs>
<rect x="100" y="100" width="824" height="824" rx="185" fill="url(#bg)" filter="url(#sh)"{stroke}/>
<rect x="100" y="100" width="824" height="824" rx="185" fill="url(#shine)"/>
<g filter="url(#glow)">{ring_svg}</g>
<g filter="url(#dsh)"><rect x="{dx}" y="{dy}" width="{drive_w}" height="{drive_h}" rx="{rx:.0f}" fill="url(#body)"/></g>
<rect x="{dx}" y="{511}" width="{drive_w}" height="2" fill="{divider}"/>
<circle cx="{lx:.0f}" cy="{q1:.0f}" r="15" fill="{led}"/><circle cx="{lx:.0f}" cy="{q3:.0f}" r="15" fill="{led}"/>
<path d="M{l0:.0f} {q1:.0f}H{l1:.0f}" stroke="{lines[0]}" stroke-width="10" stroke-linecap="round"/>
<path d="M{l0:.0f} {q3:.0f}H{l1:.0f}" stroke="{lines[1]}" stroke-width="10" stroke-linecap="round"/>
</svg>'''

variants = {
 # --- colourways (same shape as the current icon) ---
 "01-midnight-mint": {},
 "02-ocean-blue": dict(bg=("#2F7BFF", "#1440B8"), ring=("#FFFFFF", "#CFE0FF"), glow="#0A2A7A", glow_op=0.35, led="#34D058"),
 "03-daylight": dict(bg=("#FFFFFF", "#E3E8F0"), ring=("#3D8BFF", "#1F5BD8"), glow="#3D8BFF", glow_op=0.25,
                     body=("#3B4456", "#1F2533"), divider="#151A24", led="#4ADE80", lines=("#7C879C", "#6B768A"), shine=0, tile_stroke="#D5DBE5"),
 "04-graphite-amber": dict(bg=("#3A3A3E", "#18181B"), ring=("#FFC24B", "#FF7A1A"), glow="#FF9A2E", glow_op=0.40, led="#FFB020"),
 "05-aurora": dict(bg=("#2A1E5C", "#0E0A24"), ring=("#5EF2FF", "#C46BFF"), glow="#8A7DFF", glow_op=0.50, led="#5EF2FF"),
 "06-forest": dict(bg=("#1F4D3A", "#0B231A"), ring=("#C7F36B", "#5DD39E"), glow="#A6E86B", glow_op=0.35, led="#C7F36B"),
 "07-sunset": dict(bg=("#FF8A5C", "#D6336C"), ring=("#FFFFFF", "#FFE3D6"), glow="#7A1235", glow_op=0.35, led="#34D058"),
 "08-mono": dict(bg=("#1C1C1E", "#000000"), ring=("#FFFFFF", "#BDBDC2"), glow="#FFFFFF", glow_op=0.18, led="#34D058"),
 "09-teal": dict(bg=("#0F766E", "#073B37"), ring=("#7FFFD4", "#38BDF8"), glow="#5EEAD4", glow_op=0.40, led="#7FFFD4"),
 # --- shape variations, midnight/mint ---
 "10-single-loop": dict(style="one"),
 "11-big-drive": dict(drive_w=420, drive_h=190, ring_w=40, r=262),
 "12-thin-ring": dict(ring_w=30, r=250, glow_op=0.55),
 "13-spinner": dict(style="four", ring_w=44),
}
for name, kw in variants.items():
    open(f"{name}.svg", "w").write(icon(**kw))
print(" ".join(variants))
