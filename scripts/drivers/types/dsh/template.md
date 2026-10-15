<!-- DeepSeek Harness overlay. -->
<!-- agmsg:slot delivery -->
<!-- agmsg:render-overlay __AGENT_TYPE__ -->
  5. DeepSeek Harness has no agmsg automatic delivery hook. Keep delivery `off` and check `__CMD_PREFIX____SKILL_NAME__` manually.
<!-- /agmsg:slot delivery -->
<!-- agmsg:slot execute-extra -->
DeepSeek Harness is an Electron desktop app, not a plain CLI on PATH: a headless run goes through the Electron host (`ELECTRON_RUN_AS_NODE=1 "<install>/DeepSeek Harness.exe" --expose-internals "<install>/resources/app.asar/dsh/node_modules/@deepseek-ai/dsh-desktop-host/lib/cli.js" headless "<prompt>"`). It is not spawnable: the run needs `DEEPSEEK_API_KEY`, which the desktop keeps in its own credentials service rather than the environment, so a headless boot exits `MISSING_CREDENTIAL`. From Git Bash, pass a `C:/...` style install path — the shipped `dsh.cmd` breaks on `$HOME`'s `/c/...` form when the path contains spaces.
<!-- /agmsg:slot execute-extra -->
<!-- agmsg:slot mode -->
If argument is "mode", run `delivery.sh status __AGENT_TYPE__ "$(pwd)"`.
Only `off` is supported for DeepSeek Harness; reject `monitor`, `turn`, and `both`.
<!-- /agmsg:slot mode -->
