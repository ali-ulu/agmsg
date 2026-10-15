<!-- Cline overlay. -->
<!-- agmsg:slot delivery -->
<!-- agmsg:render-overlay __AGENT_TYPE__ -->
  5. Cline has no agmsg automatic delivery hook. Keep delivery `off` and check `__CMD_PREFIX____SKILL_NAME__` manually.
<!-- /agmsg:slot delivery -->
<!-- agmsg:slot execute-extra -->
Cline runs headless (`cline -c <dir> "<prompt>"`), so a seat can be booted with an initial prompt. Note that a single-word prompt is taken for a command, so any boot prompt must be longer than one token.
<!-- /agmsg:slot execute-extra -->
<!-- agmsg:slot mode -->
If argument is "mode", run `delivery.sh status __AGENT_TYPE__ "$(pwd)"`.
Only `off` is supported for Cline; reject `monitor`, `turn`, and `both`.
<!-- /agmsg:slot mode -->
