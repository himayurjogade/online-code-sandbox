terraform {
  backend "s3" {
    bucket       = "online-code-sandbox-tfstate-091199627080"
    key          = "prod/terraform.tfstate"
    region       = "ap-south-1"
    use_lockfile = true
    encrypt      = true
  }
}
