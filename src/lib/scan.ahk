; ==========================================================================
;  Шаг 2. Подбор стратегии: каждая стратегия Запрета × режим Game Filter → сетевые проверки.
;  Умный режим: только Game Filter TCP, остановка после 3 кандидатов. Полный: всё × (выкл, TCP).
; ==========================================================================

global ScanResults := []
global ScanStop := false
global ExcludeParts := StrSplit(Cfg("scan", "exclude", " - BSGO,phasmo"), ",")
global SMART_CANDIDATES := 3
global ChromiumIgnored := false

; ---------- список стратегий ----------
StrategyFiles() {
    list := ""
    if (ZapretRoot = "")
        return []
    loop files, ZapretRoot "\*.bat" {
        if (SubStr(A_LoopFileName, 1, 7) = "service")
            continue
        skip := false
        for part in ExcludeParts
            if (Trim(part) != "" && InStr(A_LoopFileName, Trim(part)))
                skip := true
        if skip
            continue
        txt := FileRead(A_LoopFileFullPath)
        if (InStr(txt, "winws.exe") && InStr(txt, "--wf-tcp="))
            list .= A_LoopFileName "`n"
    }
    return list = "" ? [] : StrSplit(Sort(RTrim(list, "`n"), "CLogical"), "`n")
}

; выбранные стратегии; пусто в tester.ini = все
SelectedNames() {
    sel := Map()
    for nm in StrSplit(Cfg("scan", "selected", ""), "|")
        if (nm != "")
            sel[nm] := true
    return sel
}

FilesToScan() {
    all := StrategyFiles(), sel := SelectedNames()
    if !sel.Count
        return all
    out := []
    for f in all
        if sel.Has(f)
            out.Push(f)
    return out.Length ? out : all
}

SelectionText() {
    total := StrategyFiles().Length, chosen := FilesToScan().Length
    return chosen = total ? Format(T("sel_all"), total) : Format(T("sel_some"), chosen, total)
}

PickStrategies(ownerHwnd, doneFn) {
    sel := SelectedNames()
    dlg := Gui("+Owner" ownerHwnd " +AlwaysOnTop", T("pick_strategies"))
    dlg.SetFont("s9", "Segoe UI")
    lv := dlg.AddListView("w440 h420 Checked -Hdr", ["name"])
    for f in StrategyFiles()
        lv.Add((!sel.Count || sel.Has(f)) ? "Check" : "", f)
    lv.ModifyCol(1, 410)
    dlg.AddButton("xm w100", T("all")).OnEvent("Click", (*) => lv.Modify(0, "Check"))
    dlg.AddButton("x+6 w100", T("none")).OnEvent("Click", (*) => lv.Modify(0, "-Check"))
    dlg.AddButton("x+6 w120 Default", T("done")).OnEvent("Click", SaveSelection.Bind(lv, dlg, doneFn))
    dlg.Show()
}

SaveSelection(lv, dlg, doneFn, *) {
    names := "", n := 0, row := 0
    while (row := lv.GetNext(row, "C")) {
        names .= lv.GetText(row) "|"
        n++
    }
    if !n {
        MsgBox(T("pick_at_least_one"), , "Icon! Owner" dlg.Hwnd)
        return
    }
    CfgSet("scan", "selected", n = lv.GetCount() ? "" : RTrim(names, "|"))
    dlg.Destroy()
    doneFn()
}

; ---------- разбор .bat: обрабатывает ли стратегия игровой порт ----------
PortInList(list, port) {
    for part in StrSplit(list, ",") {
        part := Trim(part)
        if RegExMatch(part, "^(\d+)-(\d+)$", &m) {
            if (port >= Integer(m[1]) && port <= Integer(m[2]))
                return true
        } else if (IsInteger(part) && Integer(part) = port)
            return true
    }
    return false
}

; порт должен быть и в перехвате (--wf-tcp), и в каком-то правиле (--filter-tcp)
CoversPort(batText, gfTcp, port) {
    text := StrReplace(batText, "%GameFilterTCP%", gfTcp)
    wf := false, rule := false, pos := 1
    while (pos := RegExMatch(text, "--wf-tcp=([^\s\^]+)", &m, pos)) {
        wf := wf || PortInList(m[1], port)
        pos += m.Len
    }
    pos := 1
    while (pos := RegExMatch(text, "--filter-tcp=([^\s\^]+)", &m, pos)) {
        rule := rule || PortInList(m[1], port)
        pos += m.Len
    }
    return wf && rule
}

CoversAllPorts(batText, mode, gf) {
    gfTcp := (mode = "tcp" || mode = "all") ? gf.tcp : "12"      ; при выключенном Game Filter Запрет подставляет порт 12
    for port in GamePorts
        if !CoversPort(batText, gfTcp, port)
            return false
    return true
}

; ---------- классификация ----------
; A — кандидат для игры, B — только лаунчер, E — нестабильно, C — не проходит, D — не запустилась, "-" — без обхода
ClassifyResult(fname, mode, r, batText, gf) {
    covers := (batText != "") && CoversAllPorts(batText, mode, gf)
    item := {name: fname, mode: mode, covers: covers, cls: "D", reason: "", time: 0.0, ip: ""
        , curl: T("did_not_start"), node: "—", edge: "—", ports: "—", portsOk: false, allOk: false, game: ""}
    if !IsObject(r)
        return item
    portsOk := PortsAllOk(r.ports)
    ; судья — движок самого лаунчера (если лаунчер Electron), иначе curl; см. LauncherLevel
    lvl := LauncherLevel(r)
    if (batText = "")
        cls := "-"
    else if (lvl = "ok") {
        cls := (covers && portsOk) ? "A" : "B"
        if (IsObject(r.main) && r.main.maxTime > 5)
            item.reason := T("slow")
        else if CurlDiffers(r)
            item.reason := T("r_curl_differs")
    } else if (lvl = "chromium") {
        cls := "C", item.reason := T("r_chromium")
    } else if (lvl = "partial") {
        cls := "E", item.reason := T("r_unstable")
    } else if (lvl = "unknown") {
        cls := "C", item.reason := T("r_unknown")
    } else
        cls := "C"
    item.cls := cls
    item.curl := CurlReliable ? AttemptsText(r.curl) : T("not_checked")
    item.node := IsObject(r.node) ? AttemptsText(r.node) : T("not_electron_short")
    item.edge := EdgeText(r.edge)
    item.ports := PortsText(r.ports)
    item.portsOk := portsOk
    item.time := IsObject(r.main) ? r.main.maxTime : 0.0
    item.ip := r.ip
    item.allOk := lvl = "ok"
    return item
}

ClassText(cls) {
    switch cls {
        case "A": return T("c_candidate")
        case "B": return T("c_launcher_only")
        case "E": return T("c_unstable")
        case "C": return T("c_fail")
        case "D": return T("c_not_started")
        default: return T("c_baseline")
    }
}

; ---------- сканирование ----------
; mode: "smart" | "full"; progressFn(text); rowFn(item)
; refreshFn() — перерисовать все строки (если оценки пересчитаны задним числом)
RunScan(scanMode, progressFn, rowFn, refreshFn) {
    global ScanResults, ScanStop, EdgeReliable, CurlReliable, NodeReliable, ChromiumIgnored
    ScanResults := [], ScanStop := false, ChromiumIgnored := false
    started := A_TickCount
    files := FilesToScan()
    modes := scanMode = "smart" ? ["tcp"] : ["disabled", "tcp"]
    gf := ReadGfSettings()

    progressFn(T("p_prepare"))
    ResolveBigUrl()
    EdgeReliable := EdgeSelfTest()
    CurlReliable := CurlSelfTest()
    NodeReliable := LauncherEngineSelfTest()
    if IsElectron
        WriteNodeScript()

    progressFn(T("p_stop_zapret"))
    SaveZapretState()
    OnExit(EmergencyRestore)
    StopZapret()

    progressFn(T("p_without"))
    baseItem := ClassifyResult(T("row_baseline"), "—", RunNetChecks(), "", gf)
    ScanResults.Push(baseItem), rowFn(baseItem)

    total := files.Length * modes.Length, n := 0, found := 0, stoppedEarly := false
    chromFail := 0, chromOk := 0
    for fname in files {
        batText := FileRead(ZapretRoot "\" fname)
        for mode in modes {
            if ScanStop {
                stoppedEarly := true
                break 2
            }
            n++
            progressFn(Format(T("p_strategy"), n, total, fname, ModeLabel(mode), (A_TickCount - started) / 60000))
            KillWinws()
            WriteGf(mode, gf)
            r := StartStrategy(fname) ? RunNetChecks() : ""
            item := ClassifyResult(fname, mode, r, batText, gf)
            item.raw := r, item.batText := batText
            ScanResults.Push(item), rowFn(item)
            if (item.cls = "A")
                found++

            ; лаунчер проходит, а Chromium — ни разу: скорее всего, изменился сайт, а не сеть.
            ; Тогда проверку Chromium не учитываем и пересчитываем оценки задним числом.
            if IsObject(r) {
                if (r.edge = 0 && LauncherLevel(r) = "chromium")
                    chromFail++
                else if (r.edge = 1)
                    chromOk++
            }
            if (EdgeReliable && chromFail >= 3 && chromOk = 0) {
                EdgeReliable := false, ChromiumIgnored := true
                found := 0
                for i, old in ScanResults {
                    if (i = 1 || !IsObject(old.raw))
                        continue
                    old.raw.edge := -2
                    fresh := ClassifyResult(old.name, old.mode, old.raw, old.batText, gf)
                    fresh.raw := old.raw, fresh.batText := old.batText
                    ScanResults[i] := fresh
                    if (fresh.cls = "A")
                        found++
                }
                refreshFn()
            }
            if (scanMode = "smart" && found >= SMART_CANDIDATES)
                break 2
        }
    }

    progressFn(T("p_restore"))
    KillWinws()
    RestoreZapretState()
    OnExit(EmergencyRestore, 0)
    return {items: ScanResults, mode: scanMode, elapsed: A_TickCount - started, stopped: stoppedEarly, found: found
        , total: total, done: n}
}

; кандидаты для проверки в игре: сначала с выключенным Game Filter (узкий охват), затем быстрее
RankedCandidates() {
    list := ""
    for i, item in ScanResults
        if (item.cls = "A")
            list .= (item.mode = "disabled" ? 0 : 1) Format("{:08}", Round(item.time * 1000)) "`t" i "`n"
    out := []
    if (list != "")
        for row in StrSplit(Sort(RTrim(list, "`n")), "`n")
            out.Push(ScanResults[Integer(StrSplit(row, "`t")[2])])
    return out
}

ScanReportText(scan) {
    nl := "`r`n"
    out := T("scan_title") " — " FormatTime(, "yyyy-MM-dd HH:mm") nl
    out .= T("zapret") ": " ZapretRoot nl
    out .= T("scan_mode") ": " (scan.mode = "smart" ? T("mode_smart") : T("mode_full"))
        . ",  " Format(T("scan_progress"), scan.done, scan.total) ",  " Format(T("minutes"), scan.elapsed / 60000)
        . (scan.stopped ? ",  " T("stopped_early") : "") nl
    out .= T("game_ports") ": " JoinArr(GamePorts, ", ") ",  " T("installer") ": " BigUrl nl
    if ChromiumIgnored
        out .= T("warn") ": " T("chromium_ignored") nl
    else if !EdgeReliable
        out .= T("warn") ": " T("edge_unavailable") nl
    for noteLine in StrSplit(RTrim(ListsNote, "`r`n"), "`n", "`r")
        if (noteLine != "")
            out .= T("warn") ": " noteLine nl
    if !CurlReliable
        out .= T("warn") ": " T("curl_unavailable") nl
    if (IsElectron && !NodeReliable)
        out .= T("warn") ": " T("node_unavailable") nl
    b := scan.items[1]
    out .= nl "== " T("without_bypass") " ==" nl
    out .= "  curl: " b.curl ",  " T("launcher_engine") ": " b.node ",  Chromium: " b.edge ",  " T("game_tcp") ": " b.ports nl
    if !b.portsOk
        out .= T("warn") ": " Format(T("ports_closed_baseline"), JoinArr(GamePorts, ", ")) nl
    for cls in ["A", "B", "E", "C", "D"] {
        out .= nl "== " ClassText(cls) " ==" nl
        cnt := 0
        for item in scan.items {
            if (item.cls != cls)
                continue
            cnt++
            out .= Format("  {:-46} GF={:-5} curl: {:-16} {}: {:-16} Chromium: {:-8} {}: {}"
                , item.name, ModeLabel(item.mode), item.curl, T("launcher_short"), item.node, item.edge, T("game_tcp"), item.ports)
                . (item.reason != "" ? "  ← " item.reason : "") nl
        }
        if !cnt
            out .= "  (" T("none_found") ")" nl
    }
    cands := RankedCandidates()
    out .= nl "== " T("recommendation") " ==" nl
    if cands.Length {
        out .= "  " cands[1].name "  GF: " ModeLabel(cands[1].mode) nl "  " T("rec_confirm") nl
    } else {
        anyB := false
        for item in scan.items
            anyB := anyB || item.cls = "B"
        out .= "  " (anyB ? Format(T("rec_only_launcher"), JoinArr(GamePorts)) : T("rec_none")) nl
    }
    return out
}
