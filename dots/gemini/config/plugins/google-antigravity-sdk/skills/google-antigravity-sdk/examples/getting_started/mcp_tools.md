
# Model Context Protocol (MCP)

This example demonstrates how to connect an agent to an external Model Context
Protocol (MCP) server. The SDK supports both `stdio` and `sse` (Server-Sent
Events) transports.

For conceptual details and information on permissions, see the
[MCP Integration Reference Guide](../../references/mcp_integration.md).

## Connecting via Stdio

Assume we have an MCP server (e.g., `mcp_server.py`) using the `FastMCP` library
that exposes an `add_numbers` tool:

```python
from mcp.server import fastmcp

mcp = fastmcp.FastMCP("MathServer")


@mcp.tool()
def add_numbers(a: int, b: int) -> int:
    """Adds two numbers."""
    return a + b


mcp.run()
```

To connect the agent to this MCP server via `stdio` transport:

```python
from google.antigravity import Agent, LocalAgentConfig, types

mcp_servers = [
    types.McpStdioServer(
        command="python3",
        args=["mcp_server.py"],
    )
]

config = LocalAgentConfig(mcp_servers=mcp_servers)

async with Agent(config) as agent:
    response = await agent.chat("Add 5 and 3 using the add_numbers tool.")
    print(await response.text())
```

## Connecting via SSE

You can also connect to a remote MCP server running as a web service using the
`sse` transport:

```python
from google.antigravity import Agent, LocalAgentConfig, types

mcp_servers = [
    types.McpSseServer(
        url="https://example.com/mcp/sse",
        headers={"Authorization": "Bearer your-token-here"},  # Optional headers
    )
]

config = LocalAgentConfig(mcp_servers=mcp_servers)

async with Agent(config) as agent:
    response = await agent.chat("Ask the remote MCP server to perform a task.")
    print(await response.text())
```
