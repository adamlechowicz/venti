#!/usr/bin/env python3
"""
Fetch carbon intensity data from Electricity Maps API and update Thresholds.json.

For each zone currently set to the placeholder value (1200), queries the API
for the latest carbon intensity and estimates a peak threshold using a multiplier.

Usage:
    python3 scripts/fetch_thresholds.py --api-key YOUR_API_KEY [--multiplier 1.5] [--dry-run]
"""

import argparse
import json
import os
import subprocess
import time

THRESHOLDS_PATH = os.path.join(
    os.path.dirname(__file__), "..", "Venti", "Venti", "Resources", "Thresholds.json"
)
PLACEHOLDER = 1200
API_BASE = "https://api.electricitymaps.com/v3"
RATE_LIMIT_DELAY = 1.5  # seconds between requests to avoid rate limiting


def get_latest_intensity(api_key: str, zone: str) -> int | None:
    """Fetch the latest carbon intensity for a zone. Returns None if unavailable."""
    result = subprocess.run(
        [
            "curl", "-s", "-w", "\n%{http_code}",
            f"{API_BASE}/carbon-intensity/latest?zone={zone}",
            "-H", f"auth-token: {api_key}",
        ],
        capture_output=True,
        text=True,
    )
    lines = result.stdout.strip().rsplit("\n", 1)
    if len(lines) != 2:
        return None

    body, status = lines
    status = int(status)

    if status == 429:
        print("rate limited, waiting 10s...", end=" ", flush=True)
        time.sleep(10)
        return get_latest_intensity(api_key, zone)

    if status != 200:
        return None

    try:
        data = json.loads(body)
        intensity = data.get("carbonIntensity")
        if intensity is not None:
            return int(intensity)
    except (json.JSONDecodeError, ValueError):
        pass

    return None


def main():
    parser = argparse.ArgumentParser(description="Update Thresholds.json from Electricity Maps API")
    parser.add_argument("--api-key", required=True, help="Electricity Maps API key")
    parser.add_argument(
        "--multiplier",
        type=float,
        default=1.5,
        help="Multiplier to estimate peak monthly average from latest intensity (default: 1.5)",
    )
    parser.add_argument("--dry-run", action="store_true", help="Print changes without writing")
    args = parser.parse_args()

    # Load current thresholds
    with open(THRESHOLDS_PATH) as f:
        thresholds = json.load(f)

    # Find placeholder zones
    placeholder_zones = [z for z, v in thresholds.items() if v == PLACEHOLDER and z != "DEF"]
    print(f"Found {len(placeholder_zones)} zones with placeholder value ({PLACEHOLDER})")

    # Query each placeholder zone
    updated = 0
    skipped = 0

    for i, zone in enumerate(sorted(placeholder_zones)):
        print(f"  [{i+1}/{len(placeholder_zones)}] {zone}...", end=" ", flush=True)
        intensity = get_latest_intensity(args.api_key, zone)

        if intensity is not None and intensity > 0:
            threshold = int(round(intensity * args.multiplier))
            # Clamp to reasonable range
            threshold = max(threshold, 20)
            threshold = min(threshold, 1200)
            print(f"intensity={intensity}, threshold={threshold}")
            thresholds[zone] = threshold
            updated += 1
        else:
            print("no data")
            skipped += 1

        time.sleep(RATE_LIMIT_DELAY)

    print(f"\nResults: {updated} updated, {skipped} no data")

    if args.dry_run:
        print("\nDry run — not writing changes.")
        changes = {z: thresholds[z] for z in sorted(placeholder_zones) if thresholds[z] != PLACEHOLDER}
        if changes:
            print(f"\nSample changes (showing first 20):")
            for z, v in list(changes.items())[:20]:
                print(f"  {z}: {PLACEHOLDER} -> {v}")
    else:
        with open(THRESHOLDS_PATH, "w") as f:
            json.dump(thresholds, f, indent=2)
            f.write("\n")
        print(f"\nWrote updated thresholds to {THRESHOLDS_PATH}")


if __name__ == "__main__":
    main()
