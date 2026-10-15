import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import test from "node:test";
import { bootId, currentExecutor, isAlive } from "../scripts/daemon/executor.mjs";

test("bootId is stable across calls and isAlive tells living/dead/wrong-boot apart", () => {
  assert.equal(bootId(), bootId(), "bootId must not change within the same boot");

  const self = currentExecutor();
  assert.equal(isAlive(self), true, "this process's own pid must read as alive");

  // A pid that has already exited, at the CURRENT boot id: must read as
  // confirmed dead (ESRCH), not "cannot tell".
  const dead = spawnSync(process.execPath, ["-e", "process.exit(0)"]);
  assert.equal(dead.status, 0);
  assert.equal(
    isAlive({ pid: dead.pid, bootId: self.bootId }),
    false,
    "an exited pid at the current boot id must read as confirmed dead",
  );

  // A boot id that does not match the current one must short-circuit to
  // confirmed dead even for this process's own (very much alive) pid --
  // no pid from a different boot can still be running.
  assert.equal(
    isAlive({ pid: self.pid, bootId: "0" }),
    false,
    "a mismatched boot id must read as confirmed dead regardless of the pid",
  );

  if (process.platform === "darwin") {
    // A record from when the boot id was kern.boottime seconds, shifted a
    // few seconds since by a clock adjustment, is still this boot -- but
    // only for a process older than the recorded claim (a pid born after
    // it is a reuse, e.g. after a quick restart).
    const boottime = spawnSync("sysctl", ["-n", "kern.boottime"], { encoding: "utf8" }).stdout;
    const legacy = String(Number(boottime.match(/sec\s*=\s*(\d+)/)[1]) - 3);
    const now = new Date().toISOString();
    assert.equal(isAlive({ pid: self.pid, bootId: legacy, startedAt: now }), true);
    assert.equal(isAlive({ pid: self.pid, bootId: legacy, startedAt: "2000-01-01T00:00:00.000Z" }), false);
    // No usable claim time: cannot tell, which must never read as dead.
    assert.equal(isAlive({ pid: self.pid, bootId: legacy, startedAt: null }), null);
  }
});
