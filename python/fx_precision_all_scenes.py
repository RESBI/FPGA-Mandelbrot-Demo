SCENES = [
    ("fast escape @128", (1.0, 1.0), "0.002", 128),
    ("standard @64",     (-0.5, 0.0), "0.002", 64),
    ("Seahorse @512",    (-0.743643887037151, 0.13182590420533), "5e-6", 512),
    ("deep tendrils @8192", (-0.77568377, 0.13646737), "1e-9", 8192),
    ("deep minibrot @8192", (-1.25066, 0.02012), "1e-9", 8192),
    ("deep Seahorse @1024", (-0.743643887037151, 0.13182590420533), "1e-8", 1024),
]

def iter_fp(cre, cim, max_iter):
    zr, zi = 0.0, 0.0
    for i in range(max_iter):
        zr2 = zr*zr; zi2 = zi*zi
        if zr2 + zi2 > 4.0: return i
        zi = 2.0*zr*zi + cim
        zr = zr2 - zi2 + cre
    return max_iter

def iter_fx(cre_i, cim_i, max_iter, F, W):
    mask = (1 << W) - 1
    signbit = 1 << (W - 1)
    ext = 1 << W
    def s(v):
        v &= mask
        return v - ext if v & signbit else v
    zr = 0; zi = 0
    four = 4 << F
    for i in range(max_iter):
        zr2 = s((s(zr) * s(zr)) >> F)
        zi2 = s((s(zi) * s(zi)) >> F)
        if s(zr2 + zi2) > four: return i
        cross = s(2 * s((s(zr) * s(zi)) >> F))
        zi = s(cross + cim_i)
        zr = s(zr2 - zi2 + cre_i)
    return max_iter

def to_fx(v, F):
    return int(round(v * (1 << F)))

for INT_BITS, F, W, label in [(8,40,48,"Q8.40/48-bit"), (8,48,56,"Q8.48/56-bit"), (8,55,64,"Q8.55/64-bit")]:
    print(f"\n=== {label}  (range +-{2**(INT_BITS-1)}, res 2^-{F} = {2.0**-F:.3e}) ===")
    for name, center, step, max_iter in SCENES:
        step_f = float(step)
        total = 0; mismatch = 0; maxdiff = 0
        for dy in range(-3, 4):
            for dx in range(-3, 4):
                cre = center[0] + dx * step_f
                cim = center[1] + dy * step_f
                i_fp = iter_fp(cre, cim, max_iter)
                i_fx = iter_fx(to_fx(cre, F), to_fx(cim, F), max_iter, F, W)
                total += 1
                if i_fp != i_fx:
                    mismatch += 1
                    maxdiff = max(maxdiff, abs(i_fp - i_fx))
        pct = 100.0 * (total - mismatch) / total
        print(f"  {name:28s}  match={total-mismatch}/{total} ({pct:.2f}%)  maxdiff={maxdiff}")
