function filterIPv4(ips) {
  var result = []
  if (!ips || typeof ips.length !== "number") return result
  for (var i = 0; i < ips.length; i++) {
    var ip = String(ips[i] || "")
    if (/^100\./.test(ip)) result.push(ip)
  }
  return result
}

function filterIPv6(ips) {
  var result = []
  if (!ips || typeof ips.length !== "number") return result
  for (var i = 0; i < ips.length; i++) {
    var ip = String(ips[i] || "")
    if (/^fd7a:115c:a1e0:/i.test(ip)) result.push(ip)
  }
  return result
}

function cleanDnsName(name) {
  var value = String(name || "")
  return value.charAt(value.length - 1) === "." ? value.slice(0, -1) : value
}

function shortDnsName(name) {
  var clean = cleanDnsName(name)
  if (clean === "") return ""
  return clean.split(".")[0] || clean
}

function displayHostName(hostName, dnsName) {
  var host = String(hostName || "")
  if (host !== "" && host.toLowerCase() !== "localhost") return host
  return shortDnsName(dnsName) || host || "Unknown"
}

function isMullvadHost(name) {
  var value = String(name || "").toLowerCase()
  var suffix = ".mullvad.ts.net"
  return value.length > suffix.length && value.indexOf(suffix) === value.length - suffix.length
}

function isMullvadPeer(peer) {
  var hostName = String((peer && peer.HostName) || "")
  var dnsName = cleanDnsName((peer && peer.DNSName) || "")
  return isMullvadHost(dnsName) || isMullvadHost(hostName)
}

function osIcon(os) {
  var value = String(os || "").toLowerCase()
  if (value === "linux") return "󰌽"
  if (value === "macos" || value === "ios") return "󰀵"
  if (value === "windows") return "󰍲"
  if (value === "android") return "󰀲"
  if (value === "mullvad") return "󰖂"
  return "󰟀"
}

function accountLabel(account) {
  if (!account) return "Unknown account"
  if (account.nickname) return String(account.nickname)
  if (account.tailnet) return String(account.tailnet)
  if (account.account) return String(account.account)
  return String(account.id || "Unknown account")
}

var OFFICIAL_CONTROL_URL = "https://controlplane.tailscale.com"

// Ported from hehh2001/omarchy-tailscale-plus @426b3cc (MIT): control-server
// URLs are compared without their trailing slash, which is how `tailscale
// debug prefs` reports ControlURL.
function normalizeControlUrl(value) {
  var text = String(value || "").trim()
  while (text.length > 0 && text.charAt(text.length - 1) === "/") text = text.slice(0, -1)
  return text
}

// A login server is only ever one argv element (`--login-server=<url>`), so
// this is hygiene rather than injection defence: http(s) only, a dotted
// hostname or a dotted-IPv4 / bracketed-IPv6 literal (Headscale on the LAN),
// an optional port, an optional path. No userinfo, no query, no fragment, no
// whitespace, and no scheme guessing — the user types the scheme.
var CONTROL_URL_PATTERN = /^https?:\/\/(?:(?:[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?)(?:\.[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?)*|\[[0-9a-f:.]+\])(?::([0-9]{1,5}))?(?:\/[a-z0-9._~%!$&'()*+,;=:\/-]*)?$/i

function loginServerUrl(value) {
  var url = normalizeControlUrl(value)
  if (url === "") return { ok: true, url: "", error: "" }
  var match = CONTROL_URL_PATTERN.exec(url)
  if (!match) return { ok: false, url: "", error: "Login server must be an http:// or https:// URL without a username" }
  if (match[1] !== undefined) {
    var port = parseInt(match[1], 10)
    if (port < 1 || port > 65535) return { ok: false, url: "", error: "Login server port must be 1-65535" }
  }
  if (url.toLowerCase() === OFFICIAL_CONTROL_URL) return { ok: true, url: "", error: "" }
  return { ok: true, url: url, error: "" }
}

// The only URL that ever reaches the browser launcher: the first http(s) token
// in `text`, and nothing else. A control server that puts something other than
// a URL in AuthURL gets shown, not opened.
function authUrlIn(text) {
  var match = /https?:\/\/\S+/.exec(String(text || ""))
  return match ? match[0] : ""
}

// A status AuthURL is opened whole or not at all: no token is picked out of
// it, so a flag with a URL after it is not a URL.
function wholeAuthUrl(value) {
  var text = String(value || "").trim()
  return text !== "" && authUrlIn(text) === text ? text : ""
}

// The profile id is a bare positional to `tailscale switch`, so it must never
// be able to parse as a flag.
function isProfileId(value) {
  var id = String(value || "")
  return /^[A-Za-z0-9._@-]+$/.test(id) && id.charAt(0) !== "-"
}

// How to get this machine logged in, as a list of argv steps.
//
//   state.needsLogin   backend is NeedsLogin (no session to turn on)
//   state.authUrl      AuthURL from `tailscale status --json`, if any
//   state.loginServer  the `loginServer` setting ("" = official Tailscale)
//   state.controlUrl   ControlURL from `tailscale debug prefs`
//   state.operatorUser OperatorUser from `tailscale debug prefs`
//   state.userName     the desktop user the panel runs as
//   state.rebind       true when the user explicitly asked to move to the
//                      configured server even though a session exists
//
// Plain `tailscale up` is the turn-on path and never rebinds. A fresh login
// goes to the configured server; when that differs from the server this
// profile is bound to, `tailscale logout` runs first — on tailscale 1.102.3
// logout deletes the profile and drops to a new empty one with no
// OperatorUser, so a non-root user is read-only until `set --operator` runs
// again, hence the pkexec step between logout and up. Nothing here appends
// `--accept-dns` or other prefs to `up`: a fresh profile does not need them
// and a non-fresh one errors when non-default prefs are omitted.
function loginPlan(state) {
  var s = state || {}
  var needsLogin = s.needsLogin === true
  var authUrl = wholeAuthUrl(s.authUrl)
  var userName = String(s.userName || "")
  var server = loginServerUrl(s.loginServer)
  var noop = { authUrl: "", steps: [], logoutFirst: false, loginServer: "", error: "" }
  if (!server.ok) { noop.error = server.error; return noop }

  var targetUrl = server.url === "" ? OFFICIAL_CONTROL_URL : server.url
  var currentUrl = normalizeControlUrl(s.controlUrl)
  var serverChanges = currentUrl !== "" && currentUrl.toLowerCase() !== targetUrl.toLowerCase()

  if (!needsLogin && s.rebind !== true) {
    return { authUrl: "", steps: [{ kind: "up", command: ["tailscale", "up"] }], logoutFirst: false, loginServer: currentUrl, error: "" }
  }
  if (!needsLogin && !serverChanges) {
    noop.loginServer = targetUrl
    noop.error = "Already logged in to " + targetUrl
    return noop
  }
  if (!serverChanges && authUrl !== "") {
    return { authUrl: authUrl, steps: [], logoutFirst: false, loginServer: targetUrl, error: "" }
  }

  var steps = []
  var operatorMissing = userName !== "" && String(s.operatorUser || "") !== userName
  if (serverChanges) steps.push({ kind: "logout", command: ["tailscale", "logout"] })
  if (userName !== "" && (serverChanges || operatorMissing)) {
    steps.push({ kind: "operator", command: ["pkexec", "tailscale", "set", "--operator=" + userName] })
  }
  var up = ["tailscale", "up"]
  if (server.url !== "" || serverChanges) up.push("--login-server=" + targetUrl)
  steps.push({ kind: "up", command: up })
  return { authUrl: "", steps: steps, logoutFirst: serverChanges, loginServer: targetUrl, error: "" }
}

// What a failed login step leaves behind. Once logout has run the profile is
// gone, so a dismissed polkit prompt must say exactly how to finish by hand
// rather than letting `up` run read-only and fail opaquely.
function loginStepFailure(plan, index, exitCode, detail) {
  var steps = (plan && plan.steps) || []
  var step = steps[index] || {}
  var loggedOut = false
  for (var i = 0; i < index && i < steps.length; i++) if (steps[i].kind === "logout") loggedOut = true
  var text = String(detail || "").replace(/\s+/g, " ").trim()
  if (step.kind === "logout") return "Logout failed" + (text ? ": " + text : "") + " — still on the current server"
  if (step.kind === "operator") {
    var remaining = []
    for (var j = index; j < steps.length; j++) {
      var command = steps[j].command.slice(steps[j].kind === "operator" ? 1 : 0)
      remaining.push((steps[j].kind === "operator" ? "sudo " : "") + command.join(" "))
    }
    var reason = exitCode === 126 || exitCode === 127 ? "authorization cancelled" : "operator not set" + (text ? ": " + text : "")
    return (loggedOut ? "Logged out; " : "") + reason + " — run: " + remaining.join(" && ")
  }
  return (loggedOut ? "Logged out; " : "") + (text || "tailscale up failed")
}

// The ten `tailscale set` switches the panel exposes, keyed by the property
// they read back from `tailscale debug prefs`. Flag spellings verified against
// `tailscale set --help` on 1.102.3.
var PREFERENCE_FLAGS = {
  acceptDns: "accept-dns",
  acceptRoutes: "accept-routes",
  allowLanAccess: "exit-node-allow-lan-access",
  shieldsUp: "shields-up",
  runSsh: "ssh",
  runWebClient: "webclient",
  advertiseExitNode: "advertise-exit-node",
  updateCheck: "update-check",
  autoUpdate: "auto-update",
  reportPosture: "report-posture"
}

function setPreferenceCommand(key, value) {
  var flag = PREFERENCE_FLAGS[String(key || "")]
  if (!flag) return null
  return ["tailscale", "set", "--" + flag + "=" + (value === true ? "true" : "false")]
}

// Ported from hehh2001/omarchy-tailscale-plus @426b3cc (MIT). `tailscale
// status --json` carries none of these; `tailscale debug prefs` carries all of
// them, and it is the only source of the persisted exit-node choice.
function parsePrefs(raw) {
  var text = String(raw || "").trim()
  if (text === "") return { ok: false, error: "Empty Tailscale preferences" }
  try {
    var data = JSON.parse(text)
    var autoUpdate = data.AutoUpdate || {}
    var routes = Array.isArray(data.AdvertiseRoutes) ? data.AdvertiseRoutes : []
    return {
      ok: true,
      acceptDns: data.CorpDNS === true,
      acceptRoutes: data.RouteAll === true,
      allowLanAccess: data.ExitNodeAllowLANAccess === true,
      shieldsUp: data.ShieldsUp === true,
      runSsh: data.RunSSH === true,
      runWebClient: data.RunWebClient === true,
      advertiseExitNode: routes.indexOf("0.0.0.0/0") !== -1 || routes.indexOf("::/0") !== -1,
      updateCheck: autoUpdate.Check === true,
      autoUpdate: autoUpdate.Apply === true,
      reportPosture: data.PostureChecking === true,
      hostname: String(data.Hostname || ""),
      operatorUser: String(data.OperatorUser || ""),
      controlUrl: normalizeControlUrl(data.ControlURL),
      loggedOut: data.LoggedOut === true,
      exitNodeId: String(data.ExitNodeID || ""),
      exitNodeIp: String(data.ExitNodeIP || ""),
      exitNodeActive: String(data.ExitNodeID || data.ExitNodeIP || "") !== ""
    }
  } catch (e) {
    return { ok: false, error: "Failed to parse Tailscale preferences" }
  }
}

// Ported from hehh2001/omarchy-tailscale-plus @426b3cc (MIT). The displayed
// exit node is derived from the persisted preference on every refresh and
// never from a selection the panel remembers: a node the CLI cleared shows
// cleared, a selected node that went offline shows offline, and a selected
// node the status no longer lists shows unavailable — never "None".
function exitNodeState(prefs, nodes) {
  var p = prefs || {}
  var list = Array.isArray(nodes) ? nodes : []
  if (p.exitNodeActive !== true) return { kind: "none", node: null, label: "None" }
  var selected = null
  for (var i = 0; i < list.length; i++) {
    var node = list[i]
    if (!node || node.AddMullvad === true) continue
    var byId = p.exitNodeId !== "" && String(node.StableID || "") === String(p.exitNodeId)
    var byIp = p.exitNodeIp !== "" && filterIPv4(node.TailscaleIPs || []).indexOf(String(p.exitNodeIp)) !== -1
    if (node.ExitNode === true || byId || byIp) { selected = node; break }
  }
  if (!selected) return { kind: "unavailable", node: null, label: "Selected exit node (unavailable)" }
  var name = String(selected.DisplayName || selected.HostName || "Unknown")
  if (selected.Online === true) return { kind: "online", node: selected, label: name }
  return { kind: "offline", node: selected, label: name + " (offline)" }
}

// Outcome of `tailscale switch <id>`. Observed on tailscale 1.102.3
// (cmd/tailscale/cli/switch.go): switching to a logged-out profile exits 0 and
// prints "Logged out." / "To log in, run:" / "  tailscale up" with the backend
// in NeedsLogin; a missing profile prints `No profile named "x"` and exits 1.
function switchOutcome(exitCode, stdout, stderr) {
  var out = String(stdout || "")
  var err = String(stderr || "")
  if (exitCode === 0) return /^\s*Logged out\.\s*$/m.test(out) ? "needsLogin" : "ok"
  if (/No profile named|profile not found|no such profile/i.test(err + "\n" + out)) return "missing"
  return "error"
}

// Secondary, structural check for a switch that failed: the target is gone
// from a fresh `tailscale switch --list --json`.
function profileListed(accounts, id) {
  var list = Array.isArray(accounts) ? accounts : []
  for (var i = 0; i < list.length; i++) if (String(list[i].id || "") === String(id || "")) return true
  return false
}

// Taildrop is a tailnet feature the admin can turn off, so the button for it
// only makes sense when this profile actually carries the capability.
function hasFileSharing(self) {
  var capability = "https://tailscale.com/cap/file-sharing"
  var capMap = (self && self.CapMap) || null
  if (capMap && capMap[capability] !== undefined) return true
  var capabilities = (self && self.Capabilities) || []
  for (var i = 0; i < capabilities.length; i++) {
    if (String(capabilities[i]) === capability) return true
  }
  return false
}

// Tailscale grades every peer itself — offline, wrong owner, an OS without
// Taildrop, no peer API — so take its word when the status carries one, and
// fall back to same-owner for daemons too old to say.
function isTaildropTarget(peer, selfUserId) {
  var target = peer && peer.TaildropTarget
  if (typeof target === "number" && target !== 0) return target === 1
  var owner = String((peer && peer.UserID) || "")
  return owner !== "" && owner === String(selfUserId || "")
}

function peerFromStatus(id, peer) {
  return {
    id: id,
    StableID: String(peer.ID || ""),
    HostName: displayHostName(peer.HostName, peer.DNSName),
    UserID: String(peer.UserID || ""),
    TaildropTarget: typeof peer.TaildropTarget === "number" ? peer.TaildropTarget : 0,
    DNSName: cleanDnsName(peer.DNSName),
    DisplayName: displayHostName(peer.HostName, peer.DNSName),
    TailscaleIPs: filterIPv4(peer.TailscaleIPs || []),
    TailscaleIPv6: filterIPv6(peer.TailscaleIPs || []),
    Online: peer.Online === true,
    OS: String(peer.OS || ""),
    Tags: peer.Tags || [],
    ExitNodeOption: peer.ExitNodeOption === true,
    ExitNode: peer.ExitNode === true,
    Mullvad: isMullvadPeer(peer)
  }
}

function sliceTableColumn(line, start, end) {
  var text = String(line || "")
  if (start < 0 || start >= text.length) return ""
  if (end < 0) return text.substring(start).trim()
  return text.substring(start, Math.min(end, text.length)).trim()
}

function parseExitNodeList(raw) {
  var lines = String(raw || "").split(/\r?\n/)
  var header = ""
  var headerIndex = -1
  for (var i = 0; i < lines.length; i++) {
    if (/^\s*IP\s+HOSTNAME\s+COUNTRY\s+CITY\s+STATUS\s*$/.test(lines[i])) {
      header = lines[i]
      headerIndex = i
      break
    }
  }
  if (headerIndex === -1) return []

  var ipStart = header.indexOf("IP")
  var hostStart = header.indexOf("HOSTNAME")
  var countryStart = header.indexOf("COUNTRY")
  var cityStart = header.indexOf("CITY")
  var statusStart = header.indexOf("STATUS")
  var byHost = {}

  for (var j = headerIndex + 1; j < lines.length; j++) {
    var line = lines[j]
    if (/^\s*$/.test(line) || /^\s*#/.test(line)) continue

    var ip = sliceTableColumn(line, ipStart, hostStart)
    var host = sliceTableColumn(line, hostStart, countryStart)
    var country = sliceTableColumn(line, countryStart, cityStart)
    var city = sliceTableColumn(line, cityStart, statusStart)
    var status = sliceTableColumn(line, statusStart, -1)
    if (!isMullvadHost(host)) continue

    byHost[host] = {
      id: "mullvad:" + host,
      HostName: host,
      DNSName: host,
      DisplayName: (city && city !== "Any" ? city + ", " : "") + country,
      TailscaleIPs: ip ? [ip] : [],
      TailscaleIPv6: [],
      Online: true,
      OS: "mullvad",
      Tags: [],
      ExitNodeOption: true,
      ExitNode: status !== "" && status !== "-",
      Mullvad: true,
      Country: country,
      City: city,
      Status: status
    }
  }

  var result = []
  for (var hostName in byHost) result.push(byHost[hostName])
  result.sort(function(a, b) {
    var countryCompare = String(a.Country).localeCompare(String(b.Country))
    if (countryCompare !== 0) return countryCompare
    return String(a.DisplayName).localeCompare(String(b.DisplayName))
  })
  return result
}

function mullvadRegionOptions(nodes) {
  var byRegion = {}
  var values = Array.isArray(nodes) ? nodes : []
  for (var i = 0; i < values.length; i++) {
    var node = values[i] || {}
    if (node.Mullvad !== true) continue
    var country = String(node.Country || "").trim()
    var city = String(node.City || "").trim()
    if (country === "") continue
    if (city === "" || city === "Any") continue

    var key = country + "\n" + city
    if (byRegion[key]) continue

    var option = {}
    for (var propertyName in node) option[propertyName] = node[propertyName]
    option.id = "mullvad-region:" + key
    option.DisplayName = city + ", " + country
    option.Country = country
    option.City = city
    option.MullvadRegion = true
    byRegion[key] = option
  }

  var result = []
  for (var name in byRegion) result.push(byRegion[name])
  result.sort(function(a, b) {
    var countryCompare = String(a.Country).localeCompare(String(b.Country))
    if (countryCompare !== 0) return countryCompare
    return String(a.City).localeCompare(String(b.City))
  })
  return result
}

function mullvadCountryOptions(nodes) {
  return mullvadRegionOptions(nodes)
}

function parseStatus(raw) {
  var text = String(raw || "").trim()
  if (text === "") return { ok: true, unavailable: true, message: "Disconnected" }

  try {
    var data = JSON.parse(text)
    var backendState = String(data.BackendState || "Unknown")
    var self = data.Self || {}
    var selfIps = filterIPv4(self.TailscaleIPs || data.TailscaleIPs || [])
    var peers = []
    var exitNodes = []
    var rawPeers = data.Peer || {}

    for (var id in rawPeers) {
      var peer = rawPeers[id] || {}
      var normalized = peerFromStatus(id, peer)
      if (normalized.Mullvad) continue
      peers.push(normalized)
      // Ported from hehh2001/omarchy-tailscale-plus @426b3cc (MIT): the node
      // the prefs still select stays listed when it goes offline, so the row
      // can say "(offline)" instead of vanishing and reading as "None".
      if ((normalized.Online && normalized.ExitNodeOption) || normalized.ExitNode) exitNodes.push(normalized)
    }

    peers.sort(function(a, b) {
      if (a.Online !== b.Online) return a.Online ? -1 : 1
      return String(a.HostName).localeCompare(String(b.HostName))
    })
    exitNodes.sort(function(a, b) {
      return String(a.HostName).localeCompare(String(b.HostName))
    })

    return {
      ok: true,
      unavailable: false,
      backendState: backendState,
      running: backendState === "Running",
      needsLogin: backendState === "NeedsLogin",
      authUrl: String(data.AuthURL || ""),
      selfName: displayHostName(self.HostName, self.DNSName),
      selfDnsName: cleanDnsName(self.DNSName),
      selfIp: selfIps.length > 0 ? selfIps[0] : "",
      selfUserId: String(self.UserID || ""),
      fileSharing: hasFileSharing(self),
      exitNodeOnline: !!(data.ExitNodeStatus && data.ExitNodeStatus.Online === true),
      peers: peers,
      exitNodes: exitNodes
    }
  } catch (e) {
    return { ok: false, unavailable: true, message: "Status error", error: "Failed to parse tailscale status" }
  }
}

function parseAccounts(raw) {
  var text = String(raw || "").trim()
  if (text === "") return { accounts: [], selectedAccountId: "", selectedAccountLabel: "" }

  try {
    var parsed = JSON.parse(text)
    var next = []
    var selected = null
    if (parsed && typeof parsed.length === "number") {
      for (var i = 0; i < parsed.length; i++) {
        var rawAccount = parsed[i] || {}
        var account = {
          id: String(rawAccount.id || rawAccount.ID || ""),
          nickname: String(rawAccount.nickname || rawAccount.Nickname || rawAccount.name || rawAccount.Name || ""),
          tailnet: String(rawAccount.tailnet || rawAccount.Tailnet || ""),
          account: String(rawAccount.account || rawAccount.Account || rawAccount.loginName || rawAccount.LoginName || rawAccount.user || rawAccount.User || ""),
          selected: rawAccount.selected === true || rawAccount.Selected === true
        }
        next.push(account)
        if (account.selected === true) selected = account
      }
    }
    return {
      accounts: next,
      selectedAccountId: selected ? String(selected.id || "") : "",
      selectedAccountLabel: selected ? accountLabel(selected) : ""
    }
  } catch (e) {
    return { accounts: [], selectedAccountId: "", selectedAccountLabel: "" }
  }
}

if (typeof module !== "undefined") {
  module.exports = {
    filterIPv4: filterIPv4,
    filterIPv6: filterIPv6,
    cleanDnsName: cleanDnsName,
    shortDnsName: shortDnsName,
    displayHostName: displayHostName,
    osIcon: osIcon,
    accountLabel: accountLabel,
    OFFICIAL_CONTROL_URL: OFFICIAL_CONTROL_URL,
    PREFERENCE_FLAGS: PREFERENCE_FLAGS,
    normalizeControlUrl: normalizeControlUrl,
    loginServerUrl: loginServerUrl,
    authUrlIn: authUrlIn,
    wholeAuthUrl: wholeAuthUrl,
    isProfileId: isProfileId,
    loginPlan: loginPlan,
    loginStepFailure: loginStepFailure,
    setPreferenceCommand: setPreferenceCommand,
    parsePrefs: parsePrefs,
    exitNodeState: exitNodeState,
    switchOutcome: switchOutcome,
    profileListed: profileListed,
    hasFileSharing: hasFileSharing,
    isTaildropTarget: isTaildropTarget,
    isMullvadPeer: isMullvadPeer,
    peerFromStatus: peerFromStatus,
    parseExitNodeList: parseExitNodeList,
    mullvadRegionOptions: mullvadRegionOptions,
    mullvadCountryOptions: mullvadCountryOptions,
    parseStatus: parseStatus,
    parseAccounts: parseAccounts
  }
}
