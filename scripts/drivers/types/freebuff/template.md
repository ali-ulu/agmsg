<!-- Freebuff overlay. -->
<!-- agmsg:slot delivery -->
<!-- agmsg:render-overlay __AGENT_TYPE__ -->
  5. Freebuff has no agmsg automatic delivery hook. Keep delivery `off` and check `__CMD_PREFIX____SKILL_NAME__` manually.
<!-- /agmsg:slot delivery -->
<!-- agmsg:slot execute-extra -->
Freebuff is not spawnable: it ships only a TUI and `login`, with no print or headless mode that agmsg could pre-seed with an initial `actas` prompt, so `spawn` is refused rather than pretending to start a seat. A seat is driven by the human at the TUI; it reads MCP servers from `~/.agents/mcp.json` and standing instructions from `~/.knowledge.md`.
<!-- /agmsg:slot execute-extra -->
<!-- agmsg:slot mode -->
If argument is "mode", run `delivery.sh status __AGENT_TYPE__ "$(pwd)"`.
Only `off` is supported for Freebuff; reject `monitor`, `turn`, and `both`.
<!-- /agmsg:slot mode -->
