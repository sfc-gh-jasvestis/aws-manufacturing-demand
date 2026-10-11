"""Publish simulated partner order-line (demand) events to Amazon Data Firehose (stream <prefix>-demand).

Firehose batches the records into S3 (demand/); Snowpipe loads them into RAW.LIVE_DEMAND.
Planning item IDs come from RAW.PLANNING_ITEMS (PLN-0000..PLN-0039). Values are seeded random.
"""
import argparse
import json
import random
import time
from datetime import datetime, timezone


def make_event(rng):
    exception = rng.random() < 0.1
    return {'item_id': f'PLN-{rng.randint(0, 39):04d}',
            'event_ts': datetime.now(timezone.utc).strftime('%Y-%m-%dT%H:%M:%S.%f')[:-3],
            'order_value_sgd': round((5700 if exception else 1900) * rng.lognormvariate(0, 0.5)),
            'requested_lead_hrs': round((14 if exception else 96) * rng.lognormvariate(0, 0.4)),
            'status': 'EXCEPTION' if exception else 'OK',
            'sent_ms': int(time.time() * 1000)}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--region', default='us-west-2')
    ap.add_argument('--prefix', default='sg-manufacturing-demand')
    ap.add_argument('--count', type=int, default=40)
    ap.add_argument('--seed', type=int)
    args = ap.parse_args()
    import boto3
    firehose = boto3.client('firehose', region_name=args.region)
    stream = f'{args.prefix}-orderlines'
    rng = random.Random(args.seed)
    records = [{'Data': (json.dumps(make_event(rng)) + '\n').encode()} for _ in range(args.count)]
    for start in range(0, len(records), 500):
        out = firehose.put_record_batch(DeliveryStreamName=stream, Records=records[start:start + 500])
        if out['FailedPutCount']:
            raise RuntimeError(f"{out['FailedPutCount']} records were rejected by Firehose")
    print(f'published {args.count} demand events to Firehose stream {stream}; S3 delivery buffers up to 60 s')


if __name__ == '__main__':
    main()
