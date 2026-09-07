// node tests/model.test.js — no framework, exits non-zero on the first failure.
//
// Cases marked "ported" come from hehh2001/omarchy-tailscale-plus @426b3cc
// (MIT) tests/model.test.js and tests/recovery.test.js.
//
// Facts observed on tailscale 1.102.3 (not assumed) that these tests encode:
// - `tailscale switch <id>` onto a logged-out profile exits 0 and prints
//   "Logged out." / "To log in, run:" / "  tailscale up" with the backend in
//   NeedsLogin; a profile that does not exist prints `No profile named "x"`
//   and exits 1 (cmd/tailscale/cli/switch.go).
// - `tailscale logout` deletes the current profile and switches tailscaled to
//   a new empty profile whose prefs carry no OperatorUser, so a non-root
//   operator's LocalAPI connection is read-only until `set --operator` runs
//   again (ipn/ipnlocal/local.go Logout, ipn/ipnauth IsReadonlyConn).
// - `tailscale debug prefs` exposes every pref the panel switches; `tailscale
//   status --json` exposes none of them, only ExitNodeStatus{ID,Online}.
// - `tailscale set --help` spells the posture flag `--report-posture`; it
//   reads back from debug prefs as PostureChecking.
const assert = require("node:assert/strict")
const model = require("../Model.js")

const OFFICIAL = "https://controlplane.tailscale.com"
const HEADSCALE = "https://headscale.example.com"

// --- login-server URL validator -------------------------------------------
for (const good of [
  [HEADSCALE, HEADSCALE],
  ["https://headscale.example.com/", HEADSCALE],
  ["http://10.10.10.5:8080/", "http://10.10.10.5:8080"],
  ["https://[fd00::1]:443", "https://[fd00::1]:443"],
  ["https://hs.example.com/path/", "https://hs.example.com/path"],
]) {
  const result = model.loginServerUrl(good[0])
  assert.equal(result.ok, true, good[0])
  assert.equal(result.url, good[1], good[0])
}
assert.deepEqual(model.loginServerUrl(""), { ok: true, url: "", error: "" }, "empty = official")
assert.deepEqual(model.loginServerUrl(OFFICIAL + "/"), { ok: true, url: "", error: "" }, "official spelled out = official")
for (const bad of [
  "ftp://headscale.example.com",
  "https://a@b",                     // userinfo
  "https://user:pw@hs.example.com",  // userinfo
  "javascript:alert(1)",             // ported: rejected un-normalized
  "headscale.example.com",           // no scheme, no guessing
  "https://x y",                     // whitespace
  "https://hs.example.com#frag",     // fragment
  "https://hs.example.com?q=1",      // query
  "https://hs.example.com:70000",    // port out of range
  "https://hs.example.com:0",
  "https://-bad.example.com",        // label starts with -
  "https://",                        // no host
  "https://hs.example.com/\u0000",   // control char
]) {
  const result = model.loginServerUrl(bad)
  assert.equal(result.ok, false, "must refuse " + JSON.stringify(bad))
  assert.equal(result.url, "", bad)
  assert.notEqual(result.error, "", bad)
}

// --- auth URL extraction ------------------------------------------------------
assert.equal(model.authUrlIn("To authenticate, visit:\n\n\thttps://login.tailscale.com/a/abc123\n"), "https://login.tailscale.com/a/abc123")
assert.equal(model.authUrlIn("--remote-debugging-port=1"), "")
assert.equal(model.authUrlIn(""), "")
// A raw AuthURL is opened only whole: a flag with a URL after it is not equal to the token.
const hostileAuth = "--flag https://evil.example/x"
assert.notEqual(model.authUrlIn(hostileAuth), hostileAuth)

// --- profile id validator (bare positional to `tailscale switch`) ------------
for (const good of ["2c0a", "profile.name", "user@github", "a-b_c"]) assert.equal(model.isProfileId(good), true, good)
for (const bad of ["", "-list", "--json", "a b", "a;b", "$(id)"]) assert.equal(model.isProfileId(bad), false, bad)

// --- tailscale set argv builder -------------------------------------------------
// Flag spellings from `tailscale set --help` on 1.102.3.
const flagTable = {
  acceptDns: "accept-dns",
  acceptRoutes: "accept-routes",
  allowLanAccess: "exit-node-allow-lan-access",
  shieldsUp: "shields-up",
  runSsh: "ssh",
  runWebClient: "webclient",
  advertiseExitNode: "advertise-exit-node",
  updateCheck: "update-check",
  autoUpdate: "auto-update",
  reportPosture: "report-posture",
}
assert.deepEqual(model.PREFERENCE_FLAGS, flagTable)
assert.equal(Object.keys(flagTable).length, 10)
for (const key of Object.keys(flagTable)) {
  assert.deepEqual(model.setPreferenceCommand(key, true), ["tailscale", "set", "--" + flagTable[key] + "=true"], key)
  assert.deepEqual(model.setPreferenceCommand(key, false), ["tailscale", "set", "--" + flagTable[key] + "=false"], key)
  assert.deepEqual(model.setPreferenceCommand(key, "yes"), ["tailscale", "set", "--" + flagTable[key] + "=false"], "non-boolean is off")
}
assert.equal(model.setPreferenceCommand("postureChecking", true), null, "unknown key builds nothing")
assert.equal(model.setPreferenceCommand("acceptDns; rm -rf /", true), null)

// --- parsePrefs (ported) --------------------------------------------------------
const prefs = model.parsePrefs(JSON.stringify({
  ControlURL: "https://headscale.example.com/",
  RouteAll: true,
  ExitNodeID: "20",
  ExitNodeAllowLANAccess: true,
  CorpDNS: false,
  RunSSH: true,
  RunWebClient: false,
  ShieldsUp: true,
  AdvertiseRoutes: ["0.0.0.0/0", "::/0"],
  AutoUpdate: { Check: true, Apply: false },
  PostureChecking: true,
  Hostname: "test-node",
  OperatorUser: "alice",
  LoggedOut: false,
}))
assert.equal(prefs.ok, true)
assert.equal(prefs.exitNodeActive, true)
assert.equal(prefs.allowLanAccess, true)
assert.equal(prefs.acceptDns, false)
assert.equal(prefs.acceptRoutes, true)
assert.equal(prefs.runSsh, true)
assert.equal(prefs.runWebClient, false)
assert.equal(prefs.shieldsUp, true)
assert.equal(prefs.advertiseExitNode, true)
assert.equal(prefs.updateCheck, true)
assert.equal(prefs.autoUpdate, false)
assert.equal(prefs.reportPosture, true)
assert.equal(prefs.hostname, "test-node")
assert.equal(prefs.operatorUser, "alice")
assert.equal(prefs.controlUrl, HEADSCALE)
assert.equal(prefs.loggedOut, false)
assert.equal(model.parsePrefs("not json").ok, false)
assert.equal(model.parsePrefs("").ok, false)
// Shape of this host's live `tailscale debug prefs` (AutoUpdate.Apply is null, not false).
const hostPrefs = model.parsePrefs(JSON.stringify({ ControlURL: OFFICIAL, RouteAll: true, ExitNodeID: "", ExitNodeIP: "", CorpDNS: true, RunSSH: true, AdvertiseRoutes: null, AutoUpdate: { Check: true, Apply: null }, PostureChecking: false, OperatorUser: "t1nk33r" }))
assert.equal(hostPrefs.autoUpdate, false)
assert.equal(hostPrefs.advertiseExitNode, false)
assert.equal(hostPrefs.exitNodeActive, false)
assert.equal(hostPrefs.controlUrl, OFFICIAL)
// ported
assert.equal(model.parsePrefs('{"ExitNodeID":"20"}').exitNodeActive, true)
assert.equal(model.parsePrefs('{"ExitNodeIP":"100.64.0.1"}').exitNodeActive, true)
assert.equal(model.parsePrefs("{}").exitNodeActive, false)

// --- exit-node derivation --------------------------------------------------------
// ported: an offline node that the prefs still select stays in exitNodes.
const offlineStatus = model.parseStatus(JSON.stringify({
  BackendState: "Running",
  ExitNodeStatus: { ID: "20", Online: false },
  Peer: { key: { ID: "20", Online: false, ExitNode: true, ExitNodeOption: true, HostName: "gateway" } },
}))
assert.equal(offlineStatus.exitNodes.length, 1)
assert.equal(offlineStatus.exitNodes[0].StableID, "20")
assert.equal(offlineStatus.exitNodeOnline, false)
// An offline node that is merely an option is not listed.
assert.equal(model.parseStatus(JSON.stringify({ BackendState: "Running", Peer: { k: { ID: "21", Online: false, ExitNodeOption: true, HostName: "x" } } })).exitNodes.length, 0)

const gatewayOnline = { StableID: "20", DisplayName: "gateway", HostName: "gateway", Online: true, ExitNode: true, TailscaleIPs: ["100.64.0.20"] }
const gatewayOffline = Object.assign({}, gatewayOnline, { Online: false })
const other = { StableID: "21", DisplayName: "other", Online: true, ExitNode: false, TailscaleIPs: ["100.64.0.21"] }
const addRow = { id: "mullvad:add", AddMullvad: true, DisplayName: "Choose Mullvad region" }

assert.deepEqual(model.exitNodeState({ exitNodeActive: false, exitNodeId: "", exitNodeIp: "" }, [gatewayOnline, other]).kind, "none", "pref cleared → none, even if status lags")
assert.equal(model.exitNodeState({ exitNodeActive: false, exitNodeId: "", exitNodeIp: "" }, []).label, "None")
const online = model.exitNodeState({ exitNodeActive: true, exitNodeId: "20", exitNodeIp: "" }, [other, gatewayOnline, addRow])
assert.equal(online.kind, "online")
assert.equal(online.label, "gateway")
const offline = model.exitNodeState({ exitNodeActive: true, exitNodeId: "20", exitNodeIp: "" }, [other, gatewayOffline])
assert.equal(offline.kind, "offline")
assert.equal(offline.label, "gateway (offline)")
assert.equal(model.exitNodeState({ exitNodeActive: true, exitNodeId: "", exitNodeIp: "100.64.0.20" }, [Object.assign({}, gatewayOffline, { ExitNode: false })]).kind, "offline", "matched by IP when status has not flagged it")
const gone = model.exitNodeState({ exitNodeActive: true, exitNodeId: "99", exitNodeIp: "" }, [other, addRow])
assert.equal(gone.kind, "unavailable")
assert.equal(gone.label, "Selected exit node (unavailable)")
assert.equal(model.exitNodeState({ exitNodeActive: true, exitNodeId: "99", exitNodeIp: "" }, [addRow]).node, null, "the Mullvad picker row is never the selection")

// --- login plan ------------------------------------------------------------------
const me = { userName: "me", operatorUser: "me" }
function plan(extra) { return model.loginPlan(Object.assign({ needsLogin: false, authUrl: "", loginServer: "", controlUrl: OFFICIAL }, me, extra)) }
function argv(p) { return p.steps.map(s => s.command) }
function kinds(p) { return p.steps.map(s => s.kind) }

// Turn-on never rebinds, whatever the setting says.
assert.deepEqual(argv(plan({})), [["tailscale", "up"]])
assert.deepEqual(argv(plan({ loginServer: HEADSCALE })), [["tailscale", "up"]], "plain up while a session exists")
assert.deepEqual(argv(plan({ controlUrl: HEADSCALE, loginServer: "" })), [["tailscale", "up"]])
assert.equal(plan({ loginServer: HEADSCALE }).logoutFirst, false)

// Explicit rebind, server changes: logout → operator → up, in that order.
const rebind = plan({ rebind: true, loginServer: HEADSCALE })
assert.deepEqual(kinds(rebind), ["logout", "operator", "up"])
assert.deepEqual(argv(rebind), [
  ["tailscale", "logout"],
  ["pkexec", "tailscale", "set", "--operator=me"],
  ["tailscale", "up", "--login-server=" + HEADSCALE],
])
assert.equal(rebind.logoutFirst, true)
assert.equal(rebind.loginServer, HEADSCALE)
for (const command of argv(rebind)) for (const arg of command) assert.equal(arg.indexOf("accept-dns"), -1, "no --accept-dns on up")

// Rebind back to official from Headscale names the official URL explicitly.
const back = plan({ rebind: true, controlUrl: HEADSCALE, loginServer: "" })
assert.deepEqual(kinds(back), ["logout", "operator", "up"])
assert.deepEqual(argv(back)[2], ["tailscale", "up", "--login-server=" + OFFICIAL])

// Rebind with an unchanged server: nothing runs, and it says why.
const same = plan({ rebind: true, controlUrl: HEADSCALE, loginServer: HEADSCALE })
assert.deepEqual(same.steps, [])
assert.match(same.error, /Already logged in/)
assert.deepEqual(plan({ rebind: true, controlUrl: OFFICIAL + "/", loginServer: OFFICIAL }).steps, [], "trailing slash / case are the same server")

// Fresh login (NeedsLogin), same server, operator set: exactly one step.
assert.deepEqual(argv(plan({ needsLogin: true, controlUrl: HEADSCALE, loginServer: HEADSCALE })), [["tailscale", "up", "--login-server=" + HEADSCALE]])
assert.deepEqual(argv(plan({ needsLogin: true, controlUrl: OFFICIAL, loginServer: "" })), [["tailscale", "up"]])
assert.deepEqual(argv(plan({ needsLogin: true, controlUrl: "", loginServer: HEADSCALE })), [["tailscale", "up", "--login-server=" + HEADSCALE]], "never-bound profile: no logout")
assert.deepEqual(argv(plan({ needsLogin: true, controlUrl: "", loginServer: "" })), [["tailscale", "up"]])
// Fresh login, same server, operator NOT set: pkexec first, no logout.
assert.deepEqual(kinds(plan({ needsLogin: true, controlUrl: OFFICIAL, loginServer: "", operatorUser: "" })), ["operator", "up"])
assert.deepEqual(kinds(plan({ needsLogin: true, controlUrl: OFFICIAL, loginServer: "", userName: "" })), ["up"], "no user name → nothing to authorize")
// Fresh login, server changes: logout first even though NeedsLogin (the stale profile must go).
assert.deepEqual(kinds(plan({ needsLogin: true, controlUrl: OFFICIAL, loginServer: HEADSCALE })), ["logout", "operator", "up"])

// A pending AuthURL is opened only when it belongs to the target server.
const withUrl = plan({ needsLogin: true, authUrl: "https://login.tailscale.com/a/abc", loginServer: "" })
assert.equal(withUrl.authUrl, "https://login.tailscale.com/a/abc")
assert.deepEqual(withUrl.steps, [])
const wrongServer = plan({ needsLogin: true, authUrl: "https://login.tailscale.com/a/abc", loginServer: HEADSCALE })
assert.equal(wrongServer.authUrl, "", "official AuthURL is not opened when Headscale is the target")
assert.deepEqual(kinds(wrongServer), ["logout", "operator", "up"])
assert.equal(plan({ needsLogin: true, authUrl: "--remote-debugging-port=1 https://x" }).authUrl, "", "non-URL AuthURL is never handed to the browser")

// Invalid setting: no steps, error text.
const invalid = plan({ needsLogin: true, loginServer: "ftp://x" })
assert.deepEqual(invalid.steps, [])
assert.match(invalid.error, /http/)
assert.deepEqual(plan({ rebind: true, loginServer: "https://a@b" }).steps, [])

// Every user-controlled value is exactly one argv element.
for (const command of argv(plan({ rebind: true, loginServer: "https://hs.example.com:8443/base" }))) {
  assert.equal(command.filter(a => a.indexOf("hs.example.com") !== -1).length <= 1, true)
  for (const arg of command) assert.equal(/[\s;|&]/.test(arg), false, "no shell metacharacters in " + arg)
}

// --- login step failure messages (the pkexec-cancel state machine) --------------
const three = plan({ rebind: true, loginServer: HEADSCALE })
assert.match(model.loginStepFailure(three, 0, 1, "logout: access denied"), /^Logout failed: logout: access denied — still on the current server$/)
const cancelled = model.loginStepFailure(three, 1, 126, "")
assert.match(cancelled, /^Logged out; authorization cancelled — run: sudo tailscale set --operator=me && tailscale up --login-server=https:\/\/headscale\.example\.com$/)
assert.match(model.loginStepFailure(three, 1, 127, ""), /authorization cancelled/)
assert.match(model.loginStepFailure(three, 1, 1, "Error: not permitted"), /^Logged out; operator not set: Error: not permitted — run: sudo tailscale set --operator=me && tailscale up --login-server=/)
assert.match(model.loginStepFailure(three, 2, 1, "up failed"), /^Logged out; up failed$/)
const twoStep = plan({ needsLogin: true, operatorUser: "" })
assert.match(model.loginStepFailure(twoStep, 0, 126, ""), /^authorization cancelled — run: sudo tailscale set --operator=me && tailscale up$/, "no logout ran → no 'Logged out' prefix")
assert.equal(model.loginStepFailure(plan({}), 0, 1, "  tailscale up\n failed "), "tailscale up failed")

// --- switch outcome ---------------------------------------------------------------
assert.equal(model.switchOutcome(0, 'Switching to account "x"\nLogged out.\nTo log in, run:\n  tailscale up\n', ""), "needsLogin")
assert.equal(model.switchOutcome(0, 'Switching to account "x"\nSuccess.\n', ""), "ok")
assert.equal(model.switchOutcome(1, "", 'No profile named "x"\n'), "missing")
assert.equal(model.switchOutcome(1, "", "Failed to switch to account: boom"), "error")
assert.equal(model.switchOutcome(0, "Logged out. (not on its own line)", ""), "ok", "the marker is a whole line")
assert.equal(model.profileListed([{ id: "2c0a" }, { id: "9f" }], "9f"), true)
assert.equal(model.profileListed([{ id: "2c0a" }], "9f"), false)
assert.equal(model.profileListed(null, "9f"), false)

// --- keyboard dispatch table (Panel.qml) ----------------------------------------------
// The panel's key handling is QML; the table is asserted structurally against the
// source so a binding cannot silently vanish. j/k/arrows, Enter/Space and Esc are
// PanelKeyCatcher signals; the rest are text keys the panel dispatches itself.
const fs = require("node:fs")
const panel = fs.readFileSync(require.resolve("../Panel.qml"), "utf8")
const textKeyBlock = panel.match(/onTextKey: function\(t\) \{([^]*?)\n      \}/)
assert.ok(textKeyBlock, "onTextKey handler present")
const keyTable = {
  t: "tailscale.toggleTailscale()",
  r: "tailscale.refresh(true)",
  c: "tailscale.copyPeerIp(peer)",
  n: "tailscale.copyPeerName(peer)",
  d: "tailscale.copyPeerDnsName(peer)",
  s: "root.sendPeerFile(peer)",
}
for (const key of Object.keys(keyTable)) {
  const line = textKeyBlock[1].split("\n").find(l => l.indexOf('t === "' + key + '"') !== -1)
  assert.ok(line, "key " + key + " bound")
  assert.ok(line.indexOf(keyTable[key]) !== -1, "key " + key + " → " + keyTable[key])
}
for (const peerKey of ["c", "n", "d", "s"]) {
  const line = textKeyBlock[1].split("\n").find(l => l.indexOf('t === "' + peerKey + '"') !== -1)
  assert.ok(line.indexOf("root.peerShortcut(") !== -1, peerKey + " goes through peerShortcut (peers section only)")
}
assert.ok(/function peerShortcut\(action\) \{\s*if \(focusSection !== "peers" \|\| !cursorActive\)/.test(panel), "peerShortcut refuses outside the peers section")
assert.ok(/onCloseRequested: \{\s*if \(root\.rebindArmed\) root\.rebindArmed = false\s*else root\.close\(\)/.test(panel), "Esc disarms the rebind before it closes")
const order = panel.match(/function sectionList\(\) \{([^]*?)\n  \}/)[1].match(/push\("(\w+)"\)/g).map(s => s.slice(6, -2))
assert.deepEqual(order, ["auth", "loginServer", "accounts", "exitNodes", "settings", "peers"], "cursor order: accounts → exit nodes → settings → peers")
assert.ok(/onActivateRequested: if \(root\.cursorActive\) root\.activateCursor\(\)/.test(panel), "Enter/Space activate")
assert.ok(/onMoveRequested: function\(dx, dy\)/.test(panel), "j/k/arrows move")

console.log("model tests passed")
