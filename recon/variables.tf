variable region {
  default = "us-east-1"
  description = "Region where the resources will be deployed"
}

variable failure_threshold_time {
  default = 5
  description = "failure threshold time in minutes"
}

variable "dataset_id" {
  default = "aae4c2cd145a48454f9369d4a4db5c66"
  description = "AWS Heartbeat dataset id"
}