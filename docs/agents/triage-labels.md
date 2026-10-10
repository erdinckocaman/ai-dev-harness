# Triage labels

The skills use five canonical triage roles. This file maps each role to the label string of
this workspace's issue tracker (`issue-tracker.md`). Here each label string is the same as the
role name.

| Role | Label in this tracker | Meaning |
|---|---|---|
| `needs-triage` | `needs-triage` | A maintainer must evaluate the ticket. |
| `needs-info` | `needs-info` | The ticket waits for more information from the reporter. |
| `ready-for-agent` | `ready-for-agent` | The ticket is fully specified. An agent can do it without supervision. |
| `ready-for-human` | `ready-for-human` | A human must do the ticket. |
| `wontfix` | `wontfix` | Nobody will do the ticket. |

When a skill names a role (for example, "apply the AFK-ready triage label"), write the label
string from this table into the ticket's `Status:` line.

To use a different vocabulary, change the middle column only. The skills keep the role names.
