#!/usr/bin/env python3
"""
Generate realistic log entries and push them directly to Loki.

Usage:
    python scripts/generate_loki_logs.py [--count N] [--include-errors]

This pushes logs directly to the Loki HTTP API, bypassing the grocery API.
Use this when you need log data in Loki for SRE Agent testing.
"""

import argparse
import json
import random
import time
import urllib.request

LOKI_URL = "https://ca-loki.icymeadow-96da5d2b.eastus2.azurecontainerapps.io"
PUSH_ENDPOINT = f"{LOKI_URL}/loki/api/v1/push"

PRODUCTS = [
    ("PROD001", "Organic Bananas"),
    ("PROD002", "Whole Milk"),
    ("PROD003", "Sourdough Bread"),
    ("PROD004", "Free-Range Eggs"),
    ("PROD005", "Avocados"),
    ("PROD006", "Ground Coffee"),
    ("PROD007", "Chicken Breast"),
    ("PROD008", "Greek Yogurt"),
]


def nano_ts():
    """Current time in nanoseconds as a string."""
    return str(int(time.time() * 1e9))


def make_info_log():
    """Generate a normal operational log entry."""
    pid, pname = random.choice(PRODUCTS)
    templates = [
        {
            "event": "inventory_check_success",
            "productId": pid,
            "productName": pname,
            "quantityAvailable": random.randint(10, 100),
            "message": f"Inventory check succeeded for {pname}",
        },
        {
            "event": "products_list_requested",
            "count": 8,
            "message": "Product catalog requested",
        },
        {
            "event": "order_placed",
            "productId": pid,
            "productName": pname,
            "quantity": random.randint(1, 5),
            "message": f"Order placed for {pname}",
        },
        {
            "event": "health_check",
            "status": "healthy",
            "message": "Health check passed",
        },
    ]
    return "info", random.choice(templates)


def make_warn_log():
    """Generate a warning log entry."""
    pid, pname = random.choice(PRODUCTS)
    templates = [
        {
            "event": "high_latency_detected",
            "productId": pid,
            "duration": random.randint(800, 2000),
            "message": f"High latency on inventory check for {pname}",
        },
        {
            "event": "supplier_slow_response",
            "supplier": "FreshFoods Wholesale API",
            "duration": random.randint(1500, 3000),
            "message": "Supplier API response time elevated",
        },
    ]
    return "warn", random.choice(templates)


def make_error_log():
    """Generate a rate-limit error log entry (the scenario SRE Agent investigates)."""
    pid, pname = random.choice(PRODUCTS)
    req_count = random.randint(11, 25)
    templates = [
        {
            "event": "supplier_rate_limit_exceeded",
            "productId": pid,
            "supplier": "FreshFoods Wholesale API",
            "requestCount": req_count,
            "limit": 10,
            "retryAfter": random.randint(30, 60),
            "errorCode": "SUPPLIER_RATE_LIMIT_429",
            "statusCode": 429,
            "message": f"FreshFoods Wholesale API rate limit exceeded",
        },
        {
            "event": "inventory_check_failed",
            "productId": pid,
            "productName": pname,
            "reason": "supplier_rate_limit",
            "errorCode": "SUPPLIER_RATE_LIMIT_429",
            "supplier": "FreshFoods Wholesale API",
            "retryAfter": random.randint(30, 60),
            "statusCode": 429,
            "message": f"Unable to check inventory for {pname} - supplier rate limited",
        },
    ]
    return "error", random.choice(templates)


def push_to_loki(level, log_obj):
    """Push a single log entry to Loki."""
    ts = nano_ts()
    log_obj["level"] = level
    log_obj["time"] = time.strftime("%Y-%m-%dT%H:%M:%S.000Z", time.gmtime())

    payload = {
        "streams": [
            {
                "stream": {
                    "app": "grocery-api",
                    "level": level,
                    "job": "grocery-api",
                    "environment": "production",
                },
                "values": [[ts, json.dumps(log_obj)]],
            }
        ]
    }

    data = json.dumps(payload).encode("utf-8")
    req = urllib.request.Request(
        PUSH_ENDPOINT,
        data=data,
        headers={"Content-Type": "application/json"},
        method="POST",
    )
    try:
        with urllib.request.urlopen(req, timeout=10) as resp:
            return resp.status
    except Exception as e:
        print(f"  ERROR pushing to Loki: {e}")
        return None


def main():
    parser = argparse.ArgumentParser(description="Generate Loki log entries")
    parser.add_argument(
        "--count", type=int, default=50, help="Total number of log entries (default: 50)"
    )
    parser.add_argument(
        "--include-errors",
        action="store_true",
        default=True,
        help="Include rate-limit error entries (default: True)",
    )
    parser.add_argument(
        "--errors-only",
        action="store_true",
        help="Only generate error entries",
    )
    args = parser.parse_args()

    print(f"Pushing {args.count} log entries to Loki at {LOKI_URL}")
    print()

    ok = 0
    fail = 0

    for i in range(args.count):
        if args.errors_only:
            level, log_obj = make_error_log()
        else:
            roll = random.random()
            if roll < 0.60:
                level, log_obj = make_info_log()
            elif roll < 0.80:
                level, log_obj = make_warn_log()
            else:
                level, log_obj = make_error_log()

        status = push_to_loki(level, log_obj)
        symbol = "." if status in (200, 204) else "X"
        print(symbol, end="", flush=True)

        if status in (200, 204):
            ok += 1
        else:
            fail += 1

        # Small delay to spread out timestamps
        time.sleep(0.1)

    print()
    print(f"\nDone: {ok} succeeded, {fail} failed out of {args.count}")
    print(f"\nLog mix: ~60% info, ~20% warn, ~20% errors (rate limit 429s)")
    if args.errors_only:
        print("(errors-only mode was used)")


if __name__ == "__main__":
    main()
