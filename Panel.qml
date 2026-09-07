import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model

Panel {
  id: root
  moduleName: "omarchy.tailscale"
  ipcTarget: "omarchy.tailscale"
  manageIpc: false

  // "main" (hero → connections → exit nodes → machines) or "settings" (the
  // cog's page: the `tailscale set` switches and the login-server row).
  property string page: "main"
  property string focusSection: "header"
  property int headerIndex: 0
  property int accountIndex: 0
  property int peerIndex: 0
  property int exitNodeIndex: 0
  property int settingIndex: 0
  property int mullvadRegionIndex: 0
  // Rebinding to another control server logs out and deletes this profile:
  // one activation arms the row, a second fires it, Esc disarms.
  property bool rebindArmed: false
  property bool cursorActive: false
  // The pointer's row, painted like the cursor but never what Enter acts on:
  // the keyboard cursor above moves with j/k, a click, or hover only when the
  // hoverSelects setting says so (Model.pointerSelects).
  property string hoverSection: ""
  property int hoverIndex: -1
  readonly property bool hoverSelects: setting("hoverSelects", false) === true
  property bool copyMenuOpen: false
  property bool mullvadPickerOpen: false
  property string mullvadQuery: ""
  property int phraseIndex: 0
  readonly property var activePhrases: [
    "Encrypting connections",
    "Sending secrets",
    "Guarding wires",
    "Braiding packets",
    "Polishing tunnels",
    "Hiding routes",
    "Sealing ports",
    "Sorting tailnets",
    "Shuffling keys",
    "Watching machines"
  ]
  readonly property string heroPhraseText: activePhrases[phraseIndex % activePhrases.length]

  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color urgent: bar ? bar.urgent : Color.urgent
  readonly property color online: "#00ff88"
  readonly property color dim: Qt.darker(foreground, 1.55)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property bool showLoginServer: tailscale.installed && (tailscale.loginServerDiffers || !tailscale.loginServerCheck.ok)
  readonly property bool showConnections: tailscale.accounts.length > 1 || tailscale.accountsAccessDenied
  readonly property bool showPeers: tailscale.active && tailscale.peers.length > 0
  readonly property bool showSettings: tailscale.installed && tailscale.active && tailscale.prefsLoaded
  readonly property bool hasSettingsPage: showSettings || showLoginServer
  readonly property bool mainPage: page === "main"
  readonly property bool settingsPage: page === "settings"
  readonly property string controlServerText: tailscale.controlUrl === "" ? "Not bound to a control server" : "Control server · " + tailscale.controlUrl
  readonly property var recentMullvadRegions: settings.recentMullvadRegions instanceof Array ? settings.recentMullvadRegions : (settings.recentMullvadCountries instanceof Array ? settings.recentMullvadCountries : [])
  readonly property var recentMullvadExitNodes: recentMullvadNodes()
  readonly property var exitNodes: displayExitNodes()
  readonly property bool showExitNodes: tailscale.active && (exitNodes.length > 0 || tailscale.mullvadRegions.length > 0 || tailscale.exitNodeActive)
  // Ported from hehh2001/omarchy-tailscale-plus @426b3cc (MIT): what the
  // exit-node section says it is using comes from the persisted preference
  // read on the last refresh, never from a row the panel remembers clicking.
  readonly property var exitNodeSummary: tailscale.exitNodeStateFor(exitNodes, tailscale.exitNodeActive, tailscale.exitNodeId, tailscale.exitNodeIp)
  // Labels as hehh2001/omarchy-tailscale-plus @426b3cc (MIT) labels them.
  readonly property var preferenceRows: [
    { key: "acceptDns", label: "Tailscale DNS", detail: "Use DNS supplied by the active tailnet", value: tailscale.acceptDns },
    { key: "acceptRoutes", label: "Use subnet routes", detail: "Accept routes advertised by other machines", value: tailscale.acceptRoutes },
    { key: "allowLanAccess", label: "Local network access", detail: "Keep direct LAN access while using an exit node", value: tailscale.allowLanAccess },
    { key: "shieldsUp", label: "Block incoming connections", detail: "Reject incoming Tailscale connections", value: tailscale.shieldsUp },
    { key: "runSsh", label: "Tailscale SSH", detail: "Allow SSH according to tailnet policy", value: tailscale.runSsh },
    { key: "runWebClient", label: "Web management", detail: "Expose the Tailscale web UI on port 5252", value: tailscale.runWebClient },
    { key: "advertiseExitNode", label: "Offer as exit node", detail: "Advertise this machine as an internet gateway", value: tailscale.advertiseExitNode },
    { key: "updateCheck", label: "Update notifications", detail: "Check for available Tailscale updates", value: tailscale.updateCheck },
    { key: "autoUpdate", label: "Automatic updates", detail: "Install Tailscale updates automatically", value: tailscale.autoUpdate },
    { key: "reportPosture", label: "Device posture", detail: "Allow posture collection by the control plane", value: tailscale.reportPosture }
  ]
  readonly property string rebindTitle: !tailscale.loginServerCheck.ok ? "Login server setting is invalid" : (rebindArmed ? "Press again to confirm" : "Log in to " + tailscale.loginServerUrl)
  readonly property string rebindDetail: !tailscale.loginServerCheck.ok
    ? tailscale.loginServerCheck.error
    : (rebindArmed
      ? "Logs out of " + tailscale.controlUrl + " and removes that profile · Esc cancels"
      : "Logs out of " + tailscale.controlUrl + " first; confirmed before anything runs")
  readonly property var filteredMullvadRegions: filteredMullvadRegionNodes()
  // The header holds one cursor target per control, walked with h/l: on main
  // the cog (when there is a settings page) and the switch (when the CLI is
  // present); on settings only the back button.
  readonly property int cogHeaderIndex: page === "main" && hasSettingsPage ? 0 : -1
  readonly property int toggleHeaderIndex: page === "main" && tailscale.installed ? (hasSettingsPage ? 1 : 0) : -1
  readonly property int headerActionCount: page === "settings" ? 1 : (hasSettingsPage ? 1 : 0) + (tailscale.installed ? 1 : 0)
  readonly property bool cogHasCursor: cogHeaderIndex !== -1 && rowHasCursor("header", cogHeaderIndex)
  readonly property bool toggleHasCursor: toggleHeaderIndex !== -1 && rowHasCursor("header", toggleHeaderIndex)
  readonly property bool backHasCursor: page === "settings" && rowHasCursor("header", 0)
  readonly property color iconColor: tailscale.active ? foreground : dim
  readonly property string toggleHint: tailscale.active ? "Turn Tailscale off" : (tailscale.needsLogin ? "Authorize this device" : "Turn Tailscale on")
  readonly property color barIconColor: tailscale.active ? barForeground : Qt.darker(barForeground, 1.55)
  readonly property color hoverFill: bar ? Style.hoverFillFor(bar.foreground, Color.accent) : "transparent"
  readonly property color selectedFill: bar ? Style.selectedFillFor(bar.foreground, Color.accent) : "transparent"

  function selectedPeer() {
    if (tailscale.peers.length === 0) return null
    return tailscale.peers[Math.max(0, Math.min(peerIndex, tailscale.peers.length - 1))]
  }

  function selectedExitNode() {
    if (exitNodes.length === 0) return null
    return exitNodes[Math.max(0, Math.min(exitNodeIndex, exitNodes.length - 1))]
  }

  function selectedMullvadRegion() {
    if (filteredMullvadRegions.length === 0) return null
    return filteredMullvadRegions[Math.max(0, Math.min(mullvadRegionIndex, filteredMullvadRegions.length - 1))]
  }

  function displayExitNodes() {
    var nodes = []
    for (var i = 0; i < tailscale.tailnetExitNodes.length; i++) nodes.push(tailscale.tailnetExitNodes[i])
    for (var j = 0; j < recentMullvadExitNodes.length; j++) nodes.push(recentMullvadExitNodes[j])
    if (tailscale.mullvadRegions.length > 0) nodes.push({ id: "mullvad:add", AddMullvad: true, DisplayName: "Choose Mullvad region" })
    return nodes
  }

  function recentMullvadNodes() {
    var nodes = []
    var seen = {}
    for (var a = 0; a < tailscale.mullvadRegions.length && nodes.length < 5; a++) {
      var active = tailscale.mullvadRegions[a]
      var activeKey = mullvadRegionKey(active)
      if (active.ExitNode === true && activeKey !== "" && !seen[activeKey]) {
        nodes.push(active)
        seen[activeKey] = true
      }
    }
    for (var i = 0; i < recentMullvadRegions.length && nodes.length < 5; i++) {
      var region = String(recentMullvadRegions[i] || "")
      if (region === "" || seen[region]) continue
      var node = mullvadRegionNode(region)
      if (node) {
        nodes.push(node)
        seen[region] = true
      }
    }
    return nodes
  }

  function mullvadRegionKey(node) {
    if (!node) return ""
    var country = String(node.Country || "")
    var city = String(node.City || "")
    if (country === "" || city === "") return ""
    return country + "\n" + city
  }

  function mullvadRegionNode(region) {
    for (var i = 0; i < tailscale.mullvadRegions.length; i++) {
      var node = tailscale.mullvadRegions[i]
      if (mullvadRegionKey(node) === String(region || "")) return node
      if (String(node.Country || "") === String(region || "")) return node
    }
    return null
  }

  function filteredMullvadRegionNodes() {
    var query = String(mullvadQuery || "").trim().toLowerCase()
    var result = []
    for (var i = 0; i < tailscale.mullvadRegions.length; i++) {
      var node = tailscale.mullvadRegions[i]
      var label = (String(node.City || "") + " " + String(node.Country || "")).toLowerCase()
      if (query === "" || label.indexOf(query) !== -1) result.push(node)
    }
    return result
  }

  function mullvadRegionTitle(peer) {
    if (!peer) return "Unknown"
    var city = String(peer.City || "").trim()
    var country = String(peer.Country || "").trim()
    if (city === "" || city === "Any") return country || String(peer.DisplayName || "Unknown")
    return city
  }

  function mullvadRegionSubtitle(peer) {
    if (!peer) return ""
    return String(peer.Country || "").trim()
  }

  function persistRecentMullvad(region) {
    var name = String(region || "")
    if (name === "") return
    var next = [name]
    for (var i = 0; i < recentMullvadRegions.length && next.length < 5; i++) {
      var existing = String(recentMullvadRegions[i] || "")
      if (existing !== "" && existing !== name && next.indexOf(existing) === -1) next.push(existing)
    }
    if (!root.bar || !root.bar.shell || typeof root.bar.shell.updateEntryInline !== "function") return
    var entry = { id: root.moduleName }
    for (var key in settings) if (key !== "id") entry[key] = settings[key]
    entry.recentMullvadRegions = next
    root.bar.shell.updateEntryInline(root.moduleName, entry)
  }

  function chooseExitNode(peer) {
    if (!peer) return
    if (peer.AddMullvad === true) {
      mullvadPickerOpen = !mullvadPickerOpen
      mullvadRegionIndex = 0
      if (mullvadPickerOpen) Qt.callLater(function() { if (mullvadSearch) mullvadSearch.forceActiveFocus() })
      return
    }
    if (peer.Mullvad === true) persistRecentMullvad(mullvadRegionKey(peer))
    tailscale.setExitNode(peer)
    mullvadPickerOpen = false
  }

  function selectedAccount() {
    if (tailscale.accounts.length === 0) return null
    return tailscale.accounts[Math.max(0, Math.min(accountIndex, tailscale.accounts.length - 1))]
  }

  // The keyboard cursor walks the current page's sections top to bottom
  // (Model.PAGE_SECTIONS); each one is a list with its own index. Adding a
  // section means adding it there and to sectionCount/sectionIndex, not to a
  // chain of fallbacks.
  function sectionList() {
    return Model.pageSections(page, {
      auth: tailscale.accountsAccessDenied,
      loginServer: showLoginServer,
      accounts: tailscale.accounts.length > 1,
      exitNodes: showExitNodes,
      settings: showSettings,
      peers: showPeers
    })
  }

  function sectionCount(name) {
    if (name === "header") return headerActionCount
    if (name === "accounts") return tailscale.accounts.length
    if (name === "exitNodes") return exitNodes.length
    if (name === "settings") return preferenceRows.length
    if (name === "peers") return tailscale.peers.length
    return 1
  }

  function sectionIndex(name) {
    if (name === "header") return headerIndex
    if (name === "accounts") return accountIndex
    if (name === "exitNodes") return exitNodeIndex
    if (name === "settings") return settingIndex
    if (name === "peers") return peerIndex
    return 0
  }

  function setSectionIndex(name, index) {
    var value = Math.max(0, Math.min(index, sectionCount(name) - 1))
    if (name === "header") headerIndex = value
    else if (name === "accounts") accountIndex = value
    else if (name === "exitNodes") exitNodeIndex = value
    else if (name === "settings") settingIndex = value
    else if (name === "peers") peerIndex = value
  }

  // Does this row paint the cursor ring? True for the pointer's row and for
  // the keyboard cursor's row while the cursor is active.
  function rowHasCursor(section, index) {
    return Model.rowHasCursor(section, index,
      { section: hoverSection, index: hoverIndex },
      { active: cursorActive, section: focusSection, index: sectionIndex(section) })
  }

  // Pointer entered a row: paint it, and move the keyboard cursor only when
  // the hoverSelects setting asks for the old behaviour.
  function hover(section, index) {
    hoverSection = section
    hoverIndex = index
    if (Model.pointerSelects("hover", hoverSelects)) selectCursor(section, index)
  }

  function unhover(section, index) {
    if (hoverSection === section && hoverIndex === index) { hoverSection = ""; hoverIndex = -1 }
  }

  // The Mullvad picker's Enter acts on mullvadRegionIndex, which the search
  // field's j/k drive; hover paints the row and moves that index only when
  // hoverSelects opts in.
  function hoverMullvadRegion(index) {
    hoverSection = "mullvad"
    hoverIndex = index
    if (Model.pointerSelects("hover", hoverSelects)) mullvadRegionIndex = index
  }

  // A click (or a hover-select) puts the keyboard cursor on the row, so j/k
  // continue from what was just clicked.
  function selectCursor(section, index) {
    cursorActive = true
    focusSection = section
    setSectionIndex(section, index)
  }

  function ensureCursor() {
    setSectionIndex("header", headerIndex)
    setSectionIndex("accounts", accountIndex)
    setSectionIndex("peers", peerIndex)
    setSectionIndex("exitNodes", exitNodeIndex)
    setSectionIndex("settings", settingIndex)
    if (mullvadRegionIndex >= filteredMullvadRegions.length) mullvadRegionIndex = Math.max(0, filteredMullvadRegions.length - 1)
    var list = sectionList()
    if (list.indexOf(focusSection) !== -1) return
    // The section under the cursor went away: land on the nearest one that
    // is still visible, preferring the one below it.
    var order = Model.pageOrder(page)
    var from = order.indexOf(focusSection)
    for (var below = from + 1; below < order.length; below++) if (list.indexOf(order[below]) !== -1) { focusSection = order[below]; return }
    for (var above = from - 1; above >= 0; above--) if (list.indexOf(order[above]) !== -1) { focusSection = order[above]; return }
    focusSection = "header"
  }

  // Leaving a page forgets its transient state: the cursor lands on the new
  // page's header, the switches start at the first row, an armed rebind and
  // an open Mullvad picker are dropped, and the view scrolls back to the top.
  function showPage(next) {
    var entered = Model.enterPage(next)
    if (entered.page === page) return
    page = entered.page
    focusSection = entered.focusSection
    headerIndex = entered.headerIndex
    settingIndex = entered.settingIndex
    rebindArmed = entered.rebindArmed
    mullvadPickerOpen = false
    hoverSection = ""
    hoverIndex = -1
    if (panelFlick) panelFlick.contentY = 0
    ensureCursor()
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  function openSettings() { showPage("settings") }
  function closeSettings() { showPage("main") }

  function moveCursor(dx, dy) {
    cursorActive = true
    ensureCursor()
    // h/l walk the header's controls; j/k treat the header as one row.
    if (dx !== 0 && focusSection === "header") setSectionIndex("header", headerIndex + dx)
    if (dy !== 0) {
      var list = sectionList()
      var pos = list.indexOf(focusSection)
      var oneRow = focusSection === "header"
      var index = oneRow ? 0 : sectionIndex(focusSection)
      var count = oneRow ? 1 : sectionCount(focusSection)
      if (dy > 0) {
        if (index < count - 1) setSectionIndex(focusSection, index + 1)
        else if (pos < list.length - 1) { focusSection = list[pos + 1]; setSectionIndex(focusSection, 0) }
      } else {
        if (index > 0) setSectionIndex(focusSection, index - 1)
        else if (pos > 0) { focusSection = list[pos - 1]; if (focusSection !== "header") setSectionIndex(focusSection, sectionCount(focusSection) - 1) }
      }
    }
    if (focusSection !== "loginServer") rebindArmed = false
    ensureCursor()
    scrollCursorIntoView()
  }

  function activateHeader() {
    if (page === "settings") closeSettings()
    else if (headerIndex === cogHeaderIndex) openSettings()
    else if (headerIndex === toggleHeaderIndex) tailscale.toggleTailscale()
  }

  function activateCursor() {
    ensureCursor()
    if (focusSection === "header") {
      activateHeader()
    } else if (focusSection === "auth") {
      tailscale.authorizeTailscaleOperator()
    } else if (focusSection === "loginServer") {
      activateRebind()
    } else if (focusSection === "accounts") {
      var account = selectedAccount()
      if (account) tailscale.switchAccount(account.id)
    } else if (focusSection === "peers") {
      openSelectedPeerCopyMenu()
    } else if (focusSection === "exitNodes") {
      chooseExitNode(selectedExitNode())
    } else if (focusSection === "settings") {
      if (settingIndex >= 0 && settingIndex < preferenceRows.length) tailscale.togglePreference(preferenceRows[settingIndex].key)
    }
  }

  // First activation arms, second fires; anything else disarms.
  function activateRebind() {
    if (!tailscale.loginServerCheck.ok || tailscale.loginBusy) return
    if (!rebindArmed) { rebindArmed = true; return }
    rebindArmed = false
    tailscale.rebindLoginServer()
  }

  // Peer shortcuts act on the machine under the cursor and nothing else.
  function peerShortcut(action) {
    if (focusSection !== "peers" || !cursorActive) {
      tailscale.notice("Move the cursor into Machines first (j/k)")
      return
    }
    action(selectedPeer())
  }

  function moveMullvadRegionCursor(delta) {
    if (filteredMullvadRegions.length === 0) return
    cursorActive = true
    mullvadRegionIndex = Math.max(0, Math.min(filteredMullvadRegions.length - 1, mullvadRegionIndex + delta))
    scrollMullvadRegionCursorIntoView()
  }

  function activateMullvadRegionCursor() {
    var region = selectedMullvadRegion()
    if (region) chooseExitNode(region)
  }

  function scrollItemIntoView(item) {
    if (!panelFlick || !item) return
    Qt.callLater(function() {
      if (!item) return
      var margin = Style.space(6)
      var point = item.mapToItem(panelFlick.contentItem, 0, 0)
      var top = point.y
      var bottom = top + item.height
      var viewTop = panelFlick.contentY
      var viewBottom = viewTop + panelFlick.height
      var maxY = Math.max(0, panelFlick.contentHeight - panelFlick.height)
      if (top < viewTop + margin) panelFlick.contentY = Math.max(0, top - margin)
      else if (bottom > viewBottom - margin) panelFlick.contentY = Math.min(maxY, bottom + margin - panelFlick.height)
    })
  }

  function scrollCursorIntoView() {
    if (focusSection === "peers" && peerColumn && peerIndex >= 0 && peerIndex < peerColumn.children.length) scrollItemIntoView(peerColumn.children[peerIndex])
    else if (focusSection === "exitNodes" && exitNodeColumn && exitNodeIndex >= 0 && exitNodeIndex < exitNodeColumn.children.length) scrollItemIntoView(exitNodeColumn.children[exitNodeIndex])
    else if (focusSection === "settings" && settingsColumn && settingIndex >= 0 && settingIndex < settingsColumn.children.length) scrollItemIntoView(settingsColumn.children[settingIndex])
    else if (focusSection === "loginServer" && loginServerItem) scrollItemIntoView(loginServerItem)
  }

  function scrollMullvadRegionCursorIntoView() {
    if (mullvadRegionColumn && mullvadRegionIndex >= 0 && mullvadRegionIndex < mullvadRegionColumn.children.length) scrollItemIntoView(mullvadRegionColumn.children[mullvadRegionIndex])
  }

  // The file picker takes over from here, so get the panel out of the way.
  function sendPeerFile(peer) {
    if (!tailscale.canSendFiles(peer)) return
    tailscale.sendFile(peer)
    close()
  }

  function openSelectedPeerCopyMenu() {
    if (!peerColumn || peerIndex < 0 || peerIndex >= peerColumn.children.length) return
    var item = peerColumn.children[peerIndex]
    if (item && item.openCopyMenu) item.openCopyMenu()
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  // Every open starts on the main page with the keyboard cursor parked on the
  // header (Model.enterPage): Settings is a detour, not a place the panel
  // remembers, and the first j/Enter always start from a known row.
  onOpenedChanged: if (opened) {
    var entered = Model.enterPage("main")
    page = entered.page
    focusSection = entered.focusSection
    headerIndex = entered.headerIndex
    settingIndex = entered.settingIndex
    rebindArmed = entered.rebindArmed
    hoverSection = ""
    hoverIndex = -1
    cursorActive = false
    mullvadPickerOpen = false
    if (panelFlick) panelFlick.contentY = 0
    ensureCursor()
    tailscale.refresh()
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  } else {
    rebindArmed = false
  }
  onPageChanged: ensureCursor()
  onHasSettingsPageChanged: if (!hasSettingsPage) closeSettings()
  onHeaderActionCountChanged: ensureCursor()
  onPeerIndexChanged: scrollCursorIntoView()
  onExitNodeIndexChanged: scrollCursorIntoView()
  onSettingIndexChanged: scrollCursorIntoView()
  onMullvadRegionIndexChanged: if (mullvadPickerOpen) scrollMullvadRegionCursorIntoView()
  onShowConnectionsChanged: ensureCursor()
  onShowLoginServerChanged: { rebindArmed = false; ensureCursor() }
  onShowPeersChanged: ensureCursor()
  onShowExitNodesChanged: ensureCursor()
  onShowSettingsChanged: ensureCursor()
  onFilteredMullvadRegionsChanged: ensureCursor()

  Service {
    id: tailscale
    settings: root.settings
  }

  Connections {
    target: tailscale
    function onPeersChanged() { root.ensureCursor() }
    function onAccountsChanged() { root.ensureCursor() }
    function onAccountsAccessDeniedChanged() { root.ensureCursor() }
  }

  IpcHandler {
    target: root.ipcTarget
    function open(): void { root.open() }
    function close(): void { root.close() }
    function show(): void { root.open() }
    function hide(): void { root.close() }
    function toggle(): void { root.toggle() }
    // Opens straight onto the settings page - for keybinds and for driving
    // the panel without a pointer, which is how it gets screenshotted.
    function settings(): void { root.open(); root.openSettings() }
    function refresh(): string { tailscale.refresh(); return "ok" }
    function up(): string { tailscale.loginOrUp(); return "ok" }
    function down(): string { tailscale.down(); return "ok" }
    function toggleTailscale(): string { tailscale.toggleTailscale(); return "ok" }
    function status(): string { return tailscale.statusText }
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    iconComponent: Component {
      Item {
        TailscaleIcon {
          anchors.centerIn: parent
          iconSize: Style.space(11)
          color: root.barIconColor
          badgeColor: root.urgent
          crossed: !tailscale.active && !tailscale.needsLogin
          warning: tailscale.needsLogin
        }
      }
    }
    onPressed: function(buttonCode) {
      if (buttonCode === Qt.RightButton) tailscale.toggleTailscale()
      else if (buttonCode === Qt.MiddleButton) tailscale.refresh()
      else root.toggle()
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(380))
    contentHeight: panel.fittedContentHeight(column.implicitHeight, Style.space(900))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      blocked: root.copyMenuOpen
      onMoveRequested: function(dx, dy) {
        if (!root.cursorActive) { root.cursorActive = true; return }
        root.moveCursor(dx, dy)
      }
      onActivateRequested: if (root.cursorActive) root.activateCursor()
      // Esc: disarm a pending rebind, else leave Settings, else close.
      onCloseRequested: {
        var action = Model.escapeAction(root.page, root.rebindArmed)
        if (action === "disarm") root.rebindArmed = false
        else if (action === "back") root.closeSettings()
        else root.close()
      }
      onTabRequested: function(direction) { root.switchPanel(direction) }
      // j/k/arrows, Enter/Space and Esc arrive as signals from PanelKeyCatcher.
      onTextKey: function(t) {
        if (t === "t" || t === "T") tailscale.toggleTailscale()
        else if (t === "r" || t === "R") tailscale.refresh(true)
        else if (t === "c" || t === "C") root.peerShortcut(function(peer) { tailscale.copyPeerIp(peer) })
        else if (t === "n" || t === "N") root.peerShortcut(function(peer) { tailscale.copyPeerName(peer) })
        else if (t === "d" || t === "D") root.peerShortcut(function(peer) { tailscale.copyPeerDnsName(peer) })
        else if (t === "s" || t === "S") root.peerShortcut(function(peer) { root.sendPeerFile(peer) })
      }

      Flickable {
        id: panelFlick
        anchors.fill: parent
        contentWidth: width
        contentHeight: column.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        flickableDirection: Flickable.VerticalFlick
        interactive: contentHeight > height
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

        Column {
          id: column
          width: panelFlick.width
          spacing: Style.space(12)

          // ---- Main page: hero (icon · name + status · cog + switch) ----
          Item {
            id: header
            visible: root.mainPage
            width: parent.width
            implicitHeight: hero.implicitHeight + (controlServerLine.visible ? controlServerLine.implicitHeight + Style.space(4) : 0)
            // Exposed for the hero's trailingControl, whose `root` resolves to
            // PanelHero (not this Panel) — reach panel state via `header`.
            readonly property bool cogVisible: root.hasSettingsPage
            readonly property bool cogRing: root.cogHasCursor
            readonly property bool toggleRing: root.toggleHasCursor
            function hoverCog(on) { if (on) root.hover("header", root.cogHeaderIndex); else root.unhover("header", root.cogHeaderIndex) }
            function hoverToggle(on) { if (on) root.hover("header", root.toggleHeaderIndex); else root.unhover("header", root.toggleHeaderIndex) }
            function clickCog() { root.selectCursor("header", root.cogHeaderIndex); root.openSettings() }
            function clickToggle() { root.selectCursor("header", root.toggleHeaderIndex); tailscale.toggleTailscale() }

            PanelHero {
              id: hero
              width: parent.width
              title: tailscale.installed ? (tailscale.selfName || "Tailscale") : "Tailscale"
              meta: tailscale.active ? root.heroPhraseText : "Tailscale is disconnected"
              foreground: root.foreground
              fontFamily: root.fontFamily
              iconOpacity: tailscale.active ? 1.0 : 0.5
              // Status only — the switch owns toggling, mouse and keyboard alike.
              iconComponent: Component {
                TailscaleIcon {
                  iconSize: Style.font.display
                  color: root.iconColor
                  badgeColor: root.urgent
                  crossed: !tailscale.active && !tailscale.needsLogin
                  warning: tailscale.needsLogin
                }
              }

              // The header's cursor targets, on the trailing edge of the hero:
              // the cog opens the Settings page; the compact on/off switch
              // toggles. The service already flips `active` optimistically, so
              // the knob throws the instant you click it.
              trailingControl: Component {
                RowLayout {
                  spacing: Style.space(8)

                  Button {
                    id: settingsButton
                    visible: header.cogVisible
                    iconText: "󰒓"
                    tooltipText: "Settings"
                    foreground: hero.foreground
                    fontFamily: hero.fontFamily
                    iconSize: Style.font.subtitle * 1.5
                    horizontalPadding: Style.space(5)
                    verticalPadding: Style.space(2)
                    hasCursor: header.cogRing
                    Layout.alignment: Qt.AlignVCenter
                    onHovered: function(on) { header.hoverCog(on) }
                    onClicked: header.clickCog()
                  }

                  ToggleSwitch {
                    id: powerSwitch
                    visible: tailscale.installed
                    checked: tailscale.active
                    busy: tailscale.busy
                    hasCursor: header.toggleRing
                    foreground: hero.foreground
                    Layout.alignment: Qt.AlignVCenter
                    onHovered: function(on) { header.hoverToggle(on) }
                    onToggled: header.clickToggle()

                    PanelToolTip {
                      visible: powerSwitch.containsMouse
                      text: root.toggleHint
                      fontFamily: hero.fontFamily
                    }
                  }
                }
              }
            }

            // Which control server this profile is bound to, straight from
            // `tailscale debug prefs` on the last refresh.
            Text {
              id: controlServerLine
              visible: tailscale.installed && tailscale.prefsLoaded
              anchors.top: hero.bottom
              anchors.topMargin: Style.space(4)
              anchors.left: parent.left
              anchors.right: parent.right
              textFormat: Text.PlainText
              text: root.controlServerText
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              elide: Text.ElideMiddle
            }
          }

          // ---- Settings page: back · title · control server ----
          Item {
            id: settingsHeader
            visible: root.settingsPage
            width: parent.width
            implicitHeight: Math.max(backButton.implicitHeight, settingsLabels.implicitHeight)

            Button {
              id: backButton
              anchors.left: parent.left
              anchors.verticalCenter: parent.verticalCenter
              iconText: "󰅁"
              tooltipText: "Back"
              foreground: root.foreground
              fontFamily: root.fontFamily
              iconSize: Style.font.subtitle * 1.5
              horizontalPadding: Style.space(5)
              verticalPadding: Style.space(2)
              hasCursor: root.backHasCursor
              onHovered: function(on) { if (on) root.hover("header", 0); else root.unhover("header", 0) }
              onClicked: root.closeSettings()
            }

            Column {
              id: settingsLabels
              anchors.left: backButton.right
              anchors.leftMargin: Style.space(10)
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.space(2)

              Text {
                width: parent.width
                textFormat: Text.PlainText
                text: "Settings"
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.title
                font.bold: true
                elide: Text.ElideRight
              }

              Text {
                width: parent.width
                visible: tailscale.installed && tailscale.prefsLoaded
                textFormat: Text.PlainText
                text: root.controlServerText
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                elide: Text.ElideMiddle
              }
            }
          }

          Text {
            visible: tailscale.actionStatus !== "" || tailscale.lastError !== ""
            width: parent.width
            text: tailscale.actionStatus !== "" ? tailscale.actionStatus : tailscale.lastError
            color: tailscale.lastError !== "" && tailscale.actionStatus === "" ? root.urgent : root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            wrapMode: Text.WordWrap
          }

          // An AuthURL that is not a web URL is never opened; show it to copy.
          Text {
            visible: tailscale.blockedAuthUrl !== ""
            width: parent.width
            textFormat: Text.PlainText
            text: "Login link (not opened): " + tailscale.blockedAuthUrl
            color: root.urgent
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            wrapMode: Text.WrapAnywhere
          }

          CursorSurface {
            visible: !tailscale.installed
            width: parent.width
            implicitHeight: missingText.implicitHeight + Style.spacing.rowPaddingX
            foreground: root.foreground

            Text {
              id: missingText
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              anchors.margins: Style.space(12)
              text: "Tailscale CLI is not installed or not on PATH."
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
              wrapMode: Text.WordWrap
            }
          }

          // Main page sections, top to bottom: connections → exit nodes →
          // machines. Settings-page sections follow the machines block.
          PanelSeparator {
            visible: root.mainPage && root.showConnections
            foreground: root.foreground
          }

          Column {
            visible: root.mainPage && root.showConnections
            width: parent.width
            spacing: Style.space(10)

            PanelSectionHeader {
              text: "CONNECTIONS"
              foreground: root.foreground
              fontFamily: root.fontFamily
            }

            AuthRow {
              visible: tailscale.accountsAccessDenied
              width: parent.width
            }

            Repeater {
              model: tailscale.accounts
              AccountRow {
                required property var modelData
                required property int index
                width: parent.width
                account: modelData
                rowIndex: index
              }
            }
          }

          PanelSeparator {
            visible: root.mainPage && root.showExitNodes
            foreground: root.foreground
          }

          Column {
            visible: root.mainPage && root.showExitNodes
            width: parent.width
            spacing: Style.space(10)

            PanelSectionHeader {
              text: "EXIT NODES"
              foreground: root.foreground
              fontFamily: root.fontFamily
            }

            Text {
              width: parent.width
              textFormat: Text.PlainText
              text: "Using · " + root.exitNodeSummary.label
              color: root.exitNodeSummary.kind === "offline" || root.exitNodeSummary.kind === "unavailable" ? root.urgent : root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              elide: Text.ElideRight
            }

            Column {
              id: exitNodeColumn
              width: parent.width
              spacing: Style.space(6)

              Repeater {
                model: root.exitNodes
                ExitNodeRow {
                  required property var modelData
                  required property int index
                  width: exitNodeColumn.width
                  peer: modelData
                  rowIndex: index
                }
              }

              Column {
                visible: root.mullvadPickerOpen
                width: parent.width
                spacing: Style.space(6)

                TextField {
                  id: mullvadSearch
                  width: parent.width
                  foreground: root.foreground
                  placeholderText: "Search regions"
                  text: root.mullvadQuery
                  onTextChanged: {
                    root.mullvadQuery = text
                    root.mullvadRegionIndex = 0
                  }
                  onAccepted: {
                    root.activateMullvadRegionCursor()
                  }
                  Keys.onPressed: function(event) {
                    if (event.key === Qt.Key_Down || event.text === "j") {
                      root.moveMullvadRegionCursor(1)
                      event.accepted = true
                      return
                    }
                    if (event.key === Qt.Key_Up || event.text === "k") {
                      root.moveMullvadRegionCursor(-1)
                      event.accepted = true
                      return
                    }
                    if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                      root.activateMullvadRegionCursor()
                      event.accepted = true
                      return
                    }
                    if (event.key === Qt.Key_Escape) {
                      root.mullvadPickerOpen = false
                      keyCatcher.forceActiveFocus()
                      event.accepted = true
                    }
                  }
                }

                Text {
                  visible: root.filteredMullvadRegions.length === 0
                  width: parent.width
                  text: "No Mullvad regions found."
                  color: root.dim
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.bodySmall
                  horizontalAlignment: Text.AlignHCenter
                }

                Column {
                  id: mullvadRegionColumn
                  width: parent.width
                  spacing: Style.space(6)

                  Repeater {
                    model: root.filteredMullvadRegions
                    MullvadRegionRow {
                      required property var modelData
                      required property int index
                      width: parent.width
                      peer: modelData
                      rowIndex: index
                    }
                  }
                }
              }
            }
          }

          PanelSeparator {
            visible: root.mainPage && tailscale.installed && tailscale.active
            foreground: root.foreground
          }

          Column {
            visible: root.mainPage && tailscale.installed && tailscale.active
            width: parent.width
            spacing: Style.space(10)

            PanelSectionHeader {
              text: "MACHINES"
              foreground: root.foreground
              fontFamily: root.fontFamily
            }

            Text {
              visible: tailscale.installed && tailscale.active && tailscale.peers.length === 0
              width: parent.width
              text: "No machines found on this tailnet."
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
              horizontalAlignment: Text.AlignHCenter
            }

            Column {
              id: peerColumn
              visible: root.showPeers
              width: parent.width
              spacing: Style.space(6)

              Repeater {
                model: tailscale.peers
                PeerRow {
                  required property var modelData
                  required property int index
                  width: peerColumn.width
                  peer: modelData
                  rowIndex: index
                }
              }
            }
          }

          // Settings page sections, top to bottom: preferences → login server.
          PanelSeparator {
            visible: root.settingsPage && root.showSettings
            foreground: root.foreground
          }

          // Ported from hehh2001/omarchy-tailscale-plus @426b3cc (MIT): the
          // `tailscale set` switches, read back from `tailscale debug prefs`.
          Column {
            visible: root.settingsPage && root.showSettings
            width: parent.width
            spacing: Style.space(10)

            PanelSectionHeader {
              text: "PREFERENCES"
              foreground: root.foreground
              fontFamily: root.fontFamily
            }

            Column {
              id: settingsColumn
              width: parent.width
              spacing: Style.space(6)

              Repeater {
                model: root.preferenceRows
                SettingRow {
                  required property var modelData
                  required property int index
                  width: settingsColumn.width
                  preference: modelData
                  rowIndex: index
                }
              }
            }
          }

          PanelSeparator {
            visible: root.settingsPage && root.showLoginServer
            foreground: root.foreground
          }

          Column {
            visible: root.settingsPage && root.showLoginServer
            width: parent.width
            spacing: Style.space(10)

            PanelSectionHeader {
              text: "LOGIN SERVER"
              foreground: root.foreground
              fontFamily: root.fontFamily
            }

            LoginServerRow {
              id: loginServerItem
              width: parent.width
            }
          }
        }
      }
    }
  }

  Timer {
    id: phraseTimer
    interval: 2800
    running: root.opened && tailscale.active
    repeat: true
    onTriggered: phraseSwap.restart()
  }

  SequentialAnimation {
    id: phraseSwap
    PropertyAnimation {
      target: hero; property: "metaOpacity"
      to: 0.0; duration: 180; easing.type: Easing.OutQuad
    }
    ScriptAction {
      script: root.phraseIndex = (root.phraseIndex + 1) % root.activePhrases.length
    }
    PropertyAnimation {
      target: hero; property: "metaOpacity"
      to: 1.0; duration: 260; easing.type: Easing.InQuad
    }
  }

  // Ported from hehh2001/omarchy-tailscale-plus @426b3cc (MIT): one row per
  // `tailscale set` switch, highlighted when on and dimmed when off with the
  // same fills the exit-node rows use.
  component SettingRow: CursorSurface {
    id: settingRow
    property var preference: null
    property int rowIndex: 0
    readonly property bool enabledSetting: preference && preference.value === true
    readonly property bool changing: preference && tailscale.changingSetting === String(preference.key || "")

    hasCursor: root.rowHasCursor("settings", rowIndex)
    current: enabledSetting || changing
    foreground: root.foreground
    fill: root.hoverFill
    currentFill: root.selectedFill
    implicitHeight: settingContent.implicitHeight + Style.spacing.rowPaddingX

    MouseArea {
      anchors.fill: parent
      hoverEnabled: true
      enabled: !tailscale.busy
      cursorShape: Qt.PointingHandCursor
      onEntered: root.hover("settings", settingRow.rowIndex)
      onExited: root.unhover("settings", settingRow.rowIndex)
      onClicked: settingRow.flip()
    }

    RowLayout {
      id: settingContent
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      anchors.leftMargin: Style.space(10)
      anchors.rightMargin: Style.space(8)
      spacing: Style.space(8)

      ColumnLayout {
        Layout.fillWidth: true
        spacing: Style.space(1)

        Text {
          Layout.fillWidth: true
          textFormat: Text.PlainText
          text: settingRow.preference ? String(settingRow.preference.label || "") : ""
          color: settingRow.enabledSetting ? root.foreground : root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
          font.bold: settingRow.enabledSetting
          elide: Text.ElideRight
        }

        Text {
          Layout.fillWidth: true
          textFormat: Text.PlainText
          text: settingRow.preference ? String(settingRow.preference.detail || "") : ""
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          elide: Text.ElideRight
        }
      }

      ToggleSwitch {
        checked: settingRow.enabledSetting
        busy: tailscale.busy
        hasCursor: settingRow.hasCursor
        foreground: root.foreground
        Layout.alignment: Qt.AlignVCenter
        onHovered: function(on) { if (on) root.hover("settings", settingRow.rowIndex); else root.unhover("settings", settingRow.rowIndex) }
        onToggled: settingRow.flip()
      }
    }

    // A click selects the row for the keyboard, then flips the switch.
    function flip() {
      root.selectCursor("settings", rowIndex)
      if (preference) tailscale.togglePreference(preference.key)
    }
  }

  // Log in to the configured control server. Because that logs out of the
  // current one and deletes its profile, the row arms on the first activation
  // and fires on the second; moving the cursor or Esc disarms it.
  component LoginServerRow: CursorSurface {
    id: loginServerRow
    readonly property bool usable: tailscale.loginServerCheck.ok && !tailscale.loginBusy

    hasCursor: root.rowHasCursor("loginServer", 0)
    current: root.rebindArmed
    foreground: root.foreground
    fill: root.hoverFill
    currentFill: root.selectedFill
    implicitHeight: loginServerContent.implicitHeight + Style.spacing.rowPaddingX

    MouseArea {
      anchors.fill: parent
      hoverEnabled: true
      enabled: loginServerRow.usable
      cursorShape: loginServerRow.usable ? Qt.PointingHandCursor : Qt.ArrowCursor
      onEntered: root.hover("loginServer", 0)
      onExited: root.unhover("loginServer", 0)
      onClicked: { root.selectCursor("loginServer", 0); root.activateRebind() }
    }

    RowLayout {
      id: loginServerContent
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      anchors.leftMargin: Style.space(10)
      anchors.rightMargin: Style.space(10)
      spacing: Style.space(8)

      Text {
        text: "󰍂"
        color: tailscale.loginServerCheck.ok ? (root.rebindArmed ? root.urgent : root.foreground) : root.urgent
        font.family: root.fontFamily
        font.pixelSize: Style.font.heading
        Layout.alignment: Qt.AlignVCenter
      }

      ColumnLayout {
        Layout.fillWidth: true
        spacing: Style.space(1)

        Text {
          Layout.fillWidth: true
          textFormat: Text.PlainText
          text: root.rebindTitle
          color: tailscale.loginServerCheck.ok ? root.foreground : root.urgent
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
          font.bold: root.rebindArmed
          elide: Text.ElideMiddle
        }

        Text {
          Layout.fillWidth: true
          textFormat: Text.PlainText
          text: root.rebindDetail
          color: root.rebindArmed ? root.urgent : root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          wrapMode: Text.WordWrap
        }
      }
    }
  }

  component AuthRow: CursorSurface {
    id: authRow

    hasCursor: root.rowHasCursor("auth", 0)
    foreground: root.foreground

    implicitHeight: row.implicitHeight + Style.spacing.rowPaddingX

    MouseArea {
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: tailscale.busy ? Qt.ArrowCursor : Qt.PointingHandCursor
      enabled: !tailscale.busy
      onEntered: root.hover("auth", 0)
      onExited: root.unhover("auth", 0)
      onClicked: { root.selectCursor("auth", 0); tailscale.authorizeTailscaleOperator() }
    }

    RowLayout {
      id: row
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      anchors.leftMargin: Style.space(10)
      anchors.rightMargin: Style.space(10)
      spacing: Style.space(8)

      Text {
        text: "󰒃"
        color: root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.heading
        Layout.alignment: Qt.AlignVCenter
      }

      ColumnLayout {
        Layout.fillWidth: true
        spacing: Style.space(1)

        Text {
          Layout.fillWidth: true
          text: "Authorize Tailscale operator"
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
          elide: Text.ElideRight
        }

        Text {
          Layout.fillWidth: true
          text: "Allow this user to operate this Tailscale profile"
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          elide: Text.ElideRight
        }
      }

    }
  }

  component AccountRow: CursorSurface {
    id: accountRow
    property var account: null
    property int rowIndex: 0
    readonly property bool selectedAccount: account && account.selected === true
    readonly property bool switchingAccount: account && tailscale.switchingAccountId === String(account.id || "")
    readonly property string accountText: account ? tailscale.accountLabel(account) : "Account"

    hasCursor: root.rowHasCursor("accounts", rowIndex)
    current: selectedAccount
    foreground: root.foreground
    fill: root.hoverFill
    currentFill: root.selectedFill

    implicitHeight: accountInner.implicitHeight + Style.spacing.xl

    Row {
      id: accountInner
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      anchors.leftMargin: Style.space(6)
      anchors.rightMargin: Style.space(6)
      spacing: Style.space(8)

      Text {
        id: accountGlyph
        text: ""
        color: accountRow.selectedAccount || accountRow.switchingAccount ? root.foreground : root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
        width: Style.space(22)
        horizontalAlignment: Text.AlignHCenter
        anchors.verticalCenter: parent.verticalCenter
        opacity: accountRow.switchingAccount ? 0.45 : 1.0

        SequentialAnimation on opacity {
          running: accountRow.switchingAccount
          NumberAnimation { to: 1.0; duration: 420; easing.type: Easing.InOutQuad }
          NumberAnimation { to: 0.45; duration: 420; easing.type: Easing.InOutQuad }
          loops: Animation.Infinite
        }
      }

      Text {
        text: accountRow.accountText
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
        font.bold: accountRow.selectedAccount
        elide: Text.ElideRight
        width: parent.width - Style.space(22) - Style.space(8)
        anchors.verticalCenter: parent.verticalCenter
      }
    }

    MouseArea {
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onEntered: root.hover("accounts", accountRow.rowIndex)
      onExited: root.unhover("accounts", accountRow.rowIndex)
      onClicked: {
        root.selectCursor("accounts", accountRow.rowIndex)
        if (accountRow.account) tailscale.switchAccount(accountRow.account.id)
      }
    }
  }

  component PeerRow: CursorSurface {
    id: peerRow
    property var peer: null
    property int rowIndex: 0
    readonly property bool peerOnline: peer && peer.Online === true
    readonly property string peerName: peer ? String(peer.DisplayName || peer.HostName || "Unknown") : "Unknown"
    readonly property string peerIp: peer && peer.TailscaleIPs && peer.TailscaleIPs.length > 0 ? String(peer.TailscaleIPs[0]) : ""
    readonly property string peerIpv6: {
      if (!peer || !peer.TailscaleIPv6 || peer.TailscaleIPv6.length === 0) return ""
      return String(peer.TailscaleIPv6[0] || "")
    }
    readonly property string peerDns: peer ? String(peer.DNSName || "") : ""
    readonly property var copyOptions: {
      var options = []
      if (peerName !== "") options.push({ kind: "name", label: peerName })
      if (peerDns !== "") options.push({ kind: "dns", label: peerDns })
      if (peerIpv6 !== "") options.push({ kind: "ipv6", label: peerIpv6 })
      if (peerIp !== "") options.push({ kind: "ip", label: peerIp })
      return options
    }
    property int copyIndex: 0

    hasCursor: root.rowHasCursor("peers", rowIndex)
    foreground: root.foreground

    implicitHeight: Math.max(peerContent.implicitHeight, copyButton.implicitHeight) + Style.spacing.rowPaddingX

    function clampCopyIndex() {
      copyIndex = Math.max(0, Math.min(copyIndex, copyOptions.length - 1))
    }

    function openCopyMenu() {
      if (copyOptions.length === 0) return
      clampCopyIndex()
      copyPopup.open()
    }

    function moveCopyCursor(delta) {
      if (copyOptions.length === 0) return
      copyIndex = Math.max(0, Math.min(copyOptions.length - 1, copyIndex + delta))
    }

    function copyOption(kind) {
      if (kind === "name") tailscale.copyPeerName(peer)
      else if (kind === "dns") tailscale.copyPeerDnsName(peer)
      else if (kind === "ipv6") tailscale.copyToClipboard(peerIpv6, peerName + " IPv6")
      else if (kind === "ip") tailscale.copyPeerIp(peer)
      copyPopup.close()
    }

    function copyCurrentOption() {
      clampCopyIndex()
      if (copyOptions.length === 0) return
      copyOption(copyOptions[copyIndex].kind)
    }

    MouseArea {
      anchors.fill: parent
      acceptedButtons: Qt.LeftButton
      hoverEnabled: true
      cursorShape: Qt.ArrowCursor
      onContainsMouseChanged: if (containsMouse) root.hover("peers", peerRow.rowIndex); else root.unhover("peers", peerRow.rowIndex)
      onClicked: root.selectCursor("peers", peerRow.rowIndex)
    }

    RowLayout {
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      anchors.leftMargin: Style.space(10)
      anchors.rightMargin: Style.space(8)
      spacing: Style.space(8)

      Rectangle {
        implicitWidth: Style.space(7)
        implicitHeight: implicitWidth
        Layout.preferredWidth: implicitWidth
        Layout.preferredHeight: implicitHeight
        radius: width / 2
        color: peerRow.peerOnline ? root.online : root.dim
        Layout.alignment: Qt.AlignVCenter
      }

      Text {
        text: tailscale.osIcon(peer ? peer.OS : "")
        color: peerRow.peerOnline ? root.foreground : root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.icon
        Layout.alignment: Qt.AlignVCenter
      }

      ColumnLayout {
        id: peerContent
        Layout.fillWidth: true
        spacing: Style.space(1)

        Text {
          Layout.fillWidth: true
          text: peerRow.peerName
          color: peerRow.peerOnline ? root.foreground : root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
          elide: Text.ElideRight
        }

        Text {
          Layout.fillWidth: true
          text: {
            var parts = []
            if (peerRow.peerIp !== "") parts.push(peerRow.peerIp)
            if (peerRow.peerDns !== "") parts.push(peerRow.peerDns)
            return parts.join(" · ")
          }
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          elide: Text.ElideRight
        }
      }

      PanelActionButton {
        id: sendButton
        visible: tailscale.canSendFiles(peerRow.peer)
        iconText: "󰒊"
        tooltipText: "Send files"
        foreground: root.foreground
        fontFamily: root.fontFamily
        Layout.alignment: Qt.AlignVCenter
        onClicked: { root.selectCursor("peers", peerRow.rowIndex); root.sendPeerFile(peerRow.peer) }
      }

      PanelActionButton {
        id: copyButton
        iconText: "󰆏"
        foreground: root.foreground
        fontFamily: root.fontFamily
        enabled: peerRow.peerIp !== "" || peerRow.peerName !== "" || peerRow.peerDns !== "" || peerRow.peerIpv6 !== ""
        Layout.alignment: Qt.AlignVCenter
        onClicked: { root.selectCursor("peers", peerRow.rowIndex); peerRow.openCopyMenu() }
      }

      Popup {
        id: copyPopup
        x: copyButton.x + copyButton.width - width
        y: copyButton.y + copyButton.height + Style.space(4)
        width: Style.space(280)
        padding: 0
        modal: false
        focus: true
        closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
        function handleKey(event) {
          if (event.key === Qt.Key_Escape) {
            close()
            event.accepted = true
            return
          }
          if (event.key === Qt.Key_Down || event.text === "j") {
            peerRow.moveCopyCursor(1)
            event.accepted = true
            return
          }
          if (event.key === Qt.Key_Up || event.text === "k") {
            peerRow.moveCopyCursor(-1)
            event.accepted = true
            return
          }
          if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space) {
            peerRow.copyCurrentOption()
            event.accepted = true
          }
        }
        onOpenedChanged: {
          root.copyMenuOpen = opened
          if (opened) {
            peerRow.clampCopyIndex()
            Qt.callLater(function() { copyPopupContent.forceActiveFocus() })
          } else if (root.opened) {
            Qt.callLater(function() { keyCatcher.forceActiveFocus() })
          }
        }
        background: BorderSurface {
          color: Color.background
          borderSpec: Border.flat(root.dim, 1)
          radius: Style.cornerRadius
        }

        contentItem: Column {
          id: copyPopupContent
          width: parent.width
          focus: true
          Keys.priority: Keys.BeforeItem
          Keys.onPressed: function(event) { copyPopup.handleKey(event) }

          Repeater {
            model: peerRow.copyOptions
            CopyChoice {
              required property var modelData
              required property int index
              width: parent.width
              label: String(modelData.label || "")
              selected: peerRow.copyIndex === index
              onHovered: peerRow.copyIndex = index
              onChosen: peerRow.copyOption(String(modelData.kind || ""))
            }
          }
        }
      }
    }
  }

  component CopyChoice: CursorSurface {
    id: copyChoice
    signal chosen()
    signal hovered()
    property string label: ""
    property bool selected: false

    visible: enabled
    foreground: root.foreground
    hasCursor: selected
    implicitHeight: Style.space(48)
    radius: 0

    MouseArea {
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onEntered: copyChoice.hovered()
      onClicked: copyChoice.chosen()
    }

    RowLayout {
      anchors.fill: parent
      anchors.leftMargin: Style.space(12)
      anchors.rightMargin: Style.space(12)
      spacing: Style.space(10)

      Text {
        Layout.fillWidth: true
        text: copyChoice.label
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
        elide: Text.ElideRight
      }

      Text {
        text: "󰆏"
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.icon
        Layout.alignment: Qt.AlignVCenter
      }
    }
  }

  component ExitNodeRow: CursorSurface {
    id: exitNodeRow
    property var peer: null
    property int rowIndex: 0
    readonly property bool addMullvad: peer && peer.AddMullvad === true
    readonly property bool activeExitNode: peer && peer.ExitNode === true
    readonly property bool settingExitNode: peer && tailscale.settingExitNodeId === String(peer.id || "")
    // Ported from hehh2001/omarchy-tailscale-plus @426b3cc (MIT): a selected
    // node that dropped offline stays listed and says so.
    readonly property string peerName: peer ? String(peer.DisplayName || peer.HostName || "Unknown") + (peer.ExitNode === true && peer.Online !== true ? " (offline)" : "") : "Unknown"
    readonly property string actionTooltip: addMullvad ? "" : (activeExitNode ? "Disconnect" : "Connect")

    hasCursor: root.rowHasCursor("exitNodes", rowIndex)
    current: activeExitNode || settingExitNode || (addMullvad && root.mullvadPickerOpen)
    foreground: root.foreground
    fill: root.hoverFill
    currentFill: root.selectedFill

    implicitHeight: exitNodeInner.implicitHeight + Style.spacing.xl

    Row {
      id: exitNodeInner
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      anchors.leftMargin: Style.space(6)
      anchors.rightMargin: Style.space(6)
      spacing: Style.space(8)

      Text {
        id: exitNodeGlyph
        text: exitNodeRow.addMullvad ? "+" : (peer && peer.Mullvad === true ? "󰖂" : "󱇢")
        color: exitNodeRow.activeExitNode || exitNodeRow.settingExitNode || exitNodeRow.addMullvad ? root.foreground : root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
        width: Style.space(22)
        horizontalAlignment: Text.AlignHCenter
        anchors.verticalCenter: parent.verticalCenter

        NumberAnimation on rotation {
          running: exitNodeRow.settingExitNode
          from: 0
          to: 360
          duration: 900
          loops: Animation.Infinite
        }

        onRotationChanged: if (!exitNodeRow.settingExitNode && rotation !== 0) rotation = 0
      }

      Text {
        text: exitNodeRow.peerName
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
        font.bold: exitNodeRow.activeExitNode
        elide: Text.ElideRight
        width: parent.width - Style.space(22) - Style.space(8)
        anchors.verticalCenter: parent.verticalCenter
      }
    }

    MouseArea {
      id: exitNodeMouse
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onEntered: root.hover("exitNodes", exitNodeRow.rowIndex)
      onExited: root.unhover("exitNodes", exitNodeRow.rowIndex)
      onClicked: { root.selectCursor("exitNodes", exitNodeRow.rowIndex); root.chooseExitNode(exitNodeRow.peer) }
    }

    PanelToolTip {
      visible: exitNodeRow.actionTooltip !== "" && exitNodeMouse.containsMouse
      text: exitNodeRow.actionTooltip
      fontFamily: root.fontFamily
    }
  }

  component MullvadRegionRow: CursorSurface {
    id: regionRow

    property var peer: null
    property int rowIndex: 0
    readonly property string regionName: root.mullvadRegionTitle(peer)
    readonly property string regionDetail: root.mullvadRegionSubtitle(peer)
    readonly property bool activeExitNode: peer && peer.ExitNode === true
    readonly property bool settingExitNode: peer && tailscale.settingExitNodeId === String(peer.id || "")
    readonly property bool selectedRegion: root.mullvadPickerOpen && root.mullvadRegionIndex === rowIndex
    readonly property string actionTooltip: activeExitNode ? "Disconnect" : "Connect"

    hasCursor: root.hoverSection === "mullvad" && root.hoverIndex === rowIndex
    foreground: root.foreground
    fill: root.hoverFill
    currentFill: root.selectedFill
    current: activeExitNode || settingExitNode || selectedRegion
    implicitHeight: row.implicitHeight + Style.spacing.lg

    Row {
      id: row
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      anchors.leftMargin: Style.space(6)
      anchors.rightMargin: Style.space(6)
      spacing: Style.space(8)

      Text {
        text: "󰖂"
        color: regionRow.current ? root.foreground : root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
        width: Style.space(22)
        horizontalAlignment: Text.AlignHCenter
        anchors.verticalCenter: parent.verticalCenter
      }

      Column {
        width: parent.width - Style.space(30)
        anchors.verticalCenter: parent.verticalCenter
        spacing: Style.space(1)

        Text {
          width: parent.width
          text: regionRow.regionName
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
          font.bold: regionRow.activeExitNode
          elide: Text.ElideRight
        }

        Text {
          width: parent.width
          text: regionRow.regionDetail
          visible: text !== ""
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          elide: Text.ElideRight
        }
      }
    }

    MouseArea {
      id: regionMouse
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onEntered: root.hoverMullvadRegion(regionRow.rowIndex)
      onExited: root.unhover("mullvad", regionRow.rowIndex)
      onClicked: { root.mullvadRegionIndex = regionRow.rowIndex; root.chooseExitNode(regionRow.peer) }
    }

    PanelToolTip {
      visible: regionMouse.containsMouse
      text: regionRow.actionTooltip
      fontFamily: root.fontFamily
    }
  }
}
