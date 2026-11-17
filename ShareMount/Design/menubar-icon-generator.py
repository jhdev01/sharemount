import math
def tray(alert=False):
    c, r, w = 9.0, 7.0, 1.7          # 18x18 pt canvas: centre, ring radius, stroke
    def pt(a, rad=r): t = math.radians(a); return c + rad*math.cos(t), c + rad*math.sin(t)
    def arc(a0, a1):
        (x0, y0), (x1, y1) = pt(a0), pt(a1)
        return f"M{x0:.3f} {y0:.3f} A{r} {r} 0 0 1 {x1:.3f} {y1:.3f}"
    def head(a, length=3.4, half=2.1):
        t = math.radians(a); ex, ey = pt(a)
        tx, ty = -math.sin(t), math.cos(t); nx, ny = math.cos(t), math.sin(t)
        return (f"M{ex+tx*length:.3f} {ey+ty*length:.3f} L{ex+nx*half:.3f} {ey+ny*half:.3f} "
                f"L{ex-nx*half:.3f} {ey-ny*half:.3f} Z")
    # Drive: solid rounded rect with two LED dots and a divider knocked out.
    dw, dh = 8.0, 4.4; dx, dy = c - dw/2, c - dh/2
    mask_badge = ""
    badge = ""
    if alert:
        # Badge bottom-right with a transparent gap around it so it reads at 18 px.
        mask_badge = '<circle cx="15" cy="14.6" r="3.7" fill="black"/>'
        badge = '<circle cx="15" cy="14.6" r="2.6" fill="black"/>'
    return f'''<svg xmlns="http://www.w3.org/2000/svg" width="18" height="18" viewBox="0 0 18 18">
<defs><mask id="m" maskUnits="userSpaceOnUse" x="0" y="0" width="18" height="18">
<rect width="18" height="18" fill="white"/>{mask_badge}</mask>
<mask id="d" maskUnits="userSpaceOnUse" x="0" y="0" width="18" height="18">
<rect width="18" height="18" fill="white"/>
<rect x="{dx}" y="{c-0.3}" width="{dw}" height="0.6" fill="black"/>
<circle cx="{dx+1.5}" cy="{c-1.2}" r="0.65" fill="black"/>
<circle cx="{dx+1.5}" cy="{c+1.2}" r="0.65" fill="black"/>
</mask></defs>
<g mask="url(#m)" fill="black">
<path d="{arc(206, 316)}" fill="none" stroke="black" stroke-width="{w}" stroke-linecap="round"/>
<path d="{head(316)}"/>
<path d="{arc(26, 136)}" fill="none" stroke="black" stroke-width="{w}" stroke-linecap="round"/>
<path d="{head(136)}"/>
<rect x="{dx}" y="{dy}" width="{dw}" height="{dh}" rx="1.3" mask="url(#d)"/>
</g>{badge}
</svg>'''
open('tray.svg','w').write(tray()); open('tray-alert.svg','w').write(tray(True))
