#!/usr/bin/env python3
import csv, random, os, datetime

random.seed(42)
CATEGORIES = {
    "Electronics": [f"P{i:04d}" for i in range(1, 101)],
    "Automotive": [f"P{i:04d}" for i in range(101, 201)],
    "Pharma": [f"P{i:04d}" for i in range(201, 301)],
    "FMCG": [f"P{i:04d}" for i in range(301, 401)],
    "Industrial": [f"P{i:04d}" for i in range(401, 501)],
}
WAREHOUSES = [f"WH{i:02d}" for i in range(1, 11)]
CHANNELS = ["B2B_EDI", "POS_FEED", "ECOMMERCE", "DISTRIBUTOR", "PARTNER_API"]
BASE_DT = datetime.datetime(2026, 5, 12, 0, 0, 0)

out_dir = "/tmp/demand_realtime"
os.makedirs(out_dir, exist_ok=True)

for batch in range(5):
    fname = f"demand_{BASE_DT.strftime('%Y%m%d')}_{batch:03d}.csv"
    with open(os.path.join(out_dir, fname), "w", newline="") as f:
        w = csv.writer(f)
        w.writerow(["PRODUCT_ID", "WAREHOUSE_ID", "DEMAND_DATE", "UNITS_SOLD", "CHANNEL", "INGESTED_AT"])
        for _ in range(100):
            cat = random.choice(list(CATEGORIES.keys()))
            pid = random.choice(CATEGORIES[cat])
            wh = random.choice(WAREHOUSES)
            units = random.randint(5, 500) if cat != "Electronics" else random.randint(50, 2000)
            channel = random.choice(CHANNELS)
            ts = BASE_DT + datetime.timedelta(minutes=random.randint(0, 1440), seconds=random.randint(0, 59))
            w.writerow([pid, wh, ts.strftime("%Y-%m-%d"), units, channel, ts.strftime("%Y-%m-%d %H:%M:%S")])

print(f"Generated 5 files × 100 rows = 500 rows in {out_dir}")
