#!/usr/bin/env bash
# cline delivery plug — manual inbox checks only.
#
# Cline exposes no hook agmsg could write a delivery trigger into, so `off`
# is the only valid mode (enforced by delivery_modes=off in the manifest,
# which delivery.sh's central gate checks). These overrides keep apply /
# status / teardown from touching a hook file or another agent type's
# watchers. Sourced into delivery.sh's context.

# Nothing to write — manual-only, so no hooks_file is resolved or created.
agmsg_delivery_apply() { :; }

# No hook file to read; the mode is always off.
agmsg_delivery_status() { echo "mode: off"; }

# No watcher or bridge of our own. Do NOT fall through to the default
# teardown (which stops this project's watch.sh) — another agent type may
# hold a live watcher on the same project, and a cline `set off` must not
# disturb it.
agmsg_delivery_on_disable() {
  echo "Cline has no agmsg automatic delivery hook; manual inbox checks only."
}
