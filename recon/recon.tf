resource "aws_cloudwatch_event_rule" "heartbeat_recon_event" {
  name                      = "heartbeat_recon_event"
  description               = "Generate event every 5 min to check for SLA violation for heartbeat dataset"
  schedule_expression       = "rate(5 minutes)"
  tags                      = "heartbeat_recon" #${env}_heartbeat_recon
}

resource "aws_cloudwatch_event_target" "target_heartbeat_recon_lambda" {
  rule      = aws_cloudwatch_event_rule.heartbeat_recon_event
  target_id = "SendToHeartBeatReconLambda"
  arn       = aws_lambda_function.heartbeat_recon_lambda
}

# Lambda related resources
data "archive_file" "heartbeat_recon_lambda_zip" {
  type             = "zip"
  source_file      = "${path.module}/heartbeat_recon/src/heartbeat_recon_lambda"
  output_file_mode = "0666"
  output_path      = "${path.module}/heartbeat_recon/src/heartbeat_recon_lambda.zip"
}

# Create Lambda Execution Role
resource "aws_iam_role" "heartbeat_recon_role" {
  name = "heartbeat_recon_role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Principal = {
          Service = "lambda.amazonaws.com"
        },
        Action = "sts:AssumeRole",
        Sid = "Assumed role by heartbeat lambda fxn"
      }
    ]
  })
}

resource "aws_iam_role_policy" "heartbeat_recon_lambda_role_policy" {
  name = "heartbeat_recon_role_policy"
  role = aws_iam_role.heartbeat_recon_role.id
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "dataexchange:GetJob",
          "dataexchange:ListRevisionAssets",
          "dataexchange:GetAsset",
          "dataexchange:GetRevision",
          "dataexchange:ListDataSetRevisions"
        ]
        Resource = "arn:aws:dataexchange:us-east-1::data-sets/aae4c2cd145a48454f9369d4a4db5c66" # use * if this doesn't work
      },
      {
        Effect   = "Allow",
        Action   = "s3:GetObject",
        Resource = "arn:aws:s3:::*aws-data-exchange*"
        Condition = {
          "ForAnyValue:StringEquals" = {
            "aws:CalledVia" = [
              "dataexchange.amazonaws.com"
            ]
          }
        }
      },
      {
        Effect   = "Allow",
        Action   = "sns:PublishMessage",
        Resource = aws_sns_topic.heartbeat_recon_topic.arn #  TODO replace with SNS topic
      },
      {
        Effect = "Allow",
        Action = [
          "s3:GetObject",
          "s3:ListBucket"
        ],
        Resource = [
          "arn:aws:s3:::datas3bucket20210316032041795700000001",
          join("", ["arn:aws:s3:::datas3bucket20210316032041795700000001", "/*"]) # TODO replace with actual bucket identifier
        ]
      }
    ]
  })
}


resource "aws_iam_role_policy_attachment" "heartbeat_recon_role_policy_attachment" {
  role       = aws_iam_role.heartbeat_recon_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_lambda_function" "heartbeat_recon_lambda" {
  function_name                   = "heartbeat_recon_lambda"
  handler                         =  "heartbeat_recon_lambda.lambda_handler"
  runtime                         = "python3.7"
  role                            = aws_iam_role.heartbeat_recon_role.arn
  memory_size                     = 256
  timeout                         = 300
  reserved_concurrent_executions  = 1
  # vpc_config TODO need to add
  filename                        = data.archive_file.heartbeat_recon_lambda_zip.output_path
  source_code_hash                = data.archive_file.heartbeat_recon_lambda_zip.output_base64sha256
  tags                            = {"lambda" : "heartbeat_recon_lambda"}
}

# Cloudwatch event will trigger lambda function
resource "aws_lambda_event_source_mapping" "s3ExportLambdaTrigger" {
  event_source_arn = aws_cloudwatch_event_rule.heartbeat_recon_event.arn
  function_name    = aws_lambda_function.heartbeat_recon_lambda.function_name
}

resource "aws_sns_topic" "heartbeat_recon_topic" {
  name              = "heartbeat_recon_topic"
}

resource "aws_sns_topic_policy" "heartbeat_recon_policy" {
  arn               = aws_sns_topic.heartbeat_recon_topic.arn
  policy            = data.aws_iam_policy_document.heartbeat_recon_policy_doc.json
}

data "aws_iam_policy_document" "heartbeat_recon_policy_doc_1" {
  policy_id = "__default_policy_ID"
  statement {
    actions = [
      "SNS:Receive",
      "SNS:Publish",
      "SNS:ListSubscriptionsByTopic",
      "SNS:GetTopicAttributes"
    ]
    effect = "Allow"
    principals {
      type        = "AWS"
      identifiers = [aws_lambda_function.heartbeat_recon_lambda.arn]
    }
    resources = [
      aws_sns_topic.heartbeat_recon_topic.arn,
    ]
    sid = "Policy document for heartbeat_recon_topic in regards to lambda"
  }
}

data "aws_iam_policy_document" "heartbeat_recon_policy_doc_2" {
  policy_id = "__default_policy_ID"
  statement {
    actions = [
      "SNS:Subscribe"
    ]
    effect = "Allow"
    resources = ["*"]
    condition {
      test = "StringLike"
      values = ["*@gs.com"]
      variable = "sns:endpoint"
    }
    condition {
      test = "StringEquals"
      values = ["email"]
      variable = "sns:Protocol"
    }
    sid = "Policy document for heartbeat_recon_topic to subscribe to email"
  }
}

data "aws_iam_policy_document" "heartbeat_recon_policy_doc" {
  source_policy_documents = [
    data.aws_iam_policy_document.heartbeat_recon_policy_doc_1.json,
    data.aws_iam_policy_document.heartbeat_recon_policy_doc_2.json
  ]
}

resource "aws_sns_topic_subscription" "heartbeat_recon_failure_email" {
  topic_arn = aws_sns_topic.heartbeat_recon_topic.arn
  protocol = "email"
  endpoint = "siddhantjawa18@gmail.com"
}

# difference between "aws_iam_policy_document" and "aws_iam_role_policy"