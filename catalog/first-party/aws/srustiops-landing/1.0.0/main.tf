# What a SrustiOps tenant keeps in its own AWS account, all private: a
# KMS key, the state bucket, a PostgreSQL database and VPC endpoints for the
# AWS APIs, plus the identities the tenant plane and its runners use: IRSA
# roles on EKS, or an instance profile on a VM. These hold the tenant's data,
# so the provisioner never destroys them. No secret value is in this state:
# RDS manages its own password, and the master key is made at bootstrap.

data "aws_region" "current" {}
data "aws_caller_identity" "current" {}
# The role running this apply (the provisioner, or whoever deploys it): it
# keeps access to the bucket from outside the VPC, so later applies and
# repairs still work.
data "aws_iam_session_context" "current" {
  arn = data.aws_caller_identity.current.arn
}

locals {
  tags      = merge({ "managed-by" = "srustiops-landing", "srustiops-tenant" = var.name }, var.tags)
  sa_tenant = "system:serviceaccount:${var.namespace}:${var.release}-tenant"
  sa_runner = "system:serviceaccount:${var.namespace}:${var.release}-runner"
}

resource "aws_kms_key" "this" {
  description             = "${var.name}: state, bucket, database, images and secrets"
  enable_key_rotation     = true
  deletion_window_in_days = 30
  tags                    = local.tags
  # The tenant's data: never destroyed by a run, even when the workspace is removed.
  lifecycle { prevent_destroy = true }
}

resource "aws_kms_alias" "this" {
  name          = "alias/${var.name}"
  target_key_id = aws_kms_key.this.key_id
}

# ---- state and plans ----

resource "aws_s3_bucket" "bucket" {
  bucket_prefix = "${var.name}-"
  tags          = local.tags
  # The tenant's data: never destroyed by a run, even when the workspace is removed.
  lifecycle { prevent_destroy = true }
}

resource "aws_s3_bucket_public_access_block" "bucket" {
  bucket                  = aws_s3_bucket.bucket.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_versioning" "bucket" {
  bucket = aws_s3_bucket.bucket.id
  versioning_configuration { status = "Enabled" }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "bucket" {
  bucket = aws_s3_bucket.bucket.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = aws_kms_key.this.arn
    }
    bucket_key_enabled = true
  }
}

# Only over TLS, and only through the VPC endpoint, except for the role that
# deploys this module and the admin roles given (so they are never locked out).
resource "aws_s3_bucket_policy" "bucket" {
  bucket = aws_s3_bucket.bucket.id
  # Last: once it applies, calls from outside the VPC need the exemption.
  depends_on = [aws_s3_bucket_public_access_block.bucket, aws_s3_bucket_versioning.bucket, aws_s3_bucket_server_side_encryption_configuration.bucket]
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      { Sid      = "TLSOnly", Effect = "Deny", Principal = "*", Action = "s3:*",
        Resource = [aws_s3_bucket.bucket.arn, "${aws_s3_bucket.bucket.arn}/*"],
      Condition = { Bool = { "aws:SecureTransport" = "false" } } },
      { Sid      = "VPCEndpointOnly", Effect = "Deny", Principal = "*", Action = "s3:*",
        Resource = [aws_s3_bucket.bucket.arn, "${aws_s3_bucket.bucket.arn}/*"],
        Condition = {
          StringNotEquals = { "aws:SourceVpce" = aws_vpc_endpoint.s3.id }
          ArnNotLike      = { "aws:PrincipalArn" = concat([data.aws_iam_session_context.current.issuer_arn], var.bucket_admin_arns) }
      } },
    ]
  })
}

# The bucket used to live at these addresses. An early build applied its
# policy before the rest and locked everyone out of it, so tofu forgets those
# objects without touching them in AWS, and the resources above make a new
# bucket. Nothing exists at these addresses in a fresh landing.
removed {
  from = aws_s3_bucket.state
  lifecycle { destroy = false }
}
removed {
  from = aws_s3_bucket_public_access_block.state
  lifecycle { destroy = false }
}
removed {
  from = aws_s3_bucket_versioning.state
  lifecycle { destroy = false }
}
removed {
  from = aws_s3_bucket_server_side_encryption_configuration.state
  lifecycle { destroy = false }
}
removed {
  from = aws_s3_bucket_policy.state
  lifecycle { destroy = false }
}

# ---- images (loaded by scripts/airgap-import.sh) ----

resource "aws_ecr_repository" "image" {
  for_each             = var.image_repositories ? toset(["srustiops-server", "srustiops-runner"]) : toset([])
  name                 = "${var.name}/${each.key}"
  image_tag_mutability = "IMMUTABLE"
  encryption_configuration {
    encryption_type = "KMS"
    kms_key         = aws_kms_key.this.arn
  }
  image_scanning_configuration { scan_on_push = true }
  tags = local.tags
}

# ---- PostgreSQL ----

resource "aws_security_group" "db" {
  name_prefix = "${var.name}-db-"
  vpc_id      = var.vpc_id
  ingress {
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }
  tags = local.tags
}

resource "aws_db_subnet_group" "db" {
  name_prefix = "${var.name}-"
  subnet_ids  = var.private_subnet_ids
  tags        = local.tags
}

resource "aws_db_instance" "db" {
  identifier_prefix                   = "${var.name}-"
  engine                              = "postgres"
  engine_version                      = "16"
  instance_class                      = var.db_instance_class
  allocated_storage                   = 50
  max_allocated_storage               = 500
  storage_encrypted                   = true
  kms_key_id                          = aws_kms_key.this.arn
  db_name                             = "srustiops"
  username                            = "srustiops"
  manage_master_user_password         = true # in Secrets Manager, never in this state
  master_user_secret_kms_key_id       = aws_kms_key.this.arn
  db_subnet_group_name                = aws_db_subnet_group.db.name
  vpc_security_group_ids              = [aws_security_group.db.id]
  publicly_accessible                 = false
  multi_az                            = var.db_multi_az
  backup_retention_period             = 14
  deletion_protection                 = true
  copy_tags_to_snapshot               = true
  iam_database_authentication_enabled = true
  final_snapshot_identifier           = "${var.name}-final"
  tags                                = local.tags
  # The tenant's data: never destroyed by a run, even when the workspace is removed.
  lifecycle { prevent_destroy = true }
}

# ---- private AWS APIs ----

resource "aws_security_group" "endpoints" {
  name_prefix = "${var.name}-endpoints-"
  vpc_id      = var.vpc_id
  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }
  tags = local.tags
}

resource "aws_vpc_endpoint" "interface" {
  for_each            = toset(var.interface_endpoints)
  vpc_id              = var.vpc_id
  service_name        = "com.amazonaws.${data.aws_region.current.region}.${each.key}"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = var.private_subnet_ids
  security_group_ids  = [aws_security_group.endpoints.id]
  private_dns_enabled = true
  tags                = merge(local.tags, { Name = "${var.name}-${each.key}" })
}

data "aws_route_tables" "vpc" {
  vpc_id = var.vpc_id
}

resource "aws_vpc_endpoint" "s3" {
  vpc_id            = var.vpc_id
  service_name      = "com.amazonaws.${data.aws_region.current.region}.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = data.aws_route_tables.vpc.ids
  tags              = merge(local.tags, { Name = "${var.name}-s3" })
}

# ---- workload identity (IRSA) ----

locals {
  irsa   = var.eks_oidc_provider_arn != ""
  issuer = trimprefix(var.eks_oidc_issuer, "https://") # EKS reports it with the scheme
}

data "aws_iam_policy_document" "trust" {
  for_each = local.irsa ? { tenant = local.sa_tenant, runner = local.sa_runner } : {}
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]
    principals {
      type        = "Federated"
      identifiers = [var.eks_oidc_provider_arn]
    }
    condition {
      test     = "StringEquals"
      variable = "${local.issuer}:sub"
      values   = [each.value]
    }
    condition {
      test     = "StringEquals"
      variable = "${local.issuer}:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

# On a VM the tenant plane and runner share the instance's role.
data "aws_iam_policy_document" "instance" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

locals {
  trust = local.irsa ? { for k, d in data.aws_iam_policy_document.trust : k => d.json } : { tenant = data.aws_iam_policy_document.instance.json }
}

resource "aws_iam_role" "this" {
  for_each           = local.trust
  name_prefix        = "${var.name}-${each.key}-"
  assume_role_policy = each.value
  tags               = local.tags
}

resource "aws_iam_role_policy_attachment" "ssm" {
  count      = local.irsa ? 0 : 1
  role       = aws_iam_role.this["tenant"].name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore" # Session Manager instead of SSH
}

resource "aws_iam_instance_profile" "this" {
  count       = local.irsa ? 0 : 1
  name_prefix = "${var.name}-"
  role        = aws_iam_role.this["tenant"].name
  tags        = local.tags
}

data "aws_iam_policy_document" "tenant" {
  statement {
    actions   = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject", "s3:ListBucket"]
    resources = [aws_s3_bucket.bucket.arn, "${aws_s3_bucket.bucket.arn}/*"]
  }
  statement {
    actions   = ["kms:Encrypt", "kms:Decrypt", "kms:GenerateDataKey", "kms:DescribeKey"]
    resources = [aws_kms_key.this.arn]
  }
  statement {
    actions   = ["secretsmanager:GetSecretValue"]
    resources = [aws_db_instance.db.master_user_secret[0].secret_arn]
  }
}

resource "aws_iam_role_policy" "tenant" {
  role   = aws_iam_role.this["tenant"].id
  policy = data.aws_iam_policy_document.tenant.json
}

# Runners only assume the connection roles of the accounts this tenant manages.
data "aws_iam_policy_document" "runner" {
  statement {
    actions   = ["sts:AssumeRole", "sts:TagSession"]
    resources = length(var.deploy_role_arns) > 0 ? var.deploy_role_arns : ["arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/${var.name}-none"]
  }
}

resource "aws_iam_role_policy" "runner" {
  role   = aws_iam_role.this[local.irsa ? "runner" : "tenant"].id
  policy = data.aws_iam_policy_document.runner.json
}
