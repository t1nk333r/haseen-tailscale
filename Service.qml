import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import "Model.js" as Model

Item {
  id: root

  property var settings: ({})

  property bool installed: false
  property bool running: false
  property bool needsLogin: false

  // Optimistic off state so the UI reacts the instant you click, rather than
  // waiting for the next status refresh. _desired is -1 while we just follow
  // the real state, or 0/1 while a toggle is still catching up.
  property int _desired: -1
  readonly property bool active: _desired === -1 ? running : (_desired === 1)
  property bool refreshing: false
  property string backendState: "Unknown"
  property string statusText: "Checking…"
  property string selfName: ""
  property string selfDnsName: ""
  property string selfIp: ""
  property string selfUserId: ""
  property bool fileSharing: false
  property string authUrl: ""
  property var peers: []
  property var exitNodes: []
  property var tailnetExitNodes: []
  property var mullvadExitNodes: []
  property var mullvadRegions: []
  property var accounts: []
  property string selectedAccountId: ""
  property string selectedAccountLabel: ""
  property string switchingAccountId: ""
  property string settingExitNodeId: ""
  property bool accountsAccessDenied: false
  property string actionStatus: ""
  property string lastError: ""

  // Ported from hehh2001/omarchy-tailscale-plus @426b3cc (MIT): everything
  // below comes from `tailscale debug prefs`, re-read on every refresh.
  property bool prefsLoaded: false
  property bool acceptDns: false
  property bool acceptRoutes: false
  property bool allowLanAccess: false
  property bool shieldsUp: false
  property bool runSsh: false
  property bool runWebClient: false
  property bool advertiseExitNode: false
  property bool updateCheck: false
  property bool autoUpdate: false
  property bool reportPosture: false
  property string operatorUser: ""
  property string controlUrl: ""
  property bool loggedOut: false
  property string exitNodeId: ""
  property string exitNodeIp: ""
  property bool exitNodeActive: false
  property bool exitNodeOnline: false
  property string changingSetting: ""
  // An AuthURL that failed the http(s) check is shown for copying, never opened.
  property string blockedAuthUrl: ""

  readonly property string loginServer: String(setting("loginServer", "") || "")
  readonly property var loginServerCheck: Model.loginServerUrl(loginServer)
  readonly property string loginServerUrl: loginServerCheck.ok ? (loginServerCheck.url || Model.OFFICIAL_CONTROL_URL) : ""
  // The configured server differs from the one this profile is bound to, so a
  // fresh login there means logging out first — the panel confirms that.
  readonly property bool loginServerDiffers: loginServerCheck.ok && controlUrl !== "" && controlUrl.toLowerCase() !== loginServerUrl.toLowerCase()

  // Stale poll results are dropped: every mutation bumps the generation and
  // invalidates the status/prefs snapshot until a fresh poll lands.
  property int _networkGeneration: 0
  property bool _statusValid: false
  property bool _prefsValid: false
  property var _loginPlan: null
  property int _loginStep: -1
  property bool _pendingLoginAfterRefresh: false
  property string _switchTargetId: ""

  readonly property int refreshIntervalSec: intSetting("refreshIntervalSec", 30, 5, 3600)
  readonly property bool busy: whichProcess.running || statusProcess.running || prefsProcess.running || mullvadExitNodesProcess.running || accountsProcess.running || actionProcess.running || loginProcess.running || logoutProcess.running || switchProcess.running || operatorProcess.running || exitNodeProcess.running || settingProcess.running
  readonly property bool loginBusy: loginProcess.running || logoutProcess.running || (operatorProcess.running && _loginStep >= 0)
  readonly property string userName: Quickshell.env("USER") || Quickshell.env("LOGNAME")

  property string _statusOutput: ""
  property string _statusError: ""
  property string _accountsOutput: ""
  property string _accountsError: ""
  property string _mullvadExitNodesOutput: ""
  property string _mullvadExitNodesError: ""
  property string _actionOutput: ""
  property string _actionError: ""
  property string _loginOutput: ""
  property string _loginError: ""
  property bool _loginInProgress: false
  property bool _loginUrlOpened: false
  property string _preLoginAuthUrl: ""
  property double _lastAccountsRefreshMs: 0
  property string _switchOutput: ""
  property string _switchError: ""
  property string _exitNodeOutput: ""
  property string _exitNodeError: ""
  property string _operatorOutput: ""
  property string _operatorError: ""
  property string _prefsOutput: ""
  property string _prefsError: ""
  property string _settingOutput: ""
  property string _settingError: ""
  property string _logoutOutput: ""
  property string _logoutError: ""

  function setting(name, fallback) {
    var value = settings ? settings[name] : undefined
    return value === undefined || value === null ? fallback : value
  }

  function intSetting(name, fallback, min, max) {
    var n = parseInt(String(setting(name, fallback)), 10)
    if (!isFinite(n)) n = fallback
    if (n < min) n = min
    if (n > max) n = max
    return n
  }

  function filterIPv4(ips) {
    return Model.filterIPv4(ips)
  }

  function cleanDnsName(name) {
    return Model.cleanDnsName(name)
  }

  function shortDnsName(name) {
    return Model.shortDnsName(name)
  }

  function displayHostName(hostName, dnsName) {
    return Model.displayHostName(hostName, dnsName)
  }

  function osIcon(os) {
    return Model.osIcon(os)
  }

  function accountLabel(account) {
    return Model.accountLabel(account)
  }

  // The value goes to wl-copy on stdin: no shell, no argv, nothing to quote.
  function copyToClipboard(value, label) {
    var text = String(value || "")
    if (text === "" || clipboardProcess.running) return
    clipboardProcess.payload = text
    clipboardProcess.running = true
  }

  function copyPeerIp(peer) {
    if (!peer) return
    var ips = filterIPv4(peer.TailscaleIPs || [])
    copyToClipboard(ips.length > 0 ? ips[0] : "", displayHostName(peer.HostName, peer.DNSName) + " IP")
  }

  function copyPeerName(peer) {
    if (!peer) return
    copyToClipboard(displayHostName(peer.HostName, peer.DNSName), displayHostName(peer.HostName, peer.DNSName) + " name")
  }

  function copyPeerDnsName(peer) {
    if (!peer) return
    copyToClipboard(cleanDnsName(peer.DNSName), displayHostName(peer.HostName, peer.DNSName) + " DNS name")
  }

  function peerAddress(peer) {
    if (!peer) return ""
    if (peer.DNSName) return cleanDnsName(peer.DNSName)
    if (peer.HostName) return String(peer.HostName)
    var ips = filterIPv4(peer.TailscaleIPs || [])
    return ips.length > 0 ? ips[0] : ""
  }

  function canSendFiles(peer) {
    if (!fileSharing || !running || !peer) return false
    return Model.isTaildropTarget(peer, selfUserId)
  }

  function sendFile(peer) {
    if (!canSendFiles(peer)) return
    var target = peerAddress(peer)
    if (target === "") return
    Quickshell.execDetached(["omarchy-tailscale-send", target])
  }

  function refresh(forceAccounts) {
    if (installed) {
      refreshStatusAndAccounts(forceAccounts === true)
      return
    }
    if (!whichProcess.running) {
      refreshing = true
      whichProcess.command = ["which", "tailscale"]
      whichProcess.running = true
    }
  }

  function refreshStatusAndAccounts(forceAccounts) {
    if (!installed) return
    var launched = false
    if (!statusProcess.running) {
      _statusOutput = ""
      _statusError = ""
      refreshing = true
      statusProcess.generation = _networkGeneration
      statusProcess.command = ["tailscale", "status", "--json"]
      statusProcess.running = true
      launched = true
    }
    if (!prefsProcess.running) {
      _prefsOutput = ""
      _prefsError = ""
      prefsProcess.generation = _networkGeneration
      prefsProcess.command = ["tailscale", "debug", "prefs"]
      prefsProcess.running = true
      launched = true
    }
    if (!mullvadExitNodesProcess.running) {
      _mullvadExitNodesOutput = ""
      _mullvadExitNodesError = ""
      mullvadExitNodesProcess.command = ["tailscale", "exit-node", "list"]
      mullvadExitNodesProcess.running = true
      launched = true
    }
    var now = Date.now()
    var shouldRefreshAccounts = forceAccounts === true || accounts.length === 0 || now - _lastAccountsRefreshMs > 60000
    if (shouldRefreshAccounts && !accountsProcess.running) {
      _accountsOutput = ""
      _accountsError = ""
      _lastAccountsRefreshMs = now
      accountsProcess.command = ["tailscale", "switch", "--list", "--json"]
      accountsProcess.running = true
      launched = true
    }
    // Arm on the launch that needs watching and leave it alone after that.
    // Restarting it every refresh pushes the deadline out ahead of a hung
    // process forever once the refresh interval is shorter than the timeout,
    // and refreshIntervalSec goes down to five seconds.
    if (launched && !pollWatchdog.running) pollWatchdog.start()
  }

  // Ported from hehh2001/omarchy-tailscale-plus @426b3cc (MIT): a mutation
  // makes the last status/prefs snapshot stale, and polls already in flight
  // are ignored when they land.
  function beginNetworkAction() {
    _networkGeneration += 1
    _statusValid = false
    _prefsValid = false
  }

  function elideStatus(text) {
    var value = String(text || "").replace(/\s+/g, " ").trim()
    return value.length > 140 ? value.substring(0, 137) + "…" : value
  }

  function resetUnavailable(message) {
    _statusValid = false
    running = false
    needsLogin = false
    _desired = -1
    backendState = "Unavailable"
    statusText = message
    selfName = ""
    selfDnsName = ""
    selfIp = ""
    selfUserId = ""
    fileSharing = false
    authUrl = ""
    blockedAuthUrl = ""
    exitNodeOnline = false
    peers = []
    exitNodes = []
    tailnetExitNodes = []
    mullvadExitNodes = []
    mullvadRegions = []
    accounts = []
    selectedAccountId = ""
    selectedAccountLabel = ""
    switchingAccountId = ""
    settingExitNodeId = ""
    accountsAccessDenied = false
  }

  function parseStatus(raw) {
    var parsed = Model.parseStatus(raw)
    if (!parsed.ok) {
      resetUnavailable(parsed.message || "Status error")
      lastError = parsed.error || "Failed to parse tailscale status"
      console.warn("tailscale", lastError)
      return
    }
    if (parsed.unavailable) {
      resetUnavailable(parsed.message || "Disconnected")
      return
    }

    _statusValid = true
    backendState = parsed.backendState
    running = parsed.running
    // Reality caught up to the pending toggle — stop overriding.
    if (_desired !== -1 && running === (_desired === 1)) _desired = -1
    needsLogin = parsed.needsLogin
    authUrl = parsed.authUrl
    // A control server's AuthURL is only ever opened whole and only when it is
    // a web URL; anything else is shown so the user can copy it by hand.
    blockedAuthUrl = authUrl !== "" && Model.wholeAuthUrl(authUrl) === "" ? authUrl : ""
    if (needsLogin && _loginInProgress && !_loginUrlOpened && authUrl !== "" && authUrl !== _preLoginAuthUrl) openAuthUrl(authUrl)
    selfName = parsed.selfName
    selfDnsName = parsed.selfDnsName
    selfIp = parsed.selfIp
    selfUserId = parsed.selfUserId
    fileSharing = parsed.fileSharing
    exitNodeOnline = parsed.exitNodeOnline
    peers = parsed.running ? parsed.peers : []
    tailnetExitNodes = parsed.running ? parsed.exitNodes : []
    exitNodes = parsed.running ? tailnetExitNodes.concat(mullvadRegions) : []

    if (needsLogin) statusText = "Needs login"
    else if (running) {
      statusText = "Connected"
      _loginInProgress = false
      _loginUrlOpened = false
      _preLoginAuthUrl = ""
      loginTimeoutTimer.stop()
    } else if (backendState === "Stopped") {
      statusText = "Disconnected"
    } else {
      statusText = backendState
    }
    lastError = ""
    maybeStartPendingLogin()
  }

  // Ported from hehh2001/omarchy-tailscale-plus @426b3cc (MIT): the persisted
  // preferences, including the exit-node choice, replace whatever the panel
  // showed before — there is no plugin-held selection to reconcile.
  function parsePrefs(raw) {
    var parsed = Model.parsePrefs(raw)
    if (!parsed.ok) {
      _prefsValid = false
      prefsLoaded = false
      lastError = parsed.error || "Could not read Tailscale settings"
      return
    }
    _prefsValid = true
    prefsLoaded = true
    acceptDns = parsed.acceptDns
    acceptRoutes = parsed.acceptRoutes
    allowLanAccess = parsed.allowLanAccess
    shieldsUp = parsed.shieldsUp
    runSsh = parsed.runSsh
    runWebClient = parsed.runWebClient
    advertiseExitNode = parsed.advertiseExitNode
    updateCheck = parsed.updateCheck
    autoUpdate = parsed.autoUpdate
    reportPosture = parsed.reportPosture
    operatorUser = parsed.operatorUser
    controlUrl = parsed.controlUrl
    loggedOut = parsed.loggedOut
    exitNodeId = parsed.exitNodeId
    exitNodeIp = parsed.exitNodeIp
    exitNodeActive = parsed.exitNodeActive
    maybeStartPendingLogin()
  }

  function parseAccounts(raw) {
    var parsed = Model.parseAccounts(raw)
    accounts = parsed.accounts
    selectedAccountId = parsed.selectedAccountId
    selectedAccountLabel = parsed.selectedAccountLabel
    accountsAccessDenied = false
  }

  function parseMullvadExitNodes(raw) {
    mullvadExitNodes = Model.parseExitNodeList(raw)
    mullvadRegions = Model.mullvadRegionOptions(mullvadExitNodes)
    exitNodes = running ? tailnetExitNodes.concat(mullvadRegions) : []
  }

  // Explicit inputs so a QML binding re-evaluates on every prefs refresh.
  function exitNodeStateFor(nodes, active, id, ip) {
    return Model.exitNodeState({ exitNodeActive: active, exitNodeId: id, exitNodeIp: ip }, nodes)
  }

  function notice(message) {
    actionStatus = String(message || "")
    actionStatusTimer.restart()
  }

  function preferenceValue(key) {
    var values = {
      acceptDns: acceptDns, acceptRoutes: acceptRoutes, allowLanAccess: allowLanAccess, shieldsUp: shieldsUp,
      runSsh: runSsh, runWebClient: runWebClient, advertiseExitNode: advertiseExitNode,
      updateCheck: updateCheck, autoUpdate: autoUpdate, reportPosture: reportPosture
    }
    return values[key] === true
  }

  // One `tailscale set --<flag>=<bool>` per toggle. A failure keeps the
  // switch where the CLI left it and shows the CLI's own reason.
  function togglePreference(key) {
    if (!installed || !prefsLoaded || settingProcess.running || loginBusy) return
    var command = Model.setPreferenceCommand(key, !preferenceValue(key))
    if (!command) return
    beginNetworkAction()
    changingSetting = String(key)
    _settingOutput = ""
    _settingError = ""
    settingProcess.command = command
    settingProcess.running = true
  }

  function toggleTailscale() {
    if (!installed || loginBusy) return
    if (active) down()
    else loginOrUp(false)
  }

  function down() {
    // No progress status here — the greyed icon and hero line already convey
    // the optimistic off; only surface a message if the command fails.
    _desired = 0
    runAction(["tailscale", "down"])
  }

  function loginPlanFor(rebind) {
    return Model.loginPlan({
      needsLogin: needsLogin,
      authUrl: authUrl,
      loginServer: loginServer,
      controlUrl: controlUrl,
      operatorUser: operatorUser,
      userName: userName,
      rebind: rebind === true
    })
  }

  function showActionError(message) {
    lastError = elideStatus(message)
    actionStatus = lastError
    actionStatusTimer.restart()
  }

  // Turn on, or start a fresh login. A plan that begins with `tailscale
  // logout` deletes this profile, so it only runs from rebindLoginServer(),
  // which the panel reaches through an explicit confirmation.
  function loginOrUp(confirmedRebind) {
    if (!installed || loginBusy) return
    _desired = -1
    var plan = loginPlanFor(confirmedRebind === true)
    if (plan.error !== "") { showActionError(plan.error); return }
    if (plan.authUrl !== "") {
      _loginUrlOpened = false
      openAuthUrl(plan.authUrl)
      return
    }
    if (plan.logoutFirst && confirmedRebind !== true) {
      showActionError("Logged out of " + controlUrl + " — confirm the login server row to log in to " + plan.loginServer)
      return
    }
    startLoginPlan(plan)
  }

  function rebindLoginServer() {
    loginOrUp(true)
  }

  function startLoginPlan(plan) {
    if (!plan || plan.steps.length === 0) return
    beginNetworkAction()
    _loginPlan = plan
    _loginStep = -1
    _loginOutput = ""
    _loginError = ""
    _loginUrlOpened = false
    _preLoginAuthUrl = authUrl
    _loginInProgress = needsLogin || plan.logoutFirst || plan.steps.length > 1
    if (!_loginInProgress) _desired = 1
    actionStatus = plan.logoutFirst
      ? "Logging out, then logging in to " + plan.loginServer + "…"
      : (_loginInProgress ? "Starting Tailscale login…" : "")
    runNextLoginStep()
  }

  function runNextLoginStep() {
    if (!_loginPlan) return
    _loginStep += 1
    if (_loginStep >= _loginPlan.steps.length) {
      _loginPlan = null
      _loginStep = -1
      return
    }
    var step = _loginPlan.steps[_loginStep]
    if (step.kind === "logout") {
      _logoutOutput = ""
      _logoutError = ""
      logoutProcess.command = step.command
      logoutProcess.running = true
    } else if (step.kind === "operator") {
      _operatorOutput = ""
      _operatorError = ""
      actionStatus = "Authorizing Tailscale operator to continue login…"
      operatorProcess.command = step.command
      operatorProcess.running = true
    } else {
      loginProcess.command = step.command
      loginProcess.running = true
      if (_loginInProgress) loginTimeoutTimer.restart()
    }
  }

  function failLoginStep(exitCode, detail) {
    var message = Model.loginStepFailure(_loginPlan, _loginStep, exitCode, detail)
    _loginPlan = null
    _loginStep = -1
    _desired = -1
    _loginInProgress = false
    loginTimeoutTimer.stop()
    showActionError(message)
    _lastAccountsRefreshMs = 0
    delayedRefresh.restart()
  }

  // After a switch landed on a logged-out profile: log in once a fresh
  // status and prefs snapshot describes that profile, not the old one.
  function maybeStartPendingLogin() {
    if (!_pendingLoginAfterRefresh || !_statusValid || !_prefsValid) return
    _pendingLoginAfterRefresh = false
    if (needsLogin) loginOrUp(false)
  }

  function switchAccount(id) {
    var accountId = String(id || "")
    if (!installed || accountId === "" || accountId === selectedAccountId || switchProcess.running || loginBusy) return
    // The id is a bare positional to `tailscale switch`; never let it look like a flag.
    if (!Model.isProfileId(accountId)) { showActionError("Refusing to switch to an oddly named profile"); return }
    beginNetworkAction()
    _switchOutput = ""
    _switchError = ""
    _switchTargetId = accountId
    switchingAccountId = accountId
    switchProcess.command = ["tailscale", "switch", accountId]
    switchProcess.running = true
  }

  function exitNodeTarget(peer) {
    if (!peer) return ""
    if (peer.Mullvad === true) {
      var mullvadIps = filterIPv4(peer.TailscaleIPs || [])
      if (mullvadIps.length > 0) return mullvadIps[0]
    }
    return peerAddress(peer)
  }

  function setExitNode(peer) {
    if (!installed || !running || !peer || exitNodeProcess.running) return
    var active = peer.ExitNode === true
    var target = active ? "" : exitNodeTarget(peer)
    if (!active && target === "") return
    beginNetworkAction()
    _exitNodeOutput = ""
    _exitNodeError = ""
    settingExitNodeId = String(peer.id || "")
    exitNodeProcess.command = ["tailscale", "set", "--exit-node=" + target]
    exitNodeProcess.running = true
  }

  function authorizeTailscaleOperator() {
    if (!installed || operatorProcess.running || userName === "") return
    _operatorOutput = ""
    _operatorError = ""
    actionStatus = "Authorizing Tailscale operator..."
    operatorProcess.command = ["pkexec", "tailscale", "set", "--operator=" + userName]
    operatorProcess.running = true
  }

  function runAction(command, label) {
    if (actionProcess.running) return
    beginNetworkAction()
    _actionOutput = ""
    _actionError = ""
    actionStatus = label || ""
    actionProcess.command = command
    actionProcess.running = true
  }

  // The only way a URL reaches the browser: whole, and http(s).
  function openAuthUrl(url) {
    var text = String(url || "")
    if (_loginUrlOpened) return true
    if (Model.wholeAuthUrl(text) === "") {
      if (text !== "") {
        blockedAuthUrl = text
        showActionError("Login link is not a web URL — copy it from the panel instead")
      }
      return false
    }
    // Turning on ended up needing browser auth — stop pretending we're up.
    _desired = -1
    _loginUrlOpened = true
    _loginInProgress = false
    loginTimeoutTimer.stop()
    Quickshell.execDetached(["xdg-open", text])
    return true
  }

  // CLI output: the first http(s) token in the text, nothing else.
  function openAuthUrlFrom(text) {
    if (_loginUrlOpened) return true
    var url = Model.authUrlIn(text)
    return url !== "" ? openAuthUrl(url) : false
  }

  function handleLoginOutput(data, isError) {
    var text = String(data || "")
    if (isError) _loginError += text + "\n"
    else _loginOutput += text + "\n"
    if (_loginInProgress && !_loginUrlOpened) openAuthUrlFrom(text)
  }

  Timer {
    id: refreshTimer
    interval: root.refreshIntervalSec * 1000
    repeat: true
    running: true
    triggeredOnStart: true
    onTriggered: root.refresh()
  }

  Timer {
    // After a fresh boot the startup poll usually lands before tailscaled has
    // connected, which left the icon stale until the next periodic refresh.
    // Poll quickly until the service shows up, or give up after ~30 seconds.
    id: startupRamp
    property int ticks: 0
    interval: 2000
    repeat: true
    running: true
    onTriggered: {
      ticks += 1
      if (root.running || ticks >= 15) startupRamp.running = false
      else root.refresh()
    }
  }

  Timer {
    id: delayedRefresh
    interval: 600
    repeat: false
    onTriggered: root.refresh()
  }

  Timer {
    // Every poll is skipped while its own process is still running, so one that
    // never exits — tailscale can hang on a network that is coming and going —
    // silently stops the panel refreshing at all, and it stays stopped. Reap
    // anything still running well inside the refresh interval so the next tick
    // starts clean.
    id: pollWatchdog
    interval: 15000
    repeat: false
    onTriggered: {
      if (statusProcess.running) statusProcess.running = false
      if (prefsProcess.running) prefsProcess.running = false
      if (mullvadExitNodesProcess.running) mullvadExitNodesProcess.running = false
      if (accountsProcess.running) accountsProcess.running = false
    }
  }

  Timer {
    id: actionStatusTimer
    interval: 2200
    repeat: false
    onTriggered: root.actionStatus = ""
  }

  Timer {
    id: loginTimeoutTimer
    interval: 10000
    repeat: false
    onTriggered: {
      if (!root._loginInProgress || root._loginUrlOpened) return
      if (!root.openAuthUrl(root.authUrl)) {
        root._loginInProgress = false
        root.actionStatus = "Tailscale login link not available yet"
      }
    }
  }

  Process {
    id: whichProcess
    running: false
    command: []
    onExited: function(exitCode) {
      root.installed = exitCode === 0
      if (root.installed) root.refreshStatusAndAccounts()
      else {
        root.refreshing = false
        root.resetUnavailable("Not installed")
      }
    }
  }

  Process {
    id: statusProcess
    property int generation: 0
    running: false
    command: []
    stdout: StdioCollector { id: statusStdout; waitForEnd: true; onStreamFinished: root._statusOutput = text }
    stderr: StdioCollector { id: statusStderr; waitForEnd: true; onStreamFinished: root._statusError = text }
    onExited: function(exitCode) {
      root.refreshing = false
      if (generation !== root._networkGeneration) return
      var stdout = String(statusStdout.text || root._statusOutput || "")
      var stderr = String(statusStderr.text || root._statusError || "")
      if (exitCode === 0) root.parseStatus(stdout)
      else {
        root.resetUnavailable("Disconnected")
        root.lastError = stderr.trim()
      }
    }
  }

  Process {
    id: prefsProcess
    property int generation: 0
    running: false
    command: []
    stdout: StdioCollector { id: prefsStdout; waitForEnd: true; onStreamFinished: root._prefsOutput = text }
    stderr: StdioCollector { id: prefsStderr; waitForEnd: true; onStreamFinished: root._prefsError = text }
    onExited: function(exitCode) {
      if (generation !== root._networkGeneration) return
      var stdout = String(prefsStdout.text || root._prefsOutput || "")
      var stderr = String(prefsStderr.text || root._prefsError || "")
      if (exitCode === 0) root.parsePrefs(stdout)
      else {
        root._prefsValid = false
        root.prefsLoaded = false
        root.lastError = elideStatus(stderr || "Could not read Tailscale settings")
      }
    }
  }

  Process {
    id: accountsProcess
    running: false
    command: []
    stdout: StdioCollector { id: accountsStdout; waitForEnd: true; onStreamFinished: root._accountsOutput = text }
    stderr: StdioCollector { id: accountsStderr; waitForEnd: true; onStreamFinished: root._accountsError = text }
    onExited: function(exitCode) {
      var stdout = String(accountsStdout.text || root._accountsOutput || "")
      var stderr = String(accountsStderr.text || root._accountsError || "")
      if (exitCode === 0) {
        root.parseAccounts(stdout)
        // Secondary, structural check after a failed switch: the profile the
        // user picked is gone from the fresh list, so it was stale — say so.
        if (root._switchTargetId !== "") {
          var target = root._switchTargetId
          root._switchTargetId = ""
          if (!Model.profileListed(root.accounts, target)) root.showActionError("That connection no longer exists; the list has been refreshed")
        }
      } else {
        root.parseAccounts("")
        root._switchTargetId = ""
        if (/profiles access denied/i.test(stderr) || /profiles access denied/i.test(stdout)) {
          root.accountsAccessDenied = true
          root.lastError = "Authorize Tailscale operator to show connections"
        } else {
          root.lastError = elideStatus(stderr || stdout || "Could not list Tailscale connections")
        }
      }
    }
  }

  Process {
    id: mullvadExitNodesProcess
    running: false
    command: []
    stdout: StdioCollector { id: mullvadExitNodesStdout; waitForEnd: true; onStreamFinished: root._mullvadExitNodesOutput = text }
    stderr: StdioCollector { id: mullvadExitNodesStderr; waitForEnd: true; onStreamFinished: root._mullvadExitNodesError = text }
    onExited: function(exitCode) {
      var stdout = String(mullvadExitNodesStdout.text || root._mullvadExitNodesOutput || "")
      if (exitCode === 0) root.parseMullvadExitNodes(stdout)
      else root.parseMullvadExitNodes("")
    }
  }

  Process {
    id: actionProcess
    running: false
    command: []
    stdout: StdioCollector { id: actionStdout; waitForEnd: true; onStreamFinished: root._actionOutput = text }
    stderr: StdioCollector { id: actionStderr; waitForEnd: true; onStreamFinished: root._actionError = text }
    onExited: function(exitCode) {
      var stdout = String(actionStdout.text || root._actionOutput || "")
      var stderr = String(actionStderr.text || root._actionError || "")
      if (exitCode !== 0) {
        root._desired = -1
        root.lastError = elideStatus(stderr || stdout || "Tailscale command failed")
        root.actionStatus = root.lastError
        actionStatusTimer.restart()
      } else {
        root.lastError = ""
        root.actionStatus = ""
      }
      delayedRefresh.restart()
    }
  }

  Process {
    id: loginProcess
    running: false
    command: []
    stdout: SplitParser { onRead: function(data) { root.handleLoginOutput(data, false) } }
    stderr: SplitParser { onRead: function(data) { root.handleLoginOutput(data, true) } }
    onExited: function(exitCode) {
      var combined = String(root._loginOutput || "") + "\n" + String(root._loginError || "")
      var opened = root.openAuthUrlFrom(combined)
      if (!opened && root._loginInProgress && root.authUrl !== "") opened = root.openAuthUrl(root.authUrl)
      if (exitCode !== 0 && !opened) {
        root.failLoginStep(exitCode, combined)
        return
      }
      root._loginPlan = null
      root._loginStep = -1
      if (!opened) {
        root.lastError = ""
        root.actionStatus = ""
      }
      delayedRefresh.restart()
    }
  }

  Process {
    id: logoutProcess
    running: false
    command: []
    stdout: StdioCollector { id: logoutStdout; waitForEnd: true; onStreamFinished: root._logoutOutput = text }
    stderr: StdioCollector { id: logoutStderr; waitForEnd: true; onStreamFinished: root._logoutError = text }
    onExited: function(exitCode) {
      var stdout = String(logoutStdout.text || root._logoutOutput || "")
      var stderr = String(logoutStderr.text || root._logoutError || "")
      root._lastAccountsRefreshMs = 0
      if (exitCode !== 0) root.failLoginStep(exitCode, stderr || stdout)
      else root.runNextLoginStep()
    }
  }

  Process {
    id: switchProcess
    running: false
    command: []
    stdout: StdioCollector { id: switchStdout; waitForEnd: true; onStreamFinished: root._switchOutput = text }
    stderr: StdioCollector { id: switchStderr; waitForEnd: true; onStreamFinished: root._switchError = text }
    onExited: function(exitCode) {
      var stdout = String(switchStdout.text || root._switchOutput || "")
      var stderr = String(switchStderr.text || root._switchError || "")
      // Ported from hehh2001/omarchy-tailscale-plus @426b3cc (MIT), with the
      // outcomes tailscale 1.102.3 actually produces: a switch that lands on a
      // logged-out profile exits 0 saying "Logged out." — start a fresh login
      // once the next poll describes that profile instead of retrying the
      // switch. A missing profile is a plain error plus a list refresh.
      var outcome = Model.switchOutcome(exitCode, stdout, stderr)
      if (outcome === "needsLogin") {
        root.lastError = ""
        root.actionStatus = "Connection is logged out — starting a fresh login…"
        root._pendingLoginAfterRefresh = true
        root._switchTargetId = ""
      } else if (outcome === "ok") {
        root.lastError = ""
        root.actionStatus = ""
        root._switchTargetId = ""
      } else {
        root.showActionError(stderr || stdout || "Account switch failed")
      }
      root._lastAccountsRefreshMs = 0
      root.switchingAccountId = ""
      delayedRefresh.restart()
    }
  }

  Process {
    id: settingProcess
    running: false
    command: []
    stdout: StdioCollector { id: settingStdout; waitForEnd: true; onStreamFinished: root._settingOutput = text }
    stderr: StdioCollector { id: settingStderr; waitForEnd: true; onStreamFinished: root._settingError = text }
    onExited: function(exitCode) {
      var stdout = String(settingStdout.text || root._settingOutput || "")
      var stderr = String(settingStderr.text || root._settingError || "")
      if (exitCode !== 0) root.showActionError(stderr || stdout || "Tailscale setting failed")
      else {
        root.lastError = ""
        root.actionStatus = ""
      }
      root.changingSetting = ""
      delayedRefresh.restart()
    }
  }

  Process {
    id: clipboardProcess
    property string payload: ""
    running: false
    command: ["wl-copy"]
    stdinEnabled: true
    onStarted: {
      write(payload)
      payload = ""
      // Closing stdin is what lets wl-copy take the value and fork away.
      stdinEnabled = false
    }
    onExited: function(exitCode) { if (exitCode !== 0) root.showActionError("Copy failed: wl-copy exited " + exitCode) }
  }

  Process {
    id: exitNodeProcess
    running: false
    command: []
    stdout: StdioCollector { id: exitNodeStdout; waitForEnd: true; onStreamFinished: root._exitNodeOutput = text }
    stderr: StdioCollector { id: exitNodeStderr; waitForEnd: true; onStreamFinished: root._exitNodeError = text }
    onExited: function(exitCode) {
      var stdout = String(exitNodeStdout.text || root._exitNodeOutput || "")
      var stderr = String(exitNodeStderr.text || root._exitNodeError || "")
      if (exitCode !== 0) {
        root.lastError = elideStatus(stderr || stdout || "Exit node selection failed")
        root.actionStatus = root.lastError
        actionStatusTimer.restart()
      } else {
        root.lastError = ""
        root.actionStatus = ""
      }
      root.settingExitNodeId = ""
      delayedRefresh.restart()
    }
  }

  Process {
    id: operatorProcess
    running: false
    command: []
    stdout: StdioCollector { id: operatorStdout; waitForEnd: true; onStreamFinished: root._operatorOutput = text }
    stderr: StdioCollector { id: operatorStderr; waitForEnd: true; onStreamFinished: root._operatorError = text }
    onExited: function(exitCode) {
      var stdout = String(operatorStdout.text || root._operatorOutput || "")
      var stderr = String(operatorStderr.text || root._operatorError || "")
      var loginStep = root._loginPlan !== null && root._loginStep >= 0
      if (exitCode !== 0) {
        if (loginStep) root.failLoginStep(exitCode, stderr || stdout)
        else root.showActionError(stderr || stdout || "Tailscale authorization failed")
        return
      }
      root.accountsAccessDenied = false
      root.operatorUser = root.userName
      root.lastError = ""
      root._lastAccountsRefreshMs = 0
      if (loginStep) {
        root.runNextLoginStep()
        return
      }
      root.actionStatus = "Tailscale operator authorized"
      actionStatusTimer.restart()
      delayedRefresh.restart()
    }
  }
}
