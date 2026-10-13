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

variable "instance_type" {
  description = "EC2 instance type for the single-node Kubernetes (K3s) server (replaces the original 4-instance setup)"
  type        = string
  default     = "t3.large"
}

variable "volume_size" {
  description = "Root EBS gp3 volume size in GB for the single-node server"
  type        = number
  default     = 40
}

variable "ssh_cidr_blocks" {
  description = "Allowed CIDR blocks for SSH access (port 22)"
  type        = list(string)
  default     = ["0.0.0.0/0"]
}
