variable "aws_region" {
  default = "eu-west-1"
}

provider "aws" {
  region = var.aws_region
}



data "archive_file" "lambda_zip" {
  type        = "zip"
  source_file = "index.js"
  output_path = "lambda_function.zip"
}

resource "aws_lambda_function" "lambda" {
  filename         = "lambda_function.zip"
  function_name    = "test_lambda"
  role             = aws_iam_role.iam_for_lambda_tf.arn
  handler          = "index.handler"
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256
  runtime          = "nodejs12.x"
}

resource "aws_iam_role" "iam_for_lambda_tf" {
  name = "iam_for_lambda_tf"
  assume_role_policy = file("assumerolepolicy.json")
}

resource "aws_iam_policy" "policy" {
  name        = "test-policy"
  description = "A test policy"
  policy      = file("sns-policy.json")
}

resource "aws_iam_policy_attachment" "test-attach" {
  name       = "test-attachment"
  roles      = [aws_iam_role.iam_for_lambda_tf.name]
  policy_arn = aws_iam_policy.policy.arn
}

/*
resource "random_id" "id" {
	byte_length = 8
}*/

# HTTP API
resource "aws_apigatewayv2_api" "api" {
	#name          = "api-${random_id.id.hex}"
	name          = "api-sholay20"
	protocol_type = "HTTP"
	target        = aws_lambda_function.lambda.arn
}

# Permission
resource "aws_lambda_permission" "apigw" {
	action        = "lambda:InvokeFunction"
	function_name = aws_lambda_function.lambda.arn
	principal     = "apigateway.amazonaws.com"

	source_arn = "${aws_apigatewayv2_api.api.execution_arn}/*/*"
}

resource "aws_lambda_permission" "with_sns" {
    statement_id = "AllowExecutionFromSNS"
    action = "lambda:InvokeFunction"
    function_name = aws_lambda_function.lambda.arn
    principal = "sns.amazonaws.com"
    source_arn = aws_sns_topic.my-test-alarm.arn
}



resource "aws_sns_topic" "my-test-alarm" {
  name = "my-test-alarms-topic"

  delivery_policy = <<EOF
{
  "http": {
    "defaultHealthyRetryPolicy": {
      "minDelayTarget": 20,
      "maxDelayTarget": 20,
      "numRetries": 3,
      "numMaxDelayRetries": 0,
      "numNoDelayRetries": 0,
      "numMinDelayRetries": 0,
      "backoffFunction": "linear"
    },
    "disableSubscriptionOverrides": false,
    "defaultThrottlePolicy": {
      "maxReceivesPerSecond": 1
    }
  }
}
EOF

  provisioner "local-exec" {
    command = "aws sns subscribe --topic-arn ${self.arn} --protocol email --notification-endpoint ${var.alarms_email}"
    #command = "aws sns subscribe --topic-arn   arn:aws:sns:eu-west-1:871994821053:my-test-alarms-topic --protocol email --notification-endpoint ${var.alarms_email}"
  }
}

resource "aws_lambda_function_event_invoke_config" "example" {
  function_name = aws_lambda_function.lambda.arn
  destination_config {
    on_failure {
      destination = aws_sns_topic.my-test-alarm.arn
    }
    on_success {
      destination = aws_sns_topic.my-test-alarm.arn
    }
  }
}