#Requires AutoHotkey v2.0 64-bit
#SingleInstance Force

; ==========================================================================
;  BSGO Connection Doctor — самостоятельный тестер подключения к BSGO.
;  Шаг 1: диагностика (этап A). Шаги 2–3 — подбор стратегии и проверка в игре (этапы B–C).
; ==========================================================================

; права администратора нужны, чтобы останавливать и запускать Запрет
if !A_IsAdmin {
    try Run(A_IsCompiled ? '*RunAs "' A_ScriptFullPath '"' : '*RunAs "' A_AhkPath '" "' A_ScriptFullPath '"')
    ExitApp()
}

#Include "%A_ScriptDir%\lib\i18n.ahk"
#Include "%A_ScriptDir%\lib\config.ahk"
#Include "%A_ScriptDir%\lib\net.ahk"
#Include "%A_ScriptDir%\lib\zapret.ahk"
#Include "%A_ScriptDir%\lib\diag.ahk"
#Include "%A_ScriptDir%\lib\scan.ahk"
#Include "%A_ScriptDir%\lib\ingame.ahk"

global APP_VERSION := "0.6"
global ReportsDir := A_ScriptDir "\reports"
global Busy := false

LoadGame()
LoadZapret()

; ---------- окно ----------
global MainGui := Gui("+Resize +MinSize760x560", T("app_title") " " APP_VERSION)
MainGui.SetFont("s9", "Segoe UI")
MainGui.AddText("xm w620", T("intro"))
MainGui.AddButton("x+10 yp w100 h24", T("lang_btn")).OnEvent("Click", SwitchLang)

MainGui.AddGroupBox("xm w740 h70", T("game_group"))
global GameText := MainGui.AddText("xp+10 yp+20 w560 h40", "")
MainGui.AddButton("x+8 yp w150 h26", T("btn_game_folder")).OnEvent("Click", GameFolderClick)

MainGui.AddGroupBox("xm y+14 w740 h70", T("zapret_group"))
global ZapText := MainGui.AddText("xp+10 yp+20 w560 h40", "")
MainGui.AddButton("x+8 yp w150 h26", T("btn_zapret_folder")).OnEvent("Click", ZapretFolderClick)

global BtnDiag := MainGui.AddButton("xm y+18 w240 h34", T("btn_diag"))
BtnDiag.OnEvent("Click", DiagClick)
global BtnPick := MainGui.AddButton("x+8 w240 h34", T("btn_pick"))
BtnPick.OnEvent("Click", ScanClick)
global BtnInGame := MainGui.AddButton("x+8 w244 h34", T("btn_ingame"))
BtnInGame.OnEvent("Click", InGameClick)
global StatusText := MainGui.AddText("xm y+8 w740 h18", T("coming_soon"))
global ResLV := MainGui.AddListView("xm w740 h200", [T("col_n"), T("col_strategy"), "GF", T("col_curl"), T("col_launcher"), "Chromium"
    , T("game_tcp"), T("col_game_ports"), T("col_result"), T("col_ingame")])
for i, w in [30, 230, 40, 105, 105, 65, 110, 95, 200, 90]
    ResLV.ModifyCol(i, w)
MainGui.SetFont("s9", "Consolas")
global OutBox := MainGui.AddEdit("xm w740 h170 ReadOnly -Wrap +HScroll", "")
MainGui.SetFont("s9", "Segoe UI")
MainGui.AddButton("xm w180 h28", T("btn_reports")).OnEvent("Click", OpenReports)
global BtnStop := MainGui.AddButton("x+8 w160 h28 Disabled", T("btn_stop"))
BtnStop.OnEvent("Click", StopClick)
MainGui.OnEvent("Size", GuiResized)
MainGui.OnEvent("Close", GuiClosed)

RefreshInfo()
MainGui.Show()

; прошлый запуск прервался посреди проверки — вернуть Запрет как было
if HasSavedState() {
    RestoreZapretState()
    MsgBox(T("restored_after_crash"), T("app_title"), "Iconi")
    RefreshInfo()
}
SetTimer(StartupChecks, -300)
return

; самопроверка при запуске: не переехал ли игровой сервер (узкая стратегия смотрит на старый IP)
StartupChecks() {
    ip := CheckNarrowIp()
    if !ip.stale
        return
    if (MsgBox(Format(T("server_moved_q"), ip.oldIp, ip.newIp), T("app_title"), "YesNo Icon!") = "Yes") {
        FixNarrowIp(ip.newIp)
        Status(Format(T("server_moved_fixed"), ip.newIp))
    } else
        Status(Format(T("server_moved_warn"), ip.oldIp, ip.newIp))
}

; ==========================================================================

RefreshInfo() {
    if (LauncherExe = "")
        GameText.Value := T("launcher_not_set")
    else
        GameText.Value := T("launcher") ": " LauncherExe "`n" T("game_exe") ": " (GameExe != "" ? GameExe : "—")
            . (IsElectron ? "" : "   (" T("not_electron") ")")
    ZapText.Value := (ZapretRoot != "" ? ZapretRoot : T("not_found")) "`n" T("state_now") ": " ZapretActiveText()
}

Status(msg) => StatusText.Value := msg

ProgressLine(msg) {
    Status(msg)
    OutBox.Value .= "… " msg "`r`n"
}

GameFolderClick(*) {
    if Busy
        return
    if PickGameFolder(MainGui.Hwnd)
        RefreshInfo()
}

ZapretFolderClick(*) {
    if Busy
        return
    if PickZapretFolder()
        RefreshInfo()
}

DiagClick(*) {
    global Busy
    if Busy
        return
    if (ProcessExist("bsgo.exe")) {
        MsgBox(T("close_game_first"), , "Icon!")
        return
    }
    Busy := true
    BtnDiag.Enabled := false
    OutBox.Value := ""
    try {
        d := RunDiagnostics(ProgressLine)
        text := DiagReportText(d)
        OutBox.Value := text
        DirCreate(ReportsDir)
        path := ReportsDir "\" T("report_prefix_diag") "_" FormatTime(, "yyyy-MM-dd_HH-mm") ".txt"
        FileAppend(text, path, "UTF-8")
        Status(T("report_saved") ": " path)
    } catch as e {
        try RestoreZapretState()
        OutBox.Value .= "`r`n" T("error") ": " e.Message " (" e.Line ")"
        Status(T("error") ": " e.Message)
    }
    RefreshInfo()
    BtnDiag.Enabled := true
    Busy := false
}

; ---------- шаг 2: подбор стратегии ----------
ScanClick(*) {
    if Busy
        return
    if (ZapretRoot = "") {
        MsgBox(T("no_zapret"), , "Icon!")
        return
    }
    if !StrategyFiles().Length {
        MsgBox(T("no_strategies"), , "Icon!")
        return
    }
    smart := Cfg("scan", "mode", "smart") = "smart"
    dlg := Gui("+Owner" MainGui.Hwnd " +AlwaysOnTop", T("scan_dialog_title"))
    dlg.SetFont("s9", "Segoe UI")
    radioSmart := dlg.AddRadio("w470" (smart ? " Checked" : ""), T("mode_smart"))
    dlg.AddText("xp+18 w450 cGray", T("smart_desc"))
    dlg.AddRadio("xm w470" (smart ? "" : " Checked"), T("mode_full"))
    dlg.AddText("xp+18 w450 cGray", T("full_desc"))
    selText := dlg.AddText("xm y+12 w300", SelectionText())
    dlg.AddButton("x+8 yp-4 w160", T("btn_pick_strats")).OnEvent("Click", PickFromDialog.Bind(dlg, selText))
    dlg.AddText("xm y+12 w470", T("scan_warn"))
    dlg.AddButton("xm y+10 w140 h30 Default", T("btn_start")).OnEvent("Click", StartScanFromDialog.Bind(dlg, radioSmart))
    dlg.Show()
}

PickFromDialog(dlg, selText, *) => PickStrategies(dlg.Hwnd, RefreshSelText.Bind(selText))
RefreshSelText(selText) => selText.Value := SelectionText()

StartScanFromDialog(dlg, radioSmart, *) {
    global Busy
    scanMode := radioSmart.Value ? "smart" : "full"
    CfgSet("scan", "mode", scanMode)
    if (ProcessExist("bsgo.exe") || ProcessExist("BSGO Launcher.exe")) {
        MsgBox(T("close_launcher_first"), , "Icon! Owner" dlg.Hwnd)
        return
    }
    dlg.Destroy()
    Busy := true
    SetButtons(false)
    ResLV.Delete()
    OutBox.Value := ""
    try {
        scan := RunScan(scanMode, ProgressLine, AddRow, RefreshRows)
        text := ScanReportText(scan)
        OutBox.Value := text
        DirCreate(ReportsDir)
        path := ReportsDir "\" T("report_prefix_scan") "_" FormatTime(, "yyyy-MM-dd_HH-mm") ".txt"
        FileAppend(text, path, "UTF-8")
        Status(T("report_saved") ": " path)
    } catch as e {
        EmergencyRestore()
        OutBox.Value .= "`r`n" T("error") ": " e.Message " (" e.Line ")"
        Status(T("error") ": " e.Message)
    }
    SetButtons(true)
    Busy := false
    RefreshInfo()
}

AddRow(item) {
    ResLV.Add(, ResLV.GetCount() + 1, item.name, item.mode = "—" ? "—" : ModeLabel(item.mode), item.curl, item.node, item.edge
        , item.ports, item.cls = "-" ? "—" : item.covers ? T("covers_yes") : T("covers_no")
        , ClassText(item.cls) (item.reason != "" ? " (" item.reason ")" : ""), item.game)
    item.row := ResLV.GetCount()
    ResLV.Modify(item.row, "Vis")
}

RefreshRows() {
    ResLV.Delete()
    for item in ScanResults
        AddRow(item)
}

SetButtons(enabled) {
    BtnDiag.Enabled := enabled
    BtnPick.Enabled := enabled
    BtnInGame.Enabled := enabled
    BtnStop.Enabled := !enabled
}

; ---------- шаг 3: проверка в игре ----------
InGameClick(*) {
    global Busy, ScanStop
    if Busy
        return
    if !ScanResults.Length {
        MsgBox(T("need_step2"), , "Iconi")
        return
    }
    if (GameExe = "" || !FileExist(LauncherExe)) {
        MsgBox(T("launcher_not_set"), , "Icon!")
        return
    }
    ; выделенная строка — проверить только её; иначе — кандидатов по очереди
    row := ResLV.GetNext(0)
    if (row && row <= ScanResults.Length && InStr("ABE", ScanResults[row].cls) && ScanResults[row].cls != "")
        queue := [ScanResults[row]]
    else
        queue := RankedCandidates()
    if !queue.Length {
        MsgBox(T("no_candidates"), , "Icon!")
        return
    }
    names := ""
    for item in queue
        names .= "  • " item.name "  (GF: " ModeLabel(item.mode) ")`n"
    if (MsgBox(Format(T("ingame_intro"), names), T("btn_ingame"), "OKCancel Iconi") != "OK")
        return

    Busy := true, ScanStop := false
    SetButtons(false)
    OutBox.Value := ""
    hadService := ServiceInfo().exists
    SaveZapretState()
    OnExit(EmergencyRestore)
    kept := false
    try {
        winner := "", applied := ""
        for item in queue {
            if ScanStop
                break
            ProgressLine(Format(T("g_trying"), item.name, ModeLabel(item.mode)))
            CloseGameAndLauncher()
            started := ApplyStrategy(item.name, item.mode)
            applied := item
            res := started ? WatchGame(ProgressLine) : Finish({ok: false, ports: Map(), cmdHosts: "", sec: 0}, T("did_not_start"))
            learned := res.ok ? LearnServer(res.ports) : ""
            OutBox.Value .= SaveGameResult(item.name, item.mode, ClassText(item.cls), res, learned) "`r`n"
            item.game := res.text
            if item.HasOwnProp("row")
                ResLV.Modify(item.row, "Col10", res.text)
            if res.ok {
                winner := {name: item.name, mode: item.mode}
                if (learned != "")
                    OutBox.Value .= "  → " learned "`r`n"
                break
            }
            CloseGameAndLauncher()
        }

        ; удачно, но с глобальным Game Filter TCP — предложить узкую версию только для игры
        if (IsObject(winner) && winner.mode = "tcp" && !ScanStop
            && MsgBox(T("narrow_offer"), T("btn_ingame"), "YesNo Iconi") = "Yes") {
            CloseGameAndLauncher()
            narrowBat := MakeNarrowStrategy(winner.name, &narrowErr)
            if (narrowBat = "")
                OutBox.Value .= T("narrow_failed") ": " narrowErr "`r`n"
            else {
                ProgressLine(Format(T("g_trying"), narrowBat, ModeLabel("disabled")))
                started := ApplyStrategy(narrowBat, "disabled")
                applied := {name: narrowBat, mode: "disabled"}
                res := started ? WatchGame(ProgressLine) : Finish({ok: false, ports: Map(), cmdHosts: "", sec: 0}, T("did_not_start"))
                OutBox.Value .= SaveGameResult(narrowBat, "disabled", T("narrow"), res, "") "`r`n"
                if res.ok
                    winner := {name: narrowBat, mode: "disabled"}
                else {
                    ; неработающую узкую версию не оставляем в папке Запрета, чтобы ей не пользовались по ошибке
                    KillWinws()
                    try FileDelete(ZapretRoot "\" narrowBat)
                    OutBox.Value .= "  → " T("narrow_not_ok") " " T("narrow_deleted") "`r`n"
                }
            }
        }

        if IsObject(winner) {
            msg := Format(T("keep_q"), winner.name, ModeLabel(winner.mode)) (hadService ? "`n`n" T("keep_service_note") : "")
            if (MsgBox(msg, T("btn_ingame"), "YesNo Iconi") = "Yes") {
                if (!IsObject(applied) || applied.name != winner.name || applied.mode != winner.mode)
                    ApplyStrategy(winner.name, winner.mode)
                DiscardZapretState()
                kept := true
                CfgSet("result", "strategy", winner.name)
                CfgSet("result", "game_filter", winner.mode)
                OutBox.Value .= "`r`n" Format(T("kept"), winner.name, ModeLabel(winner.mode)) "`r`n"
            }
        } else
            OutBox.Value .= "`r`n" T("no_winner") "`r`n"
        if !kept {
            ProgressLine(T("p_restore"))
            RestoreZapretState()
        }
    } catch as e {
        EmergencyRestore()
        OutBox.Value .= "`r`n" T("error") ": " e.Message " (" e.Line ")"
    }
    OnExit(EmergencyRestore, 0)
    Status(T("ingame_done"))
    SetButtons(true)
    Busy := false
    RefreshInfo()
}

StopClick(*) {
    global ScanStop
    ScanStop := true
    Status(T("stop_requested"))
}

OpenReports(*) {
    DirCreate(ReportsDir)
    Run('explorer.exe "' ReportsDir '"')
}

SwitchLang(*) {
    if Busy
        return
    CfgSet("ui", "lang", Lang = "ru" ? "en" : "ru")
    Reload()
}

GuiResized(g, minMax, w, h) {
    if (minMax = -1)
        return
    ResLV.Move(, , w - 20)
    OutBox.GetPos(, &oy)
    OutBox.Move(, , w - 20, h - oy - 50)
}

EmergencyRestore(*) {
    try RestoreZapretState()
    return 0
}

GuiClosed(*) {
    if Busy {
        if (MsgBox(T("confirm_abort"), , "YesNo Icon?") != "Yes")
            return true
        EmergencyRestore()
    }
    ExitApp()
}
