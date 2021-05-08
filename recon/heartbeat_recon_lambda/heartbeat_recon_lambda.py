import os
os.environ['AWS_DATA_PATH'] = '/opt/'

import json
from datetime import date
from datetime import datetime
import boto3

bucket = os.environ['S3_BUCKET']
region = os.environ['REGION']
sns_topic_arn = os.environ['SNS_TOPIC_ARN']
failure_threshold_time = float(os.environ['FAILURE_THRESHOLD_TIME']) * 60
dataset_id = os.environ['DATASET_ID']
destination_path = 'adx-cpi/aae4c2cd145a48454f9369d4a4db5c66/'

dataexchange = boto3.client(service_name='dataexchange', region_name=region)
s3 = boto3.client( service_name='s3', region_name=region )
sns = boto3.client(service_name='sns', region_name=region)

def send_email(*,DataSetId, RevisionId, Message):
    topic_arn = sns_topic_arn
    message = Message
    subject = 'SLA violated for dataset_id: {}'.format(DataSetId)
    sns.publish(TopicArn=topic_arn, Message=message, Subject=subject)
    print('Sending email')

def lambda_handler(event, context):
    print('Cron rate event: {}'.format(event))
    sla_failure_msg = '' # Email message
    response = dataexchange.list_data_set_revisions(DataSetId=dataset_id, MaxResults=10)
    revisions = response['Revisions']
    ## get last 5 revisions
    revisions = revisions[-6:]
    for revision in revisions:
        revision_id = revision['Id']
        created_date_adx = revision['CreatedAt']
        print('Revision_id: {}, created_date: {}'.format(revision_id, created_date_adx))
        prefix = destination_path + revision_id
        object_summary = s3.list_objects_v2(Bucket=bucket, Prefix=prefix, MaxKeys=100 )
        contents= object_summary['Contents']
        key_count = object_summary['KeyCount']
        # print("Contents: {}".format(contents))
        # print('KeyCount: {}'.format(key_count))
        if (key_count == len(contents)):
            for content in contents:
                s3_store_time = content['LastModified']
                filename = content['Key'].split("/")[-1]
                print("S3 store time: {}".format(s3_store_time))
                delta = s3_store_time - created_date_adx
                print('Delta in seconds: {}'.format(delta.total_seconds()))
                if delta.total_seconds() < failure_threshold_time:
                    sla_failure_msg = sla_failure_msg + 'revision_id: {}, file: {}, created_datetime: {}, s3_available_datetime:{}, delta:{}sec \n\n'.format(revision_id, filename, created_date_adx, s3_store_time, delta.total_seconds())

    if len(sla_failure_msg) > 0:
                send_email(DataSetId=dataset_id, RevisionId=revision_id, Message = sla_failure_msg)

    return {
        'statusCode': 200,
        'body': json.dumps('response')
    }


