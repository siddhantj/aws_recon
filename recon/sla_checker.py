import json
from datetime import date
from datetime import datetime
import boto3

dataexchange = boto3.client(service_name='dataexchange', region_name='us-east-1')
s3 = boto3.client( service_name='s3', region_name='us-east-1' )
sns = boto3.client(service_name='sns', region_name='us-east-1')

dataset_id='aae4c2cd145a48454f9369d4a4db5c66'

bucket = 'datas3bucket20210316032041795700000001'
destination_path = 'adx-cpi/aae4c2cd145a48454f9369d4a4db5c66/'

threshold_time = 300

def send_email(*,DataSetId, RevisionId, DeltaTime):
    topic_arn = 'arn:aws:sns:us-east-1:304289345267:dev_heartbeat_slafailure'
    message = 'SLA violation for heartbeat by {}'.format(DeltaTime)
    subject = 'SLA violated'
    sns.publish(TopicArn=topic_arn, Message=message, Subject=subject)
    print('Sending email')

def lambda_handler(event, context):
    # print('Recon function: {}'.format(event))
    # print('Context: {}'.format(context))
    response = dataexchange.list_data_set_revisions(DataSetId='aae4c2cd145a48454f9369d4a4db5c66', MaxResults=10)
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
                print("S3 store time: {}".format(s3_store_time))
                delta = s3_store_time - created_date_adx
                print('Delta in seconds: {}'.format(delta.total_seconds()))
                if delta.total_seconds() >= threshold_time:
                    # Send email to notifier
                    send_email(DataSetId=dataset_id, RevisionId=revision_id, DeltaTime=delta.total_seconds())



    return {
        'statusCode': 200,
        'body': json.dumps('response')
    }


