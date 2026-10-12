variable "aws_region" {
  description = "The AWS region to deploy to"
  type        = string
  default     = "ap-south-1"
}

variable "key_name" {
  description = "Name of an existing EC2 KeyPair to enable SSH access. Must exist in the selected AWS region."
  type        = string
  default     = "builder_key"
}

variable "instance_type_api" {
  description = "EC2 instance type for the API and Redis nodes"
  type        = string
  default     = "t3.small"
}

variable "instance_type_worker" {
  description = "EC2 instance type for the Worker nodes (requires more RAM for Docker-in-Docker)"
  type        = string
  default     = "t3.small"
}

variable "worker_count" {
  description = "Number of worker nodes to provision"
  type        = number
  default     = 2
}
