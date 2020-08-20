[![Build Status](https://jenkins-terraform.mesosphere.com/service/dcos-terraform-jenkins/job/dcos-terraform/job/terraform-aws-lb/job/master/badge/icon)](https://jenkins-terraform.mesosphere.com/service/dcos-terraform-jenkins/job/dcos-terraform/job/terraform-aws-lb/job/master/)  
AWS LB - Application and Network Load Balancer
============  
This module create Application and Network Load Balancers. Beaware that Application supports only "HTTP" and "HTTPS" whereas Netowrk only supports "TCP" and "UDP"

EXAMPLE
-------

\*```hcl
module "dcos-masters-lb" {
  source  = "terraform-dcos/lb/aws"
  version = "~> 0.3.0"

  cluster_name = "production"

  subnet_ids = ["subnet-12345678"]
  load_balancer_type = "application"
  additional_listener = [{
    port = 8080
    protocol = "http"
  }]

  https_acm_cert_arn = "arn:aws:acm:us-east-1:123456789123:certificate/ooc4NeiF-1234-5678-9abc-vei5Eeniipo4"
}
*
```

## Requirements

| Name | Version |
|------|---------|
| terraform | >= 0.12 |
| aws | >= 2.58 |

## Providers

| Name | Version |
|------|---------|
| aws | >= 2.58 |
| tls | n/a |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| cluster\_name | Name of the DC/OS cluster | `any` | n/a | yes |
| instances | List of instance IDs | `list(string)` | n/a | yes |
| num\_instances | How many instances should be created | `any` | n/a | yes |
| subnet\_ids | List of subnet IDs created in this network | `list(string)` | n/a | yes |
| additional\_listener | List of additional listeners | `list` | `[]` | no |
| cross\_zone\_load\_balancing | Enable cross-zone load balancing | `bool` | `true` | no |
| disable | Do not create load balancer and its resources | `bool` | `false` | no |
| elb\_name\_format | Printf style format for naming the ELB. Gets truncated to 32 characters. (input cluster\_name) | `string` | `"load-balancer-%s"` | no |
| health\_check | Health check definition. | `map(string)` | <pre>{<br>  "healthy_threshold": 2,<br>  "interval": 30,<br>  "target": "TCP:80",<br>  "timeout": 3,<br>  "unhealthy_threshold": 2<br>}</pre> | no |
| https\_acm\_cert\_arn | ACM certifacte to be used. | `string` | `""` | no |
| internal | This ELB is internal only | `bool` | `false` | no |
| listener | List of listeners. By default HTTP and HTTPS are set. If set it overrides the default listeners. | `list` | `[]` | no |
| load\_balancer\_type | Load Balancer type. Allowed values network, application | `string` | `"network"` | no |
| name\_prefix | Name Prefix | `string` | `""` | no |
| security\_groups | Security Group IDs to use | `list(string)` | `[]` | no |
| tags | Add custom tags to all resources | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
|------|-------------|
| dns\_name | DNS Name of the master load balancer |

