; ==========================================================================
;  Шаг 1. Диагностика: что сломано без обхода и помогает ли текущий Запрет.
; ==========================================================================

; progressFn(text) — показывать ход проверки
RunDiagnostics(progressFn) {
    d := {noBypass: "", with: "", hadZapret: false, zapretText: ZapretActiveText(), edgeOk: false, bigResolved: false
        , narrowIp: {stale: false, oldIp: "", newIp: ""}}
    progressFn(T("p_prepare"))
    d.bigResolved := ResolveBigUrl()
    global EdgeReliable := EdgeSelfTest()
    global CurlReliable := CurlSelfTest()
    global NodeReliable := LauncherEngineSelfTest()
    d.edgeOk := EdgeReliable
    d.narrowIp := CheckNarrowIp()
    if IsElectron
        WriteNodeScript()

    svc := ServiceInfo()
    d.hadZapret := svc.running || ProcessExist("winws.exe")
    if d.hadZapret {
        progressFn(T("p_with_zapret"))
        d.with := RunNetChecks()
        progressFn(T("p_stop_zapret"))
        SaveZapretState()
        OnExit(EmergencyRestore)
        StopZapret()
    }
    progressFn(T("p_without"))
    d.noBypass := RunNetChecks()
    if d.hadZapret {
        progressFn(T("p_restore"))
        RestoreZapretState()
        OnExit(EmergencyRestore, 0)
    }
    d.verdict := MakeVerdict(d.noBypass)
    d.withOk := IsObject(d.with) && NetAllOk(d.with)
    return d
}

NetAllOk(r) => r.tcp443 && LauncherLevel(r) = "ok"

; код проблемы без обхода → {code, text}; решаемо ли Запретом — в code
MakeVerdict(r) {
    if (r.dnsSys = "" && r.dnsDoh != "")
        return {code: "dns", text: T("v_dns")}
    if (r.ip = "")
        return {code: "offline", text: T("v_offline")}
    if !r.tcp443
        return {code: "ip_block", text: T("v_ip_block")}
    switch LauncherLevel(r) {
        case "unknown": return {code: "unknown", text: T("v_unknown")}
        case "noanswer": return {code: "tls", text: T("v_tls")}
        case "stall": return {code: "volume", text: Format(T("v_volume"), r.main.stallKb)}
        case "partial": return {code: "volume", text: T("v_partial")}
        case "chromium": return {code: "chromium", text: T("v_chromium")}
    }
    if !PortsAllOk(r.ports)
        return {code: "ports", text: Format(T("v_ports"), JoinArr(GamePorts, ", "))}
    return {code: "ok", text: T("v_ok")}
}

; что делать дальше
NextStepText(d) {
    code := d.verdict.code
    if (code = "ok")
        return T("n_ok")
    if (code = "dns")
        return T("n_dns")
    if (code = "offline")
        return T("n_offline")
    if (code = "ip_block")
        return T("n_vpn")
    if (code = "unknown")
        return T("n_unknown")
    if d.withOk
        return T("n_current_works")
    return ZapretRoot != "" ? T("n_go_step2") : T("n_install_zapret")
}

NetLines(r) {
    nl := "`r`n", out := ""
    out .= "  DNS: " T("dns_system") " " (r.dnsSys != "" ? r.dnsSys : T("no")) ", DoH " (r.dnsDoh != "" ? r.dnsDoh : T("no")) nl
    out .= "  TCP 443: " (r.tcp443 ? T("ok") : T("no")) ",  HTTPS (" T("short") ", curl): "
        . (!CurlReliable ? T("not_checked") : r.smallOk ? T("ok") : T("no") " (" r.small.err ")") nl
    out .= "  " T("download") " curl: " (CurlReliable ? AttemptsText(r.curl) : T("not_checked")) nl
    out .= "  " T("download") " " T("launcher_engine") ": " (IsObject(r.node) ? AttemptsText(r.node) : T("not_electron"))
        . (IsObject(r.node) ? "   ← " T("main_check") : "") nl
    out .= "  Chromium (" T("connected_status") "): " EdgeText(r.edge) nl
    out .= "  " T("game_tcp") ": " PortsText(r.ports) nl
    return out
}

DiagReportText(d) {
    nl := "`r`n"
    out := T("diag_title") " — " FormatTime(, "yyyy-MM-dd HH:mm") nl
    out .= T("game") ": " (LauncherExe != "" ? LauncherExe : "—") nl
    out .= T("server") ": " Host ",  " T("game_ports") ": " JoinArr(GamePorts, ", ")
        . (Cfg("server", "learned", "") != "" ? "  (" T("learned_at") " " Cfg("server", "learned", "") ")" : "  (" T("ports_default") ")") nl
    out .= T("zapret") ": " (ZapretRoot != "" ? ZapretRoot : T("not_found")) ",  " T("state_before") ": " d.zapretText nl
    if !d.edgeOk
        out .= T("warn") ": " T("edge_unavailable") nl
    for noteLine in StrSplit(RTrim(ListsNote, "`r`n"), "`n", "`r")
        if (noteLine != "")
            out .= T("warn") ": " noteLine nl
    if !CurlReliable
        out .= T("warn") ": " T("curl_unavailable") nl
    if (IsElectron && !NodeReliable)
        out .= T("warn") ": " T("node_unavailable") nl
    if d.narrowIp.stale
        out .= T("warn") ": " Format(T("server_moved_warn"), d.narrowIp.oldIp, d.narrowIp.newIp) nl
    if !d.bigResolved && IsNova()
        out .= T("warn") ": " T("latest_unreadable") nl
    out .= nl "== " T("without_bypass") " ==" nl NetLines(d.noBypass)
    if IsObject(d.with)
        out .= nl "== " T("with_current_zapret") " ==" nl NetLines(d.with)
            . "  → " (d.withOk ? T("current_ok") : T("current_not_ok")) nl
    out .= nl "== " T("conclusion") " ==" nl "  " d.verdict.text nl nl "== " T("what_next") " ==" nl "  " NextStepText(d) nl
    return out
}
