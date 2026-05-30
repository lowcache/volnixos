"""
Core orchestration loop combining local file skills and remote mcp-nixos gateway capabilities.
"""
import json
from typing import Dict, Any, List
from .prompt import NIX_EXPERT_SYSTEM_PROMPT
from .tools import LOCAL_NIX_TOOLS

class NixExpertAgent:
    def __init__(self, model_client: Any, mcp_gateway_client: Any):
        """
        Initialize agent with the LLM client and your unified MCP gateway connection.
        """
        self.model_client = model_client
        self.mcp = mcp_gateway_client
        self.system_prompt = NIX_EXPERT_SYSTEM_PROMPT

    async def get_combined_tools(self) -> List[Dict[str, Any]]:
        """
        Fetches schemas dynamically from your gateway (including mcp-nixos) 
        and mixes them with local file tools.
        """
        # Fetch available tool definitions exposed via one call to the gateway
        gateway_tools = await self.mcp.list_tools() 
        
        # Local schema definitions for file manipulation
        local_tool_schemas = [
            {
                "name": "nix_eval_error_debugger",
                "description": "Parses raw Nix evaluation error stack traces to find the precise failure root cause.",
                "parameters": {
                    "type": "object",
                    "properties": {"stderr_trace": {"type": "string"}},
                    "required": ["stderr_trace"]
                }
            },
            {
                "name": "ast_safe_modifier",
                "description": "Edits a local Nix file structurally to add/modify packages or configurations safely.",
                "parameters": {
                    "type": "object",
                    "properties": {
                        "file_path": {"type": "string"},
                        "target_attr": {"type": "string"},
                        "new_value": {"type": "string"}
                    },
                    "required": ["file_path", "target_attr", "new_value"]
                }
            },
            {
                "name": "format_nix_file",
                "description": "Must be executed immediately after any file modification operation to validate layout syntax, fix alignments, and trap unclosed braces or missing semicolons.",
                "parameters": {
                    "type": "object",
                    "properties": {
                        "file_path": {"type": "string", "description": "Absolute or relative path to the modified .nix file."}
                    },
                    "required": ["file_path"]
                }
            },
            {
                "name": "run_nix_environment_diagnostic",
                "description": "Executes system-wide nix-doctor tests to diagnose channel state failures, corrupted store profiles, or general system health regressions.",
                "parameters": {
                    "type": "object",
                    "properties": {}
                }
            }
        ]
        return gateway_tools + local_tool_schemas

    async def execute_task(self, user_input: str, file_context: Dict[str, str]) -> str:
        """
        Asynchronous execution loop utilizing mixed local and gateway capabilities.
        """
        available_tools = await self.get_combined_tools()
        
        messages = [
            {"role": "system", "content": self.system_prompt},
            {"role": "user", "content": f"Context Files:\n{json.dumps(file_context, indent=2)}\n\nProblem: {user_input}"}
        ]
        
        while True:
            response = await self.model_client.generate_completion(
                messages=messages,
                tools=available_tools
            )
            
            if response.has_tool_calls:
                for call in response.tool_calls:
                    # Check if the tool is a local python skill
                    if call.name in LOCAL_NIX_TOOLS:
                        result = LOCAL_NIX_TOOLS[call.name](**call.arguments)
                    else:
                        # Otherwise, route through the centralized MCP gateway (handles mcp-nixos tools like 'nix')
                        result = await self.mcp.call_tool(call.name, call.arguments)
                        
                    messages.append({"role": "tool", "tool_call_id": call.id, "content": json.dumps(result)})
                continue
                
            return response.text
