import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from publish_demand import make_event
from setup_aws import firehose_request, ident, names


class SetupAwsTests(unittest.TestCase):
    def test_names_are_scoped_to_prefix_account_region(self):
        n = names('sg-manufacturing-demand', '123456789012', 'us-west-2')
        self.assertEqual(n['bucket'], 'sg-manufacturing-demand-123456789012-us-west-2')
        self.assertEqual(n['storage_int'], 'SG_MANUFACTURING_DEMAND_S3_INT')
        self.assertEqual(n['firehose_stream'], 'sg-manufacturing-demand-orderlines')

    def test_rejects_unsafe_identifiers(self):
        for bad in ['DB; DROP', 'a-b', '1abc', '']:
            with self.assertRaises(ValueError):
                ident(bad)

    def test_firehose_request_matches_aws_schema(self):
        import botocore.session
        from botocore.validate import validate_parameters
        n = names('sg-manufacturing-demand', '123456789012', 'us-west-2')
        req = firehose_request(n, n['bucket'], 'arn:aws:iam::123456789012:role/sg-manufacturing-demand-firehose-s3')
        model = botocore.session.get_session().get_service_model('firehose')
        validate_parameters(req, model.operation_model('CreateDeliveryStream').input_shape)
        dest = req['ExtendedS3DestinationConfiguration']
        self.assertEqual(dest['Prefix'], 'demand/')
        self.assertFalse(dest['ErrorOutputPrefix'].startswith('demand/'))

    def test_demand_event_matches_pipe_columns(self):
        import random
        event = make_event(random.Random(7))
        self.assertEqual(set(event), {'item_id', 'event_ts', 'order_value_sgd', 'requested_lead_hrs', 'status', 'sent_ms'})
        self.assertRegex(event['item_id'], r'^PLN-00[0-3]\d$')
        self.assertIn(event['status'], ('EXCEPTION', 'OK'))


    def test_put_record_batch_matches_botocore_schema(self):
        import json
        import random
        import botocore.session
        from botocore.validate import validate_parameters
        rng = random.Random(11)
        req = {'DeliveryStreamName': names('sg-manufacturing-demand', '123456789012', 'us-west-2')['firehose_stream'],
               'Records': [{'Data': (json.dumps(make_event(rng)) + '\n').encode()} for _ in range(3)]}
        model = botocore.session.get_session().get_service_model('firehose')
        validate_parameters(req, model.operation_model('PutRecordBatch').input_shape)


if __name__ == '__main__':
    unittest.main()
