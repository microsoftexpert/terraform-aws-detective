terraform {
 required_version = ">= 1.12.0"

 required_providers {
 aws = {
 source = "hashicorp/aws"
 version = ">= 6.0, < 7.0"
 }
 }
}

# No provider "aws" {} block is declared inside this module.
#
# Detective is a regional service: the behavior graph and all of its child
# resources (members, invitation accepter, organization admin account,
# organization configuration) are created in the Region of the inherited
# provider. The caller configures region, credentials, default_tags, and
# assume_role at the root module / pipeline level and this module inherits
# that provider.
#
# An AWS account may own only ONE Detective behavior graph per Region. To
# manage Detective in multiple Regions, instantiate this module once per
# Region using provider aliases passed via `providers = { aws = aws.<region_alias> }`.
#
# Cross-account shape: the graph owner (administrator) account and each
# member account are DIFFERENT AWS accounts/providers. A typical rollout
# invokes this module twice:
# 1. From the administrator account — create_graph = true, populate
# members, optionally enable the organization admin account / org
# configuration.
# 2. From EACH member account — create_graph = false, accept_invitation =
# true, graph_arn = the administrator's graph ARN (from call #1's `arn`
# output) — via `providers = { aws = aws.member_account }`.
