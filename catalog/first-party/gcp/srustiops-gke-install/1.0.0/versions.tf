terraform {
  required_version = ">= 1.10"
  required_providers {
    google     = { source = "hashicorp/google", version = ">= 6.0, < 9.0" }
    kubernetes = { source = "hashicorp/kubernetes", version = ">= 2.30" }
    helm       = { source = "hashicorp/helm", version = ">= 3.0" }
  }
}
