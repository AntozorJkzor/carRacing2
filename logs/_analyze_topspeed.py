import csv
from collections import Counter, defaultdict
from pathlib import Path

p = Path(r"c:\Users\anton\Documents\GitHub\carRacing2\logs\car_telemetry_2026-07-14_15-03-38.csv")
rows = list(csv.DictReader(p.open(encoding="utf-8")))
print("rows", len(rows), "t", rows[0]["t"], "->", rows[-1]["t"])


def f(r, k):
	return float(r[k])


print("maxkmh", round(max(f(r, "kmh") for r in rows), 2), "maxrpm", round(max(f(r, "rpm") for r in rows), 1))
print("gears", dict(Counter(r["gear"] for r in rows)))

by_gear = defaultdict(list)
for r in rows:
	if f(r, "thr") < 0.4:
		continue
	by_gear[int(r["gear"])].append(r)

print("\nper-gear WOT:")
for g in sorted(by_gear):
	rs = by_gear[g]
	kmhs = [f(r, "kmh") for r in rs]
	rpms = [f(r, "rpm") for r in rs]
	tq = [f(r, "eng_tq") for r in rs]
	drv = [f(r, "driveline") for r in rs]
	eff = [f(r, "eff_thr") for r in rs]
	print(
		"  G%d n=%d kmh %.0f-%.0f (avg %.0f) rpm %.0f-%.0f eng_tq avg %.0f driveline avg %.0f lim_cut=%d"
		% (
			g,
			len(rs),
			min(kmhs),
			max(kmhs),
			sum(kmhs) / len(kmhs),
			min(rpms),
			max(rpms),
			sum(tq) / len(tq),
			sum(drv) / len(drv),
			sum(1 for e in eff if e < 0.05),
		)
	)

prev = None
print("\nshifts:")
for r in rows:
	g = int(r["gear"])
	if prev is not None and g != prev and g > 0 and prev > 0:
		print(
			"  %d->%d t=%.2f kmh=%.1f rpm=%.0f eng_tq=%.0f driveline=%.0f"
			% (prev, g, f(r, "t"), f(r, "kmh"), f(r, "rpm"), f(r, "eng_tq"), f(r, "driveline"))
		)
	prev = g

peak = max(f(r, "kmh") for r in rows)
plateau = [r for r in rows if f(r, "kmh") > peak * 0.95 and f(r, "thr") > 0.5]
print("\npeak", round(peak, 1), "plateau", len(plateau))
if plateau:
	# average plateau
	def avg(key):
		return sum(f(r, key) for r in plateau) / len(plateau)

	print(
		"plateau avg gear=%.1f kmh=%.1f rpm=%.0f eng_tq=%.0f driveline=%.0f clutch=%.2f slip_w=%.0f rear_k=%.2f eff=%.2f"
		% (
			avg("gear"),
			avg("kmh"),
			avg("rpm"),
			avg("eng_tq"),
			avg("driveline"),
			avg("clutch"),
			avg("clutch_slip_w"),
			avg("rear_k_avg"),
			avg("eff_thr"),
		)
	)
	r = plateau[len(plateau) // 2]
	# acceleration estimate from nearby points
	print(
		"sample t=%.2f gear=%s kmh=%.1f rpm=%.0f ax=%.2f az=%.2f vx=%.2f vz=%.2f"
		% (f(r, "t"), r["gear"], f(r, "kmh"), f(r, "rpm"), f(r, "ax_body"), f(r, "az_body"), f(r, "vx_body"), f(r, "vz_body"))
	)

# Aero power at peak with defaults Cd=0.32 A=2.1 rho=1.225
v = peak / 3.6
q = 0.5 * 1.225 * v * v
F_drag = 0.32 * 2.1 * q
P_drag = F_drag * v / 1000.0
print("\naero@peak: v=%.1fm/s Fd=%.0fN P_drag=%.1fkW (%.0fhp)" % (v, F_drag, P_drag, P_drag / 0.7457))

# Wheel force proxy: driveline / radius (approx 0.2)
if plateau:
	drv = avg("driveline")
	F_wheel = abs(drv) / 0.2
	print("wheel force from driveline (~r=0.2): Fd_wheel=%.0fN vs aero %.0fN  ratio=%.2f" % (F_wheel, F_drag, F_wheel / max(F_drag, 1)))

# Accel while in each gear late: look at kmh slope
print("\naccel approx (high thr):")
for g in sorted(by_gear):
	rs = by_gear[g]
	if len(rs) < 10:
		continue
	# use first/last third
	a = rs[: max(3, len(rs) // 4)]
	b = rs[-max(3, len(rs) // 4) :]
	dt = f(b[-1], "t") - f(a[0], "t")
	if dt < 0.05:
		continue
	dk = f(b[-1], "kmh") - f(a[0], "kmh")
	print("  G%d dkmh/dt ≈ %.1f km/h/s  (over %.1fs)" % (g, dk / dt, dt))
