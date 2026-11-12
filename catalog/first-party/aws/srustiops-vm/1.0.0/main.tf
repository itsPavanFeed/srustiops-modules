# The SrustiOps services on one EC2 instance: the tenant plane, its link agent
# and a runner, in Docker Compose, started by cloud-init. The instance sits in
# a private subnet with no inbound rules (Session Manager, not SSH); it dials
# out to the platform's gateway. Its database is the landing module's RDS,
# whose password the instance reads from Secrets Manager at boot, so it is in
# no state or user data. The install token in the user data works once and
# expires in an hour; bootstrap makes every key on the instance.

data "aws_region" "current" {}

data "aws_ssm_parameter" "al2023" {
  name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-${var.architecture == "arm64" ? "arm64" : "x86_64"}"
}

locals {
  ca = var.gateway_ca != ""
  # The gateway normally listens on 443; a tunnel (or a custom gateway) may
  # use another port, which the instance must also be allowed to reach.
  gateway_port = try(tonumber(regex(":([0-9]+)$", var.gateway_url)[0]), 443)

  # The services, as a Compose file. Built as data and encoded, so its YAML
  # is always well formed (hand-indented YAML in a template broke before).
  compose = {
    services = {
      tenant = {
        image   = "${var.image_repo}/srustiops-server:${var.image_tag}"
        command = ["tenant"]
        restart = "unless-stopped"
        user    = "1000:1000"
        environment = merge({
          SRUSTIOPS_TENANT                      = var.tenant
          SRUSTIOPS_LISTEN                      = ":8443"
          SRUSTIOPS_PUBLIC_URL                  = "https://tenant:8443"
          SRUSTIOPS_DATABASE_URL_FILE           = "/run/srustiops/database-url"
          SRUSTIOPS_MASTER_KEY_FILE             = "/srustiops/keys/master-key"
          SRUSTIOPS_TLS_CERT                    = "/srustiops/tls/tls.crt"
          SRUSTIOPS_TLS_KEY                     = "/srustiops/tls/tls.key"
          SRUSTIOPS_CENTRAL_URL                 = var.gateway_url
          SRUSTIOPS_CENTRAL_ISSUER              = var.central_url
          SRUSTIOPS_CENTRAL_CLIENT_CA           = "/srustiops/central-ca/ca.crt"
          SRUSTIOPS_BOOTSTRAP_RUNNER_TOKEN_FILE = "/srustiops/keys/runner-token"
        }, local.ca ? { SRUSTIOPS_CENTRAL_CA_FILE = "/srustiops/gateway-ca.pem" } : {})
        volumes = ["./srustiops:/srustiops:ro", "/run/srustiops:/run/srustiops:ro"]
      }
      link = {
        image   = "${var.image_repo}/srustiops-server:${var.image_tag}"
        command = ["link"]
        restart = "unless-stopped"
        user    = "1000:1000"
        environment = merge({
          SRUSTIOPS_TENANT                 = var.tenant
          SRUSTIOPS_LINK_URL               = var.gateway_url
          SRUSTIOPS_LINK_TARGET            = "tenant:8443"
          SRUSTIOPS_LINK_STATE_DIR         = "/state"
          SRUSTIOPS_LINK_ENROLL_TOKEN_FILE = "/srustiops/link-enroll/token"
        }, local.ca ? { SRUSTIOPS_LINK_SERVER_CA = "/srustiops/gateway-ca.pem" } : {})
        volumes    = ["./srustiops:/srustiops:ro", "./link-state:/state"]
        depends_on = ["tenant"]
      }
      runner = {
        image   = "${var.image_repo}/srustiops-runner:${var.image_tag}"
        command = ["runner"]
        restart = "unless-stopped"
        user    = "1000:1000"
        environment = {
          SRUSTIOPS_SERVER_URL        = "https://tenant:8443"
          SRUSTIOPS_RUNNER_TOKEN_FILE = "/srustiops/keys/runner-token"
          SRUSTIOPS_STATE_KEY_FILE    = "/srustiops/keys/state-key"
          SRUSTIOPS_CA_FILE           = "/srustiops/tls/ca.crt"
        }
        volumes    = ["./srustiops:/srustiops:ro"]
        depends_on = ["tenant"]
      }
    }
  }

  # Runs at every boot: the database URL is rebuilt from Secrets Manager
  # (RDS rotates the password) into tmpfs, never onto disk.
  start_sh = <<-EOT
    #!/bin/bash
    set -euo pipefail
    cd /opt/srustiops
    mkdir -p /run/srustiops && chmod 0750 /run/srustiops && chown root:1000 /run/srustiops
    s=$(aws secretsmanager get-secret-value --region ${data.aws_region.current.region} --secret-id '${var.database_password_secret_arn}' --query SecretString --output text)
    u=$(jq -r .username <<<"$s"); p=$(jq -rj .password <<<"$s" | jq -sRr @uri)
    printf 'postgres://%s:%s@${var.database_endpoint}/srustiops?sslmode=require' "$u" "$p" > /run/srustiops/database-url
    chmod 0640 /run/srustiops/database-url && chown root:1000 /run/srustiops/database-url
    if [ -f install.token ]; then
      # Once: keys are made here; the gateway returns certificates and the link
      # enrolment. Retried while the gateway cannot be reached (it may be
      # starting, or a tunnel may be down); systemd runs the script again if
      # it gives up.
      chown 1000:1000 install.token # bootstrap runs as 1000, like the services
      for try in $(seq 1 40); do
        if docker run --rm --user 1000:1000 -v /opt/srustiops/srustiops:/out -v /opt/srustiops/install.token:/install/token:ro \
          -e SRUSTIOPS_TENANT=${var.tenant} -e SRUSTIOPS_LINK_URL=${var.gateway_url} -e SRUSTIOPS_SERVER_NAMES=tenant \
          -e SRUSTIOPS_INSTALL_TOKEN_FILE=/install/token ${local.ca ? "-e SRUSTIOPS_LINK_SERVER_CA=/out/gateway-ca.pem" : ""} \
          ${var.image_repo}/srustiops-server:${var.image_tag} bootstrap -out /out; then
          break
        fi
        [ "$try" -lt 40 ] || exit 1
        echo "bootstrap failed (attempt $try); retrying in 30 s" >&2
        sleep 30
      done
      shred -u install.token
    fi
    docker compose up -d
  EOT

  service = <<-EOT
    [Unit]
    Description=SrustiOps tenant
    After=docker.service network-online.target
    Wants=network-online.target
    Requires=docker.service
    [Service]
    Type=oneshot
    RemainAfterExit=yes
    # Image pulls and bootstrap retries take longer than the default 90 s.
    TimeoutStartSec=infinity
    Restart=on-failure
    RestartSec=60
    ExecStart=/opt/srustiops/start.sh
    ExecStop=/usr/bin/docker compose -f /opt/srustiops/docker-compose.yml down
    [Install]
    WantedBy=multi-user.target
  EOT

  # cloud-init: installs Docker, writes the files above and starts the
  # service. Encoded from data for the same reason as the Compose file.
  cloud_init = "#cloud-config\n${yamlencode({
    package_update = true
    packages       = ["docker", "jq"]
    write_files = concat(
      [{ path = "/opt/srustiops/install.token", permissions = "0600", content = var.install_token }],
      local.ca ? [{ path = "/opt/srustiops/srustiops/gateway-ca.pem", permissions = "0644", content = var.gateway_ca }] : [],
      [
        { path = "/opt/srustiops/docker-compose.yml", permissions = "0644", content = yamlencode(local.compose) },
        { path = "/opt/srustiops/start.sh", permissions = "0700", content = local.start_sh },
        { path = "/etc/systemd/system/srustiops.service", permissions = "0644", content = local.service },
      ],
    )
    runcmd = [
      "mkdir -p /usr/local/lib/docker/cli-plugins",
      "curl -fsSL --retry 5 -o /usr/local/lib/docker/cli-plugins/docker-compose \"https://github.com/docker/compose/releases/download/v2.29.7/docker-compose-linux-$(uname -m)\"",
      "chmod +x /usr/local/lib/docker/cli-plugins/docker-compose",
      "mkdir -p /opt/srustiops/srustiops /opt/srustiops/link-state && chown -R 1000:1000 /opt/srustiops/srustiops /opt/srustiops/link-state",
      "systemctl daemon-reload",
      "systemctl enable --now docker",
      "systemctl enable --now srustiops.service",
    ]
  })}"
  tags = merge({ "managed-by" = "srustiops-provisioner", "srustiops-tenant" = var.tenant, "srustiops-role" = "service" }, var.tags)
}

resource "aws_security_group" "this" {
  name_prefix = "${var.name}-vm-"
  description = "SrustiOps tenant VM: no inbound, egress to the gateway, registries and the database"
  vpc_id      = var.vpc_id
  egress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  dynamic "egress" {
    for_each = local.gateway_port == 443 ? [] : [local.gateway_port]
    content {
      description = "the platform gateway"
      from_port   = egress.value
      to_port     = egress.value
      protocol    = "tcp"
      cidr_blocks = ["0.0.0.0/0"]
    }
  }
  egress {
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }
  egress {
    from_port   = 53
    to_port     = 53
    protocol    = "udp"
    cidr_blocks = [var.vpc_cidr]
  }
  tags = local.tags
}

# The install token changes only when the provisioner reinstalls (the last
# one expired before the tenant plane connected). Then the instance is
# replaced, so the new one boots with the new token; nothing else replaces it.
resource "terraform_data" "install" {
  input = sha256(var.install_token)
}

resource "aws_instance" "this" {
  ami                         = data.aws_ssm_parameter.al2023.value
  instance_type               = var.instance_type
  subnet_id                   = var.subnet_ids[0]
  vpc_security_group_ids      = [aws_security_group.this.id]
  iam_instance_profile        = var.instance_profile
  associate_public_ip_address = false
  user_data_replace_on_change = false
  user_data                   = local.cloud_init
  metadata_options {
    http_tokens                 = "required" # IMDSv2 only
    http_put_response_hop_limit = 2          # containers reach the instance role
  }
  root_block_device {
    volume_size = var.disk_gb
    volume_type = "gp3"
    encrypted   = true
    kms_key_id  = var.kms_key_arn
  }
  tags = merge(local.tags, { Name = "${var.name}-srustiops" })
  lifecycle {
    # User data holds the install token; a new token replaces the instance
    # through terraform_data.install instead of updating it in place. A new
    # AMI waits for a deliberate replacement.
    ignore_changes       = [user_data, ami]
    replace_triggered_by = [terraform_data.install]
  }
}

# Removing the workspace takes only SrustiOps off the machine, through Systems
# Manager: the instance, network and data stay, and the keys are kept so the
# data in the database stays readable if SrustiOps is installed again.
resource "aws_ssm_association" "remove_srustiops" {
  count            = var.remove_srustiops ? 1 : 0
  name             = "AWS-RunShellScript"
  association_name = "${var.name}-remove-srustiops"
  targets {
    key    = "InstanceIds"
    values = [aws_instance.this.id]
  }
  parameters = {
    commands = <<-EOT
      set -eu
      systemctl disable --now srustiops.service || true
      if [ -f /opt/srustiops/docker-compose.yml ]; then
        docker compose -f /opt/srustiops/docker-compose.yml down --rmi all --remove-orphans || true
      fi
      rm -f /etc/systemd/system/srustiops.service /opt/srustiops/docker-compose.yml /opt/srustiops/start.sh /opt/srustiops/install.token
      systemctl daemon-reload
      echo "SrustiOps was removed $(date -u +%FT%TZ) because its workspace was removed from the platform. Keys are kept in /opt/srustiops/srustiops." > /opt/srustiops/REMOVED
    EOT
  }
}
