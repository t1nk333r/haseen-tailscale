// node tests/service.test.js — drives the login/switch/setting state machine in
// Service.qml without Quickshell, and proves every argv it would hand to
// Process through a PATH shim that logs what it received.
//
// Harness technique ported from hehh2001/omarchy-tailscale-plus @426b3cc (MIT)
// tests/recovery.test.js: the function bodies and onExited handlers are lifted
// out of the QML source verbatim and run in a vm context with stub processes,
// so what is tested is the shipped code, not a re-derivation of it.
//
// Nothing here ever runs the real `tailscale`, `pkexec`, `xdg-open` or
// `wl-copy`: PATH is replaced with a directory of shims for every spawn.
const assert = require("node:assert/strict")
const fs = require("node:fs")
const os = require("node:os")
const path = require("node:path")
const vm = require("node:vm")
const { spawnSync } = require("node:child_process")
const Model = require("../Model.js")

const source = fs.readFileSync(require.resolve("../Service.qml"), "utf8")

function fn(name) {
  const match = source.match(new RegExp("^  function " + name + "\\([^]*?^  }", "m"))
  assert.ok(match, "function " + name + " present in Service.qml")
  return match[0]
}

function handler(processId) {
  const block = source.slice(source.indexOf("    id: " + processId + "\n"))
  const match = block.match(/    onExited: (function\(exitCode\) \{[^]*?^    })/m)
  assert.ok(match, "onExited for " + processId)
  return "(" + match[1] + ")(exitCode)"
}

// --- shim directory --------------------------------------------------------------
const shimDir = fs.mkdtempSync(path.join(os.tmpdir(), "tailscale-shim-"))
const logFile = path.join(shimDir, "argv.log")
function shim(name, body) {
  const file = path.join(shimDir, name)
  fs.writeFileSync(file, "#!/bin/sh\n" +
    "printf '%s' \"${0##*/}\" >> \"$SHIM_LOG\"\n" +
    "for a in \"$@\"; do printf ' %s' \"[$a]\" >> \"$SHIM_LOG\"; done\n" +
    "printf '\\n' >> \"$SHIM_LOG\"\n" + body + "\n")
  fs.chmodSync(file, 0o755)
}
shim("tailscale", [
  'case "$1 $2" in',
  '  "status --json") printf \'%s\' "$SHIM_STATUS"; exit 0;;',
  '  "debug prefs") printf \'%s\' "$SHIM_PREFS"; exit 0;;',
  '  "up "*|"up") printf \'To authenticate, visit:\\n\\n\\thttps://login.example/a/shim\\n\'; exit 0;;',
  '  "logout "*|"logout") exit "${SHIM_LOGOUT_RC:-0}";;',
  '  "set "*) [ -n "$SHIM_SET_ERROR" ] && { printf \'%s\\n\' "$SHIM_SET_ERROR" >&2; exit 1; }; exit 0;;',
  '  "switch "*) printf \'%s\' "$SHIM_SWITCH_OUT"; exit "${SHIM_SWITCH_RC:-0}";;',
  'esac',
  'exit 0',
].join("\n"))
shim("pkexec", '[ -n "$SHIM_PKEXEC_CANCEL" ] && exit 126\nexec "$@"')
shim("xdg-open", "exit 0")
shim("wl-copy", "while read -r _; do :; done; exit 0")

const env = Object.assign({}, process.env, { PATH: shimDir, SHIM_LOG: logFile })
function run(command, extra) {
  const result = spawnSync(command[0], command.slice(1), { encoding: "utf8", env: Object.assign({}, env, extra || {}), timeout: 5000 })
  assert.equal(result.error, undefined, "spawn " + command[0] + " through the shim: " + (result.error && result.error.message))
  return result
}
function logLines() { return fs.existsSync(logFile) ? fs.readFileSync(logFile, "utf8").trim().split("\n").filter(Boolean) : [] }
function resetLog() { fs.rmSync(logFile, { force: true }) }

// --- harness ------------------------------------------------------------------------
function stubProcess() { return { running: false, command: [], generation: 0 } }
function harness(overrides) {
  const c = {
    Model, console,
    installed: true, running: true, needsLogin: false, authUrl: "", blockedAuthUrl: "",
    controlUrl: Model.OFFICIAL_CONTROL_URL, operatorUser: "me", userName: "me", loginServer: "",
    prefsLoaded: true, acceptDns: true, acceptRoutes: true, allowLanAccess: false, shieldsUp: false, runSsh: true,
    runWebClient: false, advertiseExitNode: false, updateCheck: true, autoUpdate: false, reportPosture: false,
    changingSetting: "", settingExitNodeId: "", switchingAccountId: "", selectedAccountId: "2c0a",
    accounts: [{ id: "2c0a" }, { id: "9f" }], accountsAccessDenied: false,
    _desired: -1, _networkGeneration: 0, _statusValid: true, _prefsValid: true,
    _loginPlan: null, _loginStep: -1, _loginOutput: "", _loginError: "", _loginInProgress: false, _loginUrlOpened: false,
    _preLoginAuthUrl: "", _pendingLoginAfterRefresh: false, _switchTargetId: "", _lastAccountsRefreshMs: 5,
    _settingOutput: "", _settingError: "", _logoutOutput: "", _logoutError: "", _operatorOutput: "", _operatorError: "",
    _switchOutput: "", _switchError: "", _accountsOutput: "", _accountsError: "",
    actionStatus: "", lastError: "", statusText: "",
    loginBusy: false,
    logoutProcess: stubProcess(), operatorProcess: stubProcess(), loginProcess: stubProcess(),
    settingProcess: stubProcess(), switchProcess: stubProcess(), accountsProcess: stubProcess(),
    loginTimeoutTimer: { restart() { c.timerRestarted = true }, stop() { c.timerStopped = true } },
    actionStatusTimer: { restart() {} },
    delayedRefresh: { restart() { c.refreshes = (c.refreshes || 0) + 1 } },
    opened: [],
    Quickshell: { execDetached(argv) { c.opened.push(argv); run(argv) } },
    exec: [],
  }
  c.root = c
  Object.assign(c, overrides || {})
  vm.createContext(c)
  vm.runInContext([
    "beginNetworkAction", "elideStatus", "showActionError", "notice", "preferenceValue", "togglePreference",
    "loginPlanFor", "loginOrUp", "rebindLoginServer", "startLoginPlan", "runNextLoginStep", "failLoginStep",
    "maybeStartPendingLogin", "switchAccount", "openAuthUrl", "openAuthUrlFrom", "handleLoginOutput", "parseAccounts",
  ].map(fn).join("\n"), c)
  return c
}

// Run whatever a stub process was told to run through the shims, then feed the
// exit code back into the real onExited handler.
function settle(c, processId, extraEnv) {
  const proc = c[processId]
  assert.equal(proc.running, true, processId + " was started")
  const result = run(proc.command, extraEnv)
  proc.running = false
  c.exitCode = result.status
  const collectors = {
    logoutProcess: ["logoutStdout", "logoutStderr"], operatorProcess: ["operatorStdout", "operatorStderr"],
    settingProcess: ["settingStdout", "settingStderr"], switchProcess: ["switchStdout", "switchStderr"],
    accountsProcess: ["accountsStdout", "accountsStderr"],
  }[processId]
  if (collectors) { c[collectors[0]] = { text: result.stdout }; c[collectors[1]] = { text: result.stderr } }
  if (processId === "loginProcess") { c.handleLoginOutput(result.stdout, false); c.handleLoginOutput(result.stderr, true) }
  vm.runInContext(handler(processId), c)
  return result
}

const HEADSCALE = "https://headscale.example.com"

// --- 1. the ten switches: one argv each, no shell ---------------------------------
resetLog()
{
  const c = harness()
  for (const key of Object.keys(Model.PREFERENCE_FLAGS)) {
    c.togglePreference(key)
    assert.equal(c.changingSetting, key)
    settle(c, "settingProcess")
    assert.equal(c.changingSetting, "", key + " clears changingSetting")
    assert.equal(c.lastError, "", key)
  }
  const lines = logLines()
  assert.equal(lines.length, 10, "exactly ten tailscale invocations")
  for (const key of Object.keys(Model.PREFERENCE_FLAGS)) {
    const expect = "tailscale [set] [--" + Model.PREFERENCE_FLAGS[key] + "=" + (c.preferenceValue(key) ? "false" : "true") + "]"
    assert.ok(lines.indexOf(expect) !== -1, "shim saw: " + expect)
  }
  // A refused set surfaces the CLI's stderr instead of silently reverting.
  c.togglePreference("runSsh")
  settle(c, "settingProcess", { SHIM_SET_ERROR: "Access denied: set --ssh not permitted" })
  assert.match(c.lastError, /Access denied: set --ssh not permitted/)
  assert.equal(c.actionStatus, c.lastError)
  // Busy guard: nothing spawns while a set is in flight.
  c.settingProcess.running = true
  const before = logLines().length
  c.togglePreference("shieldsUp")
  assert.equal(logLines().length, before)
}
fs.writeFileSync(path.join(shimDir, "switches.log"), logLines().join("\n") + "\n")

// --- 2. login plans through the shim ------------------------------------------------
// Unchanged server: exactly one argv line.
resetLog()
{
  const c = harness({ running: false })
  c.loginOrUp(false)
  assert.equal(c._desired, 1, "plain turn-on is optimistic")
  settle(c, "loginProcess")
  assert.deepEqual(logLines(), ["tailscale [up]", "xdg-open [https://login.example/a/shim]"], "one up; the URL it printed is opened (turning on ended up needing auth)")
  assert.equal(c._loginPlan, null)
  assert.equal(JSON.stringify(c.opened), JSON.stringify([["xdg-open", "https://login.example/a/shim"]]))
}
// Changed server without confirmation: nothing runs, the panel is told to confirm.
resetLog()
{
  const c = harness({ loginServer: HEADSCALE, running: false, needsLogin: true })
  c.loginOrUp(false)
  assert.deepEqual(logLines(), [], "no logout without confirmation")
  assert.match(c.lastError, /confirm the login server row/)
  assert.equal(c.logoutProcess.running, false)
}
// Changed server, confirmed: logout → pkexec set --operator → up --login-server, in order.
resetLog()
{
  const c = harness({ loginServer: HEADSCALE })
  c.rebindLoginServer()
  assert.equal(c._loginInProgress, true)
  settle(c, "logoutProcess")
  assert.equal(c.operatorProcess.running, true, "logout success continues to the operator step")
  settle(c, "operatorProcess")
  assert.equal(c.operatorUser, "me")
  assert.equal(c.loginProcess.running, true, "operator success continues to up")
  settle(c, "loginProcess")
  assert.deepEqual(logLines(), [
    "tailscale [logout]",
    "pkexec [tailscale] [set] [--operator=me]",
    "tailscale [set] [--operator=me]",
    "tailscale [up] [--login-server=" + HEADSCALE + "]",
    "xdg-open [https://login.example/a/shim]",
  ])
  assert.equal(c._loginUrlOpened, true, "the URL the CLI printed was opened")
  assert.equal(JSON.stringify(c.opened), JSON.stringify([["xdg-open", "https://login.example/a/shim"]]))
  assert.equal(c._loginPlan, null, "plan cleared after the last step")
}
fs.writeFileSync(path.join(shimDir, "rebind.log"), logLines().join("\n") + "\n")
// Changed server, polkit prompt dismissed: stop after logout with a coherent message; up never runs.
resetLog()
{
  const c = harness({ loginServer: HEADSCALE })
  c.rebindLoginServer()
  settle(c, "logoutProcess")
  settle(c, "operatorProcess", { SHIM_PKEXEC_CANCEL: "1" })
  assert.equal(c.loginProcess.running, false, "up must not run as a non-operator")
  assert.equal(c._loginPlan, null)
  assert.equal(c._loginStep, -1)
  assert.equal(c._loginInProgress, false)
  assert.equal(c.lastError, "Logged out; authorization cancelled — run: sudo tailscale set --operator=me && tailscale up --login-server=" + HEADSCALE)
  assert.deepEqual(logLines(), ["tailscale [logout]", "pkexec [tailscale] [set] [--operator=me]"])
  assert.equal(c.refreshes, 1, "a refresh is queued so the panel shows the logged-out state")
}
// Logout itself fails: nothing else runs, and the user is told they are still where they were.
resetLog()
{
  const c = harness({ loginServer: HEADSCALE })
  c.rebindLoginServer()
  settle(c, "logoutProcess", { SHIM_LOGOUT_RC: "3" })
  assert.equal(c.operatorProcess.running, false)
  assert.match(c.lastError, /^Logout failed.*still on the current server$/)
  assert.deepEqual(logLines(), ["tailscale [logout]"])
}
// Fresh login on the same server while not operator: pkexec then up, no logout.
resetLog()
{
  const c = harness({ running: false, needsLogin: true, operatorUser: "" })
  c.loginOrUp(false)
  settle(c, "operatorProcess")
  settle(c, "loginProcess")
  assert.deepEqual(logLines(), ["pkexec [tailscale] [set] [--operator=me]", "tailscale [set] [--operator=me]", "tailscale [up]", "xdg-open [https://login.example/a/shim]"])
}
// A pending AuthURL that is not a web URL is shown, never opened.
resetLog()
{
  const c = harness({ running: false, needsLogin: true, authUrl: "--remote-debugging-port=1 https://evil.example/" })
  c.loginOrUp(false)
  assert.equal(c.blockedAuthUrl, "", "loginPlan ignored it")
  assert.equal(c.loginProcess.running, true, "and fell through to a fresh up")
  assert.equal(c.openAuthUrl(c.authUrl), false)
  assert.equal(c.blockedAuthUrl, c.authUrl)
  assert.equal(JSON.stringify(c.opened), "[]")
  assert.match(c.lastError, /not a web URL/)
}
// Busy guard: a second rebind while one is in flight is ignored.
{
  const c = harness({ loginServer: HEADSCALE })
  c.rebindLoginServer()
  c.loginBusy = true
  const stepBefore = c._loginStep
  c.rebindLoginServer()
  assert.equal(c._loginStep, stepBefore)
}

// --- 3. switch outcomes -------------------------------------------------------------
resetLog()
{
  // Bad ids never reach argv.
  const c = harness()
  c.switchAccount("-list")
  assert.equal(c.switchProcess.running, false)
  assert.match(c.lastError, /oddly named/)
  assert.deepEqual(logLines(), [])
}
{
  // Switch landed on a logged-out profile: pending login waits for a fresh snapshot, then starts.
  const c = harness({ loginServer: "" })
  c.switchAccount("9f")
  assert.equal(c._statusValid, false, "beginNetworkAction invalidated the snapshot")
  settle(c, "switchProcess", { SHIM_SWITCH_OUT: 'Switching to account "9f"\nLogged out.\nTo log in, run:\n  tailscale up\n' })
  assert.equal(c._pendingLoginAfterRefresh, true)
  assert.equal(c.loginProcess.running, false, "no login until the new profile has been read")
  assert.equal(c.switchingAccountId, "")
  // Fresh status+prefs describing the new profile arrive.
  c.needsLogin = true; c.running = false; c.controlUrl = ""
  c._statusValid = true; c._prefsValid = true
  c.maybeStartPendingLogin()
  assert.equal(c._pendingLoginAfterRefresh, false)
  assert.equal(c.loginProcess.running, true)
  assert.equal(JSON.stringify(c.loginProcess.command), JSON.stringify(["tailscale", "up"]))
  assert.deepEqual(logLines(), ["tailscale [switch] [9f]"])
}
{
  // Missing profile: plain error, and the structural check on the refreshed list confirms it is gone.
  const c = harness()
  c.switchAccount("9f")
  settle(c, "switchProcess", { SHIM_SWITCH_OUT: "", SHIM_SWITCH_RC: "1" })
  assert.equal(c._pendingLoginAfterRefresh, false, "a missing profile does not start a login")
  assert.equal(c._switchTargetId, "9f", "kept for the structural check")
  c.accountsStdout = { text: JSON.stringify([{ id: "2c0a", selected: true }]) }
  c.accountsStderr = { text: "" }
  c.exitCode = 0
  vm.runInContext(handler("accountsProcess"), c)
  assert.equal(c._switchTargetId, "")
  assert.match(c.lastError, /no longer exists/)
  assert.equal(c.accounts.length, 1)
}
{
  // Successful switch: nothing pending.
  const c = harness()
  c.switchAccount("9f")
  settle(c, "switchProcess", { SHIM_SWITCH_OUT: 'Switching to account "9f"\nSuccess.\n' })
  assert.equal(c._pendingLoginAfterRefresh, false)
  assert.equal(c.lastError, "")
}

// --- 4. the shim log itself ----------------------------------------------------------
const all = fs.readFileSync(path.join(shimDir, "switches.log"), "utf8") + fs.readFileSync(path.join(shimDir, "rebind.log"), "utf8")
for (const line of all.trim().split("\n")) {
  assert.ok(/^(tailscale|pkexec|xdg-open) (\[[^\]]*\] ?)+$/.test(line), "every logged argv is bracketed elements only: " + line)
  assert.equal(line.indexOf("sh -c"), -1)
  assert.equal(line.indexOf("bash"), -1)
}
console.log("service state-machine tests passed; shim dir " + shimDir)
console.log("--- switches.log ---\n" + fs.readFileSync(path.join(shimDir, "switches.log"), "utf8") + "--- rebind.log ---\n" + fs.readFileSync(path.join(shimDir, "rebind.log"), "utf8"))
