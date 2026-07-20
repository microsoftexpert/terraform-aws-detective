###############################################################################
# tf_mod_aws_detective — variables
#
# Composite module for Amazon Detective. The keystone is a single regional
# behavior graph (aws_detective_graph.this), rendered behind a guarded
# for_each (keyed "this") so the SAME module can be invoked either as the
# graph owner (create_graph = true) or, from a member account's own provider
# context, purely to accept an invitation and/or manage org-level Detective
# configuration against an EXISTING graph_arn (create_graph = false).
#
# Child collections (members) are for_each maps; the organization admin
# account, organization configuration, and invitation accepter are optional
# single objects/toggles guarded via for_each keyed "this" — the modern
# "conditionally-created singleton" pattern already used by
# terraform-aws-inspector2 and terraform-aws-security-hub in this library.
#
# Secure-by-default: none of the Detective resources expose an
# encryption/public-access/logging toggle (Detective is itself a
# threat-investigation *consumer* of GuardDuty/VPC Flow Logs/DNS logs, not a
# data store this module encrypts) — the meaningful secure-by-default lever
# here is auto_enable on aws_detective_organization_configuration, which
# governs whether NEW organization accounts are automatically enrolled.
# Defaulting that ON is documented as a tradeoff (automatic coverage vs.
# explicit per-account opt-in) rather than silently applied — see
# organization_configuration and README § Design Principles.
#
# TAGGING NOTE: of the five Detective resources, ONLY aws_detective_graph
# supports `tags`/`tags_all` in the hashicorp/aws provider (verified against
# v6.54.0 provider docs). aws_detective_member, aws_detective_invitation_accepter,
# aws_detective_organization_admin_account, and aws_detective_organization_configuration
# accept no tags argument. var.tags is therefore wired to the graph ONLY. See
# the tags variable and SCOPE.md § Provider gotchas.
###############################################################################

# --- Behavior graph (keystone) ----------------------------------------------

variable "create_graph" {
 description = <<EOT
Whether to create the keystone aws_detective_graph (the behavior graph this
account owns).

Defaults to true — the module's core purpose, invoked from the account that
will act as the Detective administrator (standalone or org delegated admin).
Set this to false when invoking the module from a MEMBER account's own
provider context purely to accept an invitation (accept_invitation = true)
against an administrator-owned graph_arn supplied via var.graph_arn — that
account does not own its own graph.

An AWS account may own only ONE Detective behavior graph per Region;
instantiate this module once per Region (via a provider alias) if multiple
Regions are required, and never twice with create_graph = true in the same
account + Region.
EOT
 type = bool
 default = true
}

variable "graph_arn" {
 description = <<EOT
ARN of an EXISTING Detective behavior graph to operate against when
create_graph = false (e.g. a member account referencing the administrator's
graph, or a caller wiring members/organization configuration onto a graph
created outside this module call).

Ignored (and computed from this module's own aws_detective_graph) when
create_graph = true. REQUIRED when create_graph = false and you also set
members, organization_configuration, or accept_invitation = true. Defaults to
null.
EOT
 type = string
 default = null

 validation {
 condition = var.graph_arn == null ? true: can(regex("^arn:aws[a-zA-Z-]*:detective:", var.graph_arn))
 error_message = "graph_arn must be a Detective behavior graph ARN (arn:aws:detective:<region>:<account-id>:graph:<graph-id>)."
 }

 validation {
 condition = var.create_graph || var.graph_arn != null || (length(var.members) == 0 && var.organization_configuration == null && !var.accept_invitation)
 error_message = "graph_arn is required when create_graph = false and you supply members, organization_configuration, or accept_invitation = true."
 }
}

# --- Member accounts (multi-account invitations) ----------------------------

variable "members" {
 description = <<EOT
Map of Detective member accounts keyed by a stable label. Only meaningful from
the graph-owning (administrator) account; each entry is one aws_detective_member
inviting an account to contribute its data to THIS module's graph
(create_graph's graph, or the graph_arn supplied when create_graph = false).

 members = {
 "audit" = {
 account_id = "123456789012"
 email_address = "security@example.com"
 message = optional(string) # custom invitation text
 disable_email_notification = optional(bool, false) # suppress the root-user invitation email
 }
 }

Defaults to {} (standalone graph — no members). aws_detective_member is NOT a
taggable resource. Each invited member account must separately run this module
with create_graph = false and accept_invitation = true (from its own provider
context) to move from "INVITED" to "ENABLED" status — see
aws_detective_invitation_accepter / var.accept_invitation.
EOT
 type = map(object({
 account_id = string
 email_address = string
 message = optional(string)
 disable_email_notification = optional(bool, false)
 }))
 default = {}

 validation {
 condition = alltrue([for m in values(var.members): can(regex("^[0-9]{12}$", m.account_id))])
 error_message = "Each member account_id must be a 12-digit AWS account ID."
 }
}

# --- Organization admin account (Organizations management account) ---------

variable "enable_organization_admin_account" {
 description = <<EOT
Whether to register organization_admin_account_id as the Organization's
Detective delegated administrator (aws_detective_organization_admin_account).

Defaults to false. Apply this from the Organizations MANAGEMENT (primary)
account only — this mirrors the delegated-administrator pattern used
identically by terraform-aws-guardduty and terraform-aws-security-hub for their
respective services. An Organization has exactly one Detective delegated
administrator per Region.
EOT
 type = bool
 default = false
}

variable "organization_admin_account_id" {
 description = <<EOT
The 12-digit AWS account ID to register as the Detective delegated
administrator. Typically an existing member/security-tooling account ID
supplied directly, or sourced from data.aws_organizations_organization /
data.aws_caller_identity in the root module.

Required when enable_organization_admin_account = true; otherwise ignored.
Defaults to null.
EOT
 type = string
 default = null

 validation {
 condition = var.organization_admin_account_id == null ? true: can(regex("^[0-9]{12}$", var.organization_admin_account_id))
 error_message = "organization_admin_account_id must be a 12-digit AWS account ID."
 }

 validation {
 condition = !var.enable_organization_admin_account || var.organization_admin_account_id != null
 error_message = "organization_admin_account_id is required when enable_organization_admin_account is true."
 }
}

# --- Organization configuration (delegated administrator account) ----------

variable "organization_configuration" {
 description = <<EOT
Optional org-wide auto-enrollment policy (aws_detective_organization_configuration)
applied to THIS module's graph. Must be created from the Detective DELEGATED
ADMINISTRATOR account (not the management account), and the delegated
administrator must already be registered
(aws_detective_organization_admin_account) first — the module orders
organization_admin_account -> organization_configuration via depends_on when
both are created in a single call.

 organization_configuration = {
 auto_enable = true # (Required) new org accounts are auto-added as graph
 # members and Detective is auto-enabled for them in
 # this Region
 }

Defaults to null (no org-wide auto-enrollment policy — accounts are invited
individually via var.members). SECURE-BY-DEFAULT TRADEOFF: setting
auto_enable = true gives new accounts automatic, continuous Detective
coverage the moment they join the organization (recommended for our
PII/privacy-regulation baseline — no gap while a human remembers to invite a new account),
but it also means Terraform is no longer the single source of truth for which
accounts participate — review the tradeoff in README § Design Principles
before enabling. Terraform assumes management of this resource without
import and takes no destroy-time action (AWS-side; see Provider gotchas).
EOT
 type = object({
 auto_enable = bool
 })
 default = null
}

# --- Invitation accepter (member account's own provider context) -----------

variable "accept_invitation" {
 description = <<EOT
Whether to create aws_detective_invitation_accepter against var.graph_arn (or
this module's own graph when create_graph = true, though that combination is
unusual — an account does not typically invite and accept itself).

Defaults to false. This resource is intended to run from the INVITED MEMBER
account's own provider context (typically create_graph = false, graph_arn =
the administrator's graph ARN) — mirroring the cross-account accepter pattern
used elsewhere in this library (e.g. aws_guardduty_invite_accepter). The
member account must already have a pending invitation (created by
aws_detective_member from the administrator account) before this succeeds.
EOT
 type = bool
 default = false
}

# --- Universal tail: tags, then timeouts ------------------------------------

variable "tags" {
 description = <<EOT
A map of tags to assign to the TAGGABLE resources created by this module.

IMPORTANT: of the five Detective resources, ONLY aws_detective_graph accepts a
`tags` argument in the hashicorp/aws provider. var.tags is therefore applied to
the GRAPH ONLY (when create_graph = true); aws_detective_member,
aws_detective_invitation_accepter, aws_detective_organization_admin_account,
and aws_detective_organization_configuration are not taggable and receive no
tags. Graph tags merge with provider-level default_tags; resource tags win on
key conflict. The tags_all output reflects the merged set on the graph (null
when create_graph = false).
EOT
 type = map(string)
 default = {}
}

variable "timeouts" {
 description = <<EOT
Reserved for interface consistency with the rest of the tf_mod_aws_* library.

IMPORTANT: none of the five Detective resources exposed by the hashicorp/aws
provider (aws_detective_graph, _member, _invitation_accepter,
_organization_admin_account, _organization_configuration) declare a
configurable Timeouts block (verified against the provider's resource schemas
and documentation, v6.54.0) — every create/update/delete on this service uses
the provider's fixed internal defaults. This variable is therefore accepted
but NOT wired to any resource in main.tf; it is retained so a future provider
version that adds timeouts support can be picked up without an interface
change, matching the precedent set by terraform-aws-security-hub's tags caveat
for a similarly all-or-nothing provider-schema gap.
EOT
 type = object({
 create = optional(string)
 update = optional(string)
 delete = optional(string)
 })
 default = {}
}
