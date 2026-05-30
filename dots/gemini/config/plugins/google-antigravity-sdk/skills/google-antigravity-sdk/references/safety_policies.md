# Safety Policies in Google Antigravity SDK

Reference guide for configuring access control and safety policies in the Google
Antigravity SDK.

## Overview

The Google Antigravity SDK provides a declarative policy system to control which
tools an agent can execute. Policies are evaluated using a priority-based model
to ensure safety and prevent unauthorized actions.

## Default Behavior

By default, `LocalAgentConfig` uses `policy.confirm_run_command()` which:

-   **Denies** `run_command` (shell execution is blocked)
-   **Allows** all other tools (view, edit, create files, etc.)

This means new agents are **conservative by default** — they cannot execute shell
commands unless you explicitly opt in.

If `workspaces` is set on the config, `policy.workspace_only()` is also
automatically prepended, restricting file tools (`view_file`, `create_file`,
`edit_file`) to the configured workspace directories.

### Interactive Sessions

When using `run_interactive_loop()`, the default deny on `run_command` is
automatically upgraded to `ask_user` — the user gets a y/n confirmation prompt
instead of a hard denial.

### Restoring Permissive Behavior

To allow all tools (including `run_command`), pass `policy.allow_all()`:

```python
from google.antigravity import LocalAgentConfig
from google.antigravity.hooks import policy

config = LocalAgentConfig(
    system_instructions="You are a helpful assistant.",
    policies=[policy.allow_all()],
)
```

## Policy Resolution Order

Policies are evaluated in the following order of precedence (highest to lowest):

1. **Specific Deny**: `policy.deny("tool_name", ...)`
2. **Specific Ask**: `policy.ask_user("tool_name", ...)`
3. **Specific Allow**: `policy.allow("tool_name", ...)`
4. **Wildcard Deny**: `policy.deny("*", ...)`
5. **Wildcard Ask**: `policy.ask_user("*", ...)`
6. **Wildcard Allow**: `policy.allow("*", ...)`

Within each priority group, the **first match wins** (short-circuit evaluation).

## Configuration

Use the `google.antigravity.hooks.policy` module to define policies.

### Allow

Approves tool calls without confirmation.

```python
from google.antigravity.hooks import policy

# Allow all calls to view_file

policy.allow("view_file")
```

### Deny

Blocks tool calls immediately.

```python
from google.antigravity.hooks import policy

# Deny all calls to run_command

policy.deny("run_command")
```

### Ask User

Requires user confirmation before execution. Must provide a handler.

```python
from google.antigravity.hooks import policy

async def my_approval_handler(tool_call):
  # Custom logic to ask user or auto-approve
  # Return True to allow, False to deny
  return True

policy.ask_user("run_command", handler=my_approval_handler)
```

### Wildcards

-   `policy.allow_all()`: Approves all tool calls. Equivalent to `allow("*")`.
-   `policy.deny_all()`: Denies all tool calls. Equivalent to `deny("*")`.

### Convenience Presets

-   `policy.confirm_run_command()`: Denies `run_command`, allows everything else.
    This is the **default** policy. Optionally accepts a `handler` to use
    `ask_user` instead of `deny`.
-   `policy.workspace_only(workspaces)`: Restricts `view_file`, `create_file`,
    and `edit_file` to paths within the given workspace directories.
    Automatically applied when `LocalAgentConfig.workspaces` is set.

## Predicates (Argument Checking)

You can use the `when` parameter to restrict policies based on tool arguments.
The predicate receives the tool arguments as a dictionary.

```python
from google.antigravity.hooks import policy

# Deny run_command if it contains 'rm'
policy.deny(
    "run_command",
    when=lambda args: "rm" in args.get("CommandLine", ""),
    name="deny_rm",
)
```

> [!CAUTION] If a predicate raises an exception during evaluation, the policy
> **fails closed** and treats it as a match (i.e., the decision for that policy
> applies).

## Minimal Safe Templates

### Deny by Default (Recommended for Production)

Start by denying everything and selectively allow safe tools.

```python
from google.antigravity import Agent, LocalAgentConfig, CapabilitiesConfig
from google.antigravity.hooks import policy

policies = [
    policy.deny_all(),
    policy.allow("view_file"),
    policy.allow("code_search"),
    policy.ask_user("run_command", handler=my_approval_handler),
]

config = LocalAgentConfig(
    system_instructions="You are a helpful assistant.",
    capabilities=CapabilitiesConfig(),  # Enables write tools
    policies=policies,
)
```

### Safe Default (No Configuration Needed)

The default `confirm_run_command()` policy is suitable for most use cases. Simply
create a config without specifying policies:

```python
from google.antigravity import Agent, LocalAgentConfig

# run_command is denied, all other tools allowed
config = LocalAgentConfig(
    system_instructions="You are a helpful assistant.",
)
```

### Allow All (Development Only)

Use only for local development where safety is not a concern.

```python
from google.antigravity import Agent, LocalAgentConfig, CapabilitiesConfig
from google.antigravity.hooks import policy

config = LocalAgentConfig(
    system_instructions="You are a helpful assistant.",
    capabilities=CapabilitiesConfig(),
    policies=[policy.allow_all()],
)
```
