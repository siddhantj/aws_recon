terraform {
  required_providers {
    aws = {
      version =  ">= 3.38"
      source = "hashicorp/aws"
    }
  }
}

provider "aws" {
  region  = "us-east-1"
}

