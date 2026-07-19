###############################################################################
# tf_mod_aws_detective — outputs
#
# Primary outputs are id + arn (the cross-resource reference types) on the
# behavior graph, plus tags_all. All graph-derived outputs use try(..., null)
# because the graph is behind a toggle (create_graph) and may not exist in
# this module call (e.g. a member-account invocation that only accepts an
# invitation). Resource-specific maps (members) are keyed by the same stable
# keys used on input for easy cross-referencing.
###############################################################################

# --- Behavior graph (keystone) ----------------------------------------------

output "id" {
 description = "The ID of the Detective behavior graph created by this module, or null when create_graph = false."
 value = try(aws_detective_graph.this["this"].id, null)
}

output "arn" {
 description = "ARN of the Detective behavior graph (cross-resource reference type) — format: arn:<partition>:detective:<region>:<account-id>:graph:<graph-id>. Null when create_graph = false. Pass this to member accounts' var.graph_arn."
 value = try(aws_detective_graph.this["this"].graph_arn, null)
}

output "graph_arn" {
 description = "The Detective behavior graph ARN (explicit alias of `arn`) — consumed by member-account module calls (var.graph_arn) and org-configuration wiring. Null when create_graph = false."
 value = try(aws_detective_graph.this["this"].graph_arn, null)
}

output "created_time" {
 description = "Date/time (UTC, extended RFC 3339) the graph was created, or null when create_graph = false."
 value = try(aws_detective_graph.this["this"].created_time, null)
}

output "tags_all" {
 description = "All tags on the graph, including those inherited from provider default_tags. Null when create_graph = false (the graph is the only taggable resource in this module)."
 value = try(aws_detective_graph.this["this"].tags_all, null)
}

output "effective_graph_arn" {
 description = "The graph ARN this module call actually operates against — this module's own graph when create_graph = true, or the caller-supplied var.graph_arn otherwise. Use this (not `arn`) when you need a non-null value regardless of invocation shape."
 value = local.graph_arn
}

# --- Members -----------------------------------------------------------------

output "member_ids" {
 description = "Map of member label => aws_detective_member id for every managed member."
 value = { for k, v in aws_detective_member.this: k => v.id }
}

output "member_statuses" {
 description = "Map of member label => current membership status (e.g. INVITED, VERIFICATION_IN_PROGRESS, ENABLED, DISABLED) for every managed member."
 value = { for k, v in aws_detective_member.this: k => v.status }
}

output "member_administrator_ids" {
 description = "Map of member label => AWS account ID of the administrator account for every managed member."
 value = { for k, v in aws_detective_member.this: k => v.administrator_id }
}

output "member_volume_usage_bytes" {
 description = "Map of member label => data volume in bytes per day ingested for every managed member."
 value = { for k, v in aws_detective_member.this: k => v.volume_usage_in_bytes }
}

# --- Organization admin account ---------------------------------------------

output "organization_admin_account_id" {
 description = "AWS account ID registered as the Detective delegated administrator, or null when enable_organization_admin_account is false."
 value = try(aws_detective_organization_admin_account.this["this"].id, null)
}

# --- Organization configuration ----------------------------------------------

output "organization_configuration_id" {
 description = "Identifier of the Detective behavior graph the organization configuration applies to (mirrors the graph id/ARN), or null when organization_configuration is not set."
 value = try(aws_detective_organization_configuration.this["this"].id, null)
}

output "organization_auto_enable" {
 description = "The applied auto_enable setting for organization_configuration, or null when organization_configuration is not set."
 value = try(aws_detective_organization_configuration.this["this"].auto_enable, null)
}

# --- Invitation accepter -------------------------------------------------------

output "invitation_accepter_id" {
 description = "Unique identifier of the Detective invitation accepter, or null when accept_invitation is false."
 value = try(aws_detective_invitation_accepter.this["this"].id, null)
}
