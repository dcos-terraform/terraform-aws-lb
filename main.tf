/**
 * [![Build Status](https://jenkins-terraform.mesosphere.com/service/dcos-terraform-jenkins/job/dcos-terraform/job/terraform-aws-lb/job/master/badge/icon)](https://jenkins-terraform.mesosphere.com/service/dcos-terraform-jenkins/job/dcos-terraform/job/terraform-aws-lb/job/master/)
 * AWS LB - Application and Network Load Balancer
 * ============
 * This module create Application and Network Load Balancers. Beaware that Application supports only "HTTP" and "HTTPS" whereas Netowrk only supports "TCP" and "UDP"
 *
 * EXAMPLE
 * -------
 *
 *```hcl
 * module "dcos-masters-lb" {
 *   source  = "terraform-dcos/lb/aws"
 *   version = "~> 0.3.0"
 *
 *   cluster_name = "production"
 *
 *   subnet_ids = ["subnet-12345678"]
 *   load_balancer_type = "application"
 *   additional_listener = [{
 *     port = 8080
 *     protocol = "http"
 *   }]
 *
 *   https_acm_cert_arn = "arn:aws:acm:us-east-1:123456789123:certificate/ooc4NeiF-1234-5678-9abc-vei5Eeniipo4"
 * }
 *```
 */

provider "aws" {
  version = ">= 2.58"
}

locals {
  cluster_name = var.name_prefix != "" ? "${var.name_prefix}-${var.cluster_name}" : var.cluster_name
}

resource "tls_private_key" "selfsigned" {
  algorithm   = "ECDSA"
  ecdsa_curve = "P384"
}

resource "tls_self_signed_cert" "selfsigned" {
  count           = var.disable ? 0 : 1
  key_algorithm   = "ECDSA"
  private_key_pem = tls_private_key.selfsigned.private_key_pem

  subject {
    common_name  = element(aws_lb.loadbalancer.*.dns_name, 0)
    organization = "Mesosphere Inc."
  }

  validity_period_hours = 19800

  allowed_uses = [
    "key_encipherment",
    "digital_signature",
    "server_auth",
  ]
}

resource "aws_iam_server_certificate" "selfsigned" {
  count = var.disable ? 0 : 1
  name = "${format(var.elb_name_format, local.cluster_name)}-cert-${replace(
    element(tls_self_signed_cert.selfsigned.*.validity_start_time, 0),
    "/[:+.]/",
    "-",
  )}"
  certificate_body = element(tls_self_signed_cert.selfsigned.*.cert_pem, 0)
  private_key      = element(tls_private_key.selfsigned.*.private_key_pem, 0)

  lifecycle {
    create_before_destroy = true
  }
}

data "aws_subnet" "selected" {
  id = element(var.subnet_ids, 0)
}

// Only 32 characters allowed for name. So we have to use substring
locals {
  elb_name = format(var.elb_name_format, local.cluster_name)

  default_listeners = [
    {
      port     = 80
      protocol = var.load_balancer_type == "application" ? "http" : "tcp"
    },
    {
      port            = 443
      protocol        = var.load_balancer_type == "application" ? "https" : "tcp"
      certificate_arn = var.load_balancer_type == "application" ? coalesce(var.https_acm_cert_arn, "selfsigned") : ""
    },
  ]

  new_concat_list = concat(local.default_listeners, var.additional_listener)

  concat_listeners = coalescelist(
    var.listener,
    concat(local.default_listeners, var.additional_listener),
  )

  instances = [coalescelist(var.instances, [""])]
}

resource "aws_lb" "loadbalancer" {
  count = var.disable ? 0 : 1
  name = substr(
    local.elb_name,
    0,
    length(local.elb_name) >= 32 ? 32 : length(local.elb_name),
  )
  internal                         = var.internal
  load_balancer_type               = var.load_balancer_type
  subnets                          = var.subnet_ids
  enable_cross_zone_load_balancing = var.cross_zone_load_balancing

  # security_groups = ["${ var.load_balancer_type == "application" ? var.security_groups : list()}"]

  security_groups = compact(
    split(
      ",",
      var.load_balancer_type == "application" ? join(",", var.security_groups) : "",
    ),
  )
  tags = merge(
    var.tags,
    {
      "Name"    = format(var.elb_name_format, local.cluster_name)
      "Cluster" = local.cluster_name
    },
  )
}

resource "aws_lb_listener" "listeners" {
  count             = var.disable ? 0 : length(local.concat_listeners)
  load_balancer_arn = element(aws_lb.loadbalancer.*.arn, 0)
  port              = local.concat_listeners[count.index]["port"]
  protocol = upper(
    lookup(
      local.concat_listeners[count.index],
      "protocol",
      var.load_balancer_type == "application" ? "http" : "tcp",
    ),
  )

  certificate_arn = lookup(local.concat_listeners[count.index], "certificate_arn", "") == "selfsigned" ? aws_iam_server_certificate.selfsigned[0].arn : lookup(local.concat_listeners[count.index], "certificate_arn", "")

  default_action {
    type             = "forward"
    target_group_arn = element(aws_lb_target_group.targetgroup.*.arn, count.index)
  }
}

resource "aws_lb_target_group" "targetgroup" {
  count = var.disable ? 0 : length(local.concat_listeners)
  port  = local.concat_listeners[count.index]["port"]
  protocol = upper(
    lookup(
      local.concat_listeners[count.index],
      "protocol",
      var.load_balancer_type == "application" ? "http" : "tcp",
    ),
  )
  name = "${substr(
    local.elb_name,
    0,
    length(local.elb_name) >= 24 ? 23 : length(local.elb_name),
  )}-tg-${local.concat_listeners[count.index]["port"]}"
  tags = merge(
    var.tags,
    {
      "Name"    = format(var.elb_name_format, local.cluster_name)
      "Cluster" = local.cluster_name
    },
  )

  vpc_id = data.aws_subnet.selected.vpc_id

  stickiness {
    type    = "lb_cookie"
    enabled = false
  }

  health_check {
    protocol = upper(
      lookup(
        local.concat_listeners[count.index],
        "protocol",
        var.load_balancer_type == "application" ? "http" : "tcp",
      ),
    )
    port = local.concat_listeners[count.index]["port"]
  }
}

resource "aws_lb_target_group_attachment" "attachment" {
  count = var.disable ? 0 : var.num_instances * length(local.concat_listeners)
  target_group_arn = element(
    aws_lb_target_group.targetgroup.*.arn,
    ceil(count.index / length(local.instances)),
  )
  target_id = element(var.instances, count.index)
  port      = local.concat_listeners[ceil(count.index / length(local.instances))]["port"]
}

