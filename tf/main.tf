terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 3.0"
    }
  }
}

provider "aws" {
  profile = "kubernetes-limitless-dev"
  region = "us-east-1"
  shared_credentials_file = "~/.aws/credentials"
}

#
# This should be the only block that needs changing regularly...
#
variable "routes" {
    type = object({
        glass = list(string)
        prod = list(string)
    })

    default = {
        glass = [
            "sso",
            "minecraft.public",
            "registry.lab",
            "alerts.mon",
            "grafana.mon",
            "prom.mon",
            "fetch.news",
            "xmit.news",
            "screen.news",
            "conf.news",
            "shorts.news",
            "music.news",
            "movies.news",
            "books.news",
            "library.news",
            "ai.home",
        ]
        prod = []
    }
}

#
# Route53 Dev/Prod Environment Setup
#
# glass: dev env hosted zone id
# prod: prod env hosted zone id
#
variable "zones" {
    type = object({
        glass   = string
        prod    = string
    })

    default = {
        glass = "Z010939671A5NCHBBBCH"
        prod = "Z05575802ULDZNGHPUH6L"
    }
}

# Add custom TXT records to your domains
variable "txt_records" {
    type = object({
        glass   = list(string)
        prod    = list(string)
    })

    default = {
        glass = [
            "v=spf1 include:amazonses.com -all",
            ]
        prod = [
            "v=spf1 include:amazonses.com ~all",
            ]
    }
}

#
# This should be a DNS record that points to your server.
# e.g. afraid.org or another dynamic DNS provider
#
# variable "dynamic_dns" {
#     type = list(string)
#     default = ["ipv4-is-about-to-be.strangled.net"]
# }

# Don't change - gets current IP
data "external" "current_ip" {
    program = ["bash", "-c", "curl -s 'https://ipinfo.io/json'"]
}

# Don't change - sets A record to current IP
resource "aws_route53_record" "glass_ip" {
    zone_id     = var.zones.glass
    name        = "ingress"
    type        = "A"
    ttl         = 5
    records     = [data.external.current_ip.result.ip]
}

resource "aws_route53_record" "prod_tld" {
    zone_id     = var.zones.prod
    name        = ""
    type        = "A"
    ttl         = 300
    records     = [data.external.current_ip.result.ip]
}

resource "aws_route53_record" "prod_ip" {
    zone_id     = var.zones.prod
    name        = "ingress"
    type        = "A"
    ttl         = 300
    records     = [data.external.current_ip.result.ip] # maybe change
}

resource "aws_route53_record" "glass" {
    zone_id     = var.zones.glass
    name        = each.key
    type        = "CNAME"
    ttl         = 5
    records     = ["ingress.madeof.glass"]
    for_each    = toset(var.routes.glass)
}

resource "aws_route53_record" "prod" {
    zone_id     = var.zones.prod
    name        = each.key
    type        = "CNAME"
    ttl         = 5
    records     = ["ingress.limitlessinteractive.com"]
    for_each    = toset(var.routes.prod)
}

# Don't change
resource "aws_route53_record" "glass_txt" {
    zone_id     = var.zones.glass
    name        = ""
    type        = "TXT"
    ttl         = 300
    records     = var.txt_records.glass
}

# Change for custom MX records on dev
resource "aws_route53_record" "glass_mx" {
    zone_id     = var.zones.glass
    name        = ""
    type        = "MX"
    ttl         = 3600
    records     = ["10 inbound-smtp.us-east-1.amazonaws.com"]
}

# Change for custom DMARC records on dev
resource "aws_route53_record" "glass_dmarc" {
    zone_id     = var.zones.glass
    name        = "_dmarc"
    type        = "TXT"
    ttl         = 3600
    records     = ["v=DMARC1;p=quarantine;pct=100;fo=1"]
}
