"""
Central Routing Registry for all antigravity Swarm Experts.
"""
from typing import Any
from .nix_expert import NixExpertAgent

def route_to_agent(agent_name: str, model_client: Any, mcp_gateway_client: Any) -> Any:
    """
    Factory pattern to instantiate and return the requested sub-agent swarm.
    """
    name_lower = agent_name.lower()
    
    if name_lower == "nix" or name_lower == "nixos":
        return NixExpertAgent(model_client, mcp_gateway_client)
        
    # Future agents plug in here cleanly:
    # if name_lower == "solana":
    #     return SolanaAuditorAgent(model_client)
        
    raise ValueError(f"Target expert agent '{agent_name}' is not registered in the swarm.")

__all__ = ["route_to_agent"]
