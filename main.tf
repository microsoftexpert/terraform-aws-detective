###############################################################################
# tf_mod_aws_detective — main
#
# Keystone: aws_detective_graph.this (one graph per account per Region),
# rendered behind a guarded for_each keyed "this" so this module can also be
# invoked with create_graph = false — from a member account's own provider
# context — purely to accept an invitation and/or manage org-level Detective
# configuration against an externally-supplied graph_arn.
#
# local.graph_arn resolves to this module's own graph when create_graph =
# true, or to the caller-supplied var.graph_arn otherwise. Every child
# resource references local.graph_arn rather than the graph resource
# directly, so the module works identically in both invocation shapes.
#
# Only aws_detective_graph is taggable; var.tags is wired to it alone.
###############################################################################

# --- Behavior graph (keystone) ----------------------------------------------

resource "aws_detective_graph" "this" {
 for_each = var.create_graph ? { this = true }: {}

 tags = var.tags
}

locals {
 graph_arn = var.create_graph ? aws_detective_graph.this["this"].graph_arn: var.graph_arn
}

# --- Member accounts (multi-account invitations) ----------------------------

resource "aws_detective_member" "this" {
 for_each = var.members

 graph_arn = local.graph_arn
 account_id = each.value.account_id
 email_address = each.value.email_address
 message = try(each.value.message, null)
 disable_email_notification = try(each.value.disable_email_notification, false)
}

# --- Organization admin account (Organizations management account) ---------

resource "aws_detective_organization_admin_account" "this" {
 for_each = var.enable_organization_admin_account ? { this = var.organization_admin_account_id }: {}

 account_id = each.value
}

# --- Organization configuration (delegated administrator account) ----------

resource "aws_detective_organization_configuration" "this" {
 for_each = var.organization_configuration != null ? { this = var.organization_configuration }: {}

 graph_arn = local.graph_arn
 auto_enable = each.value.auto_enable

 # The delegated administrator must be registered before the org policy is
 # applied. No attribute reference links them (they typically run from
 # different accounts), so encode the ordering explicitly for the single-call
 # case where both are created here — mirrors terraform-aws-inspector2.
 depends_on = [aws_detective_organization_admin_account.this]
}

# --- Invitation accepter (member account's own provider context) -----------

resource "aws_detective_invitation_accepter" "this" {
 for_each = var.accept_invitation ? { this = true }: {}

 graph_arn = local.graph_arn

 # The member account must already have a pending invitation from the
 # administrator account's aws_detective_member before this succeeds. When
 # both are managed in a single (test/demo) call across provider aliases,
 # depends_on encodes that ordering explicitly.
 depends_on = [aws_detective_member.this]
}
