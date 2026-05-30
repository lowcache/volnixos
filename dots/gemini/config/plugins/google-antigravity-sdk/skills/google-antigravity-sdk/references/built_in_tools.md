# Built-in Tools Reference

In the `LocalAgentConfig` (used for local development), all built-in tools are
**enabled** by default. However, `run_command` is **denied** by the default
`confirm_run_command()` policy — all other tools are allowed. See
[Safety Policies](safety_policies.md) to customize this behavior.

The following table lists all built-in tools available in the SDK and their
descriptions.

Tool Enum                     | Tool Name          | Description
----------------------------- | ------------------ | --------------------------
`BuiltinTools.LIST_DIR`       | `list_directory`   | List directory contents.
`BuiltinTools.SEARCH_DIR`     | `search_directory` | Search within directories.
`BuiltinTools.FIND_FILE`      | `find_file`        | Find files by name.
`BuiltinTools.VIEW_FILE`      | `view_file`        | View file contents.
`BuiltinTools.FINISH`         | `finish`           | Finish and return output.
`BuiltinTools.CREATE_FILE`    | `create_file`      | Create a new file.
`BuiltinTools.EDIT_FILE`      | `edit_file`        | Edit an existing file.
`BuiltinTools.RUN_COMMAND`    | `run_command`      | Execute a shell command.
`BuiltinTools.ASK_QUESTION`   | `ask_question`     | Ask user a question.
`BuiltinTools.START_SUBAGENT` | `start_subagent`   | Invoke a subagent.
`BuiltinTools.GENERATE_IMAGE` | `generate_image`   | Generate or edit images.

> [!NOTE] Some production backends may require additional environment or
> filesystem configuration to support these tools.
