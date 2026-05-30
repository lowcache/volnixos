This server manages 80 tools across 6 backends.
Use gateway_search_tools FIRST to find relevant tools by keyword before invoking.
Tool schemas are not listed directly so the prompt stays compact.

Discovery pattern:
1. gateway_search_tools(query="your keyword") -- find tools matching your need
2. gateway_invoke(server="X", tool="Y", arguments={...}) -- call the tool

Direct listing (when you know the backend):
- gateway_list_tools(server="brave") -- list tools from a specific backend
- gateway_list_servers -- list all backends with status
