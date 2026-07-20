# terraform-aws-detective — SCOPE

Composite module for Amazon Detective: the behavior graph, member-account invitations, the
invitation accepter (member-side), and AWS Organizations delegated-administrator / org-wide
auto-enrollment configuration. A single module call, invoked from the appropriate account context,
builds one leg of a multi-account Detective investigation graph aligned with the Casey's (NPI / GLBA /
FCA) baseline. **An AWS account may own only one Detective behavior graph per Region.**

- **Module type:** Composite
- **Primary resource (keystone):** `aws_detective_graph.this` (guarded by `var.create_graph`,
  default `true`, rendered behind a `for_each` keyed `"this"` so the module can also run with
  `create_graph = false` — see `## Design decisions`)

## In-scope resources

The module manages **all** of the following (allow-list):

- `aws_detective_graph` — keystone (the behavior graph; one per account per Region)
- `aws_detective_member` — member-account invitations (`map(object(...))`, `for_each`) — created
  from the graph-owning (administrator) account
- `aws_detective_invitation_accepter` — member-side invitation acceptance — created from the
  INVITED MEMBER account's own provider context (`var.accept_invitation`)
- `aws_detective_organization_admin_account` — registers the org's Detective delegated
  administrator — created from the Organizations MANAGEMENT (primary) account
  (`var.enable_organization_admin_account`)
- `aws_detective_organization_configuration` — org-wide auto-enrollment policy — created from the
  Detective DELEGATED ADMINISTRATOR account (`var.organization_configuration`)

## Out-of-scope resources (consumed by reference)

Referenced by id/ARN/account-id, never created here:

- **Amazon GuardDuty** — GuardDuty findings, VPC Flow Logs, and DNS logs are Detective's primary
  data sources. Detective ingests them automatically once enabled; this module does **not** enable
  or configure GuardDuty. **`terraform-aws-guardduty` should typically be enabled first** — Detective
  without GuardDuty still ingests VPC Flow Logs/DNS/CloudTrail-derived data, but the investigative
  value is materially lower without GuardDuty findings to pivot from.
- **AWS Organizations itself** — `aws_organizations_organization` / `aws_organizations_account` /
  the `aws_service_access_principals` trusted-access toggle for `detective.amazonaws.com` live in
  `terraform-aws-organizations` (Phase 7) or the root module. This module assumes an Organization
  already exists and Detective trusted access is already enabled when the organization
  admin-account / org-configuration resources are used.
- **Member AWS accounts** — referenced by 12-digit account ID / email; not created here.
- **Security Hub integration** — Detective findings surfaced in Security Hub are configured in
  `terraform-aws-security-hub`, not here.

## Consumes

| Input | Type | Source module |
|---|---|---|
| `graph_arn` (when `create_graph = false`) | `string` (Detective graph ARN) | Another invocation of this same module (administrator account's `arn`/`graph_arn` output) |
| `organization_admin_account_id` | `string` (12-digit account id) | Caller-supplied, or `data.aws_organizations_organization` / `data.aws_caller_identity` in the root module — **not** a `terraform-aws-organizations` output today (Phase 7, not yet built), matching the `terraform-aws-inspector2` precedent |
| `members[*].account_id` | `string` (12-digit account id) | Caller-supplied member/child account ids |

> **Foundation-adjacent module** — Detective consumes GuardDuty's *output* (findings) implicitly at
> the data-plane level, but has no Terraform-level dependency on `terraform-aws-guardduty`; the two
> modules are ordered by operational recommendation, not by a `depends_on` / input wiring.

## Required IAM permissions

Least-privilege actions the Terraform identity needs. Split by resource because the organization
admin-account and org-configuration paths run from **different accounts** (management vs.
delegated administrator) and pull in `organizations:*` read actions alongside `detective:*`.

| Action | Required for |
|---|---|
| `detective:CreateGraph`, `detective:DeleteGraph`, `detective:ListGraphs`, `detective:TagResource`, `detective:UntagResource`, `detective:ListTagsForResource` | `aws_detective_graph` lifecycle / tagging (the only taggable resource) |
| `detective:CreateMembers`, `detective:DeleteMembers`, `detective:GetMembers`, `detective:ListMembers` | `aws_detective_member` |
| `detective:AcceptInvitation`, `detective:GetMembers`, `detective:DisassociateMembership` | `aws_detective_invitation_accepter` — run from the MEMBER account |
| `detective:EnableOrganizationAdminAccount`, `detective:DisableOrganizationAdminAccount`, `detective:ListOrganizationAdminAccounts` | `aws_detective_organization_admin_account` — run from the Organizations **management** account |
| `organizations:EnableAWSServiceAccess`, `organizations:ListDelegatedAdministrators`, `organizations:RegisterDelegatedAdministrator`, `organizations:DeregisterDelegatedAdministrator`, `organizations:DescribeOrganization`, `organizations:DescribeAccount` | Delegated-admin registration is an Organizations-service action, not purely a Detective action — run from the **management account** |
| `detective:UpdateOrganizationConfiguration`, `detective:DescribeOrganizationConfiguration` | `aws_detective_organization_configuration` — run from the **delegated administrator** account |

No `iam:PassRole` required by this module.

## AWS Prerequisites

- **Amazon Detective works best with GuardDuty already enabled.** Detective ingests GuardDuty
  findings, VPC Flow Logs, and DNS query logs as its primary evidence sources. Enable
  `terraform-aws-guardduty` in the same account/Region before (or alongside) this module for the
  investigation graph to be materially useful — Detective will still enable and ingest VPC
  Flow/DNS data without GuardDuty, but with a narrower analytical surface.
- **One behavior graph per account per Region.** Creating a second `aws_detective_graph` in the
  same account + Region fails — design accordingly (this is why `create_graph` is a toggle rather
  than an always-on resource).
- **Organization-wide delegated administrator — mirrors GuardDuty/Security Hub exactly.** Detective
  supports AWS Organizations integration the same way GuardDuty and Security Hub do: one designated
  delegated administrator account manages the org's Detective behavior graph and can auto-enroll
  new accounts. The delegated administrator must be registered
  (`aws_detective_organization_admin_account`, from the management account) before
  `aws_detective_organization_configuration` can be applied (from the delegated administrator
  account) — see `## Provider gotchas` for the ordering trap.
- **Detective trusted access for AWS Organizations** (`aws_service_access_principals` including
  `detective.amazonaws.com`) must already be enabled on the Organization before
  `aws_detective_organization_admin_account` succeeds — a one-time Organizations-level action
  typically performed in the root module or via `terraform-aws-organizations`, outside this module's
  control.
- **No service-linked role** is documented as required for Detective itself.
- **Quotas** (Region-specific; see the Detective User Guide):
  - **1 behavior graph** per account per Region.
  - **1,200 member accounts** per behavior graph (invited or organization-enrolled, combined).
  - **Data source eligibility window** — Detective can only ingest up to the account's log
    retention; enabling Detective late means historical data prior to enablement is not
    retroactively analyzed.

## Emits

| Output | Description | Consumed by |
|---|---|---|
| `id` | Detective graph id, or `null` when `create_graph = false` | Audit/state inspection |
| `arn` | Graph ARN (`arn:<partition>:detective:<region>:<acct>:graph:<graph-id>`) — cross-resource reference type, or `null` when `create_graph = false` | Member-account module calls' `graph_arn` input; Security Hub integration; audit |
| `graph_arn` | Explicit alias of `arn` | Same as `arn` — offered for wiring clarity |
| `effective_graph_arn` | The graph ARN this call actually operates against (own graph OR caller-supplied `var.graph_arn`) — **never null** when the module manages any child resource | Internal wiring reference for callers who need a guaranteed non-null value |
| `created_time` | Graph creation timestamp, or `null` when `create_graph = false` | Audit |
| `tags_all` | All tags incl. provider `default_tags` (on the graph only) — `null` when `create_graph = false` | Governance/audit |
| `member_ids` / `member_statuses` / `member_administrator_ids` / `member_volume_usage_bytes` | Maps of member label → id / status / administrator account id / daily ingest volume | Org rollup, membership health monitoring |
| `organization_admin_account_id` | Registered delegated administrator account id, or `null` | Audit; cross-check against `terraform-aws-guardduty` / `terraform-aws-security-hub` delegated admin |
| `organization_configuration_id` / `organization_auto_enable` | Org configuration state, or `null` | Compliance reporting |
| `invitation_accepter_id` | Accepter id, or `null` when `accept_invitation = false` | Audit/state inspection |

## Provider gotchas

- **One graph per account per Region (hard limit).** Do not instantiate this module twice with
  `create_graph = true` in the same account + Region; the second `aws_detective_graph` will fail.
- **Cross-account shape is NOT single-call by default.** The graph owner and each member account
  are different AWS accounts/providers. A typical rollout invokes this module twice: once from the
  administrator account (`create_graph = true`, `members = {...}`) and once per member account
  (`create_graph = false`, `accept_invitation = true`, `graph_arn` = the administrator's `arn`
  output), each with its own `providers = { aws = aws.<account_alias> }`. A single-call, multi-provider
  demo/test invocation is possible (see README example) but is the exception, not the norm.
- **A member must ACCEPT before it is fully part of the graph.** `aws_detective_member` (created by
  the administrator) only sends the invitation; `aws_detective_invitation_accepter` — run in the
  MEMBER account's own provider context — completes the join. Until accepted, the member's status
  stays `INVITED`/`VERIFICATION_IN_PROGRESS`, not `ENABLED`. This mirrors the cross-account accepter
  pattern used elsewhere in this library (e.g. `aws_guardduty_invite_accepter`).
- **`aws_detective_organization_configuration` requires the caller to already be the delegated
  administrator.** Applying it before `aws_detective_organization_admin_account` exists fails at
  the API level, not at plan time — an eventual-consistency / ordering trap, not a
  schema-validated constraint. The module sequences `organization_admin_account` before
  `organization_configuration` via an explicit `depends_on` (no direct attribute reference exists
  between them) for the single-call case; in the more common two-account rollout, apply the
  admin-account registration first, then the org configuration in a subsequent apply from the
  delegated administrator's provider.
- **`aws_detective_organization_configuration` has no meaningful destroy/import behavior.** Per the
  provider docs, Terraform assumes management of this resource automatically without import and
  performs no action on removal from configuration — removing it from state does not revert
  auto-enrollment on the AWS side; treat it as a policy toggle you manage forward, not a
  fully-reversible resource.
- **`tags` vs `tags_all`.** Only `aws_detective_graph` is taggable in the provider schema.
  `aws_detective_member`, `aws_detective_invitation_accepter`,
  `aws_detective_organization_admin_account`, and `aws_detective_organization_configuration` accept
  no `tags` argument — `var.tags` is wired to the graph alone, and `tags_all` is `null` whenever
  `create_graph = false`.
- **No configurable `timeouts` block on any of the five resources** (verified against the provider
  schema, v6.54.0) — `var.timeouts` is accepted for interface consistency but not wired anywhere;
  see `variables.tf`.
- **`arn` (via `graph_arn`) is the cross-resource reference type**; the plain Terraform `id` on
  every Detective resource in this family is either the same value as the ARN/graph identifier or a
  synthetic composite — always prefer `arn`/`graph_arn`/`effective_graph_arn` for wiring.
- **No `us-east-1` global-resource requirement** — Detective is a purely Regional service
  throughout; there is no CloudFront/WAFv2/ACM-style global coupling here.

## Secure-by-default decisions

| Posture | Default | Opt-out |
|---|---|---|
| Organization-wide auto-enrollment | `organization_configuration = null` (no auto-enrollment — accounts are invited individually via `members`) | Set `organization_configuration = { auto_enable = true }` for automatic, continuous coverage of new org accounts — **recommended** for the Casey's NPI/GLBA baseline (no coverage gap while a human remembers to invite a new account), but trades away Terraform-as-single-source-of-truth for membership; document the choice per `## Provider gotchas` |
| Member invitation email | `disable_email_notification = false` (root user of the invited account IS notified) | Set `true` per-member to suppress the root-user email (the AWS Personal Health Dashboard alert still fires) |
| Tagging | `var.tags` applied to the graph by default | n/a — the graph is always tagged when created; there is no encryption/public-access toggle on this service to opt out of |

## Design decisions

- **The keystone graph is itself toggleable (`create_graph`, default `true`).** This mirrors
  `terraform-aws-inspector2`'s "individually toggleable switches" philosophy: a member-account
  invocation (`accept_invitation = true`) does not need to force-create its own graph, since
  Detective member accounts do not own a graph — they attach to the administrator's. Because of
  this, the graph is rendered with a guarded `for_each` keyed `"this"`, and every graph-derived
  output uses `try(..., null)`.
- **`local.graph_arn` (and the `effective_graph_arn` output) resolve the "which graph does this
  call operate against" question once**, so every child resource (`members`,
  `organization_configuration`, `invitation_accepter`) references a single local value regardless
  of whether this call owns the graph or attaches to an external one via `var.graph_arn`.
- **GuardDuty is deliberately out of scope** — it is a sibling module
  (`terraform-aws-guardduty`) that Detective consumes at the data-plane level (not via Terraform
  wiring). Building/enabling it first is documented as an operational recommendation, not enforced
  as a hard Terraform dependency, since Detective can be enabled (with reduced value) without it.
- **AWS Organizations itself is deliberately excluded**, consistent with `terraform-aws-inspector2`
  and `terraform-aws-guardduty`: this module accepts raw account-id strings for
  `organization_admin_account_id` and `members[*].account_id` rather than blocking on the Phase 7
  `terraform-aws-organizations` module.
- **The organization admin-account and org-configuration resources are individually toggleable**
  (`enable_organization_admin_account` / `organization_configuration != null`) rather than bundled,
  because they must be applied from two different accounts (management vs. delegated
  administrator) in the typical rollout — bundling them into one always-created pair would
  misrepresent how AWS actually enforces that account-context split.
