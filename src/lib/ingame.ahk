; ==========================================================================
;  Шаг 3. Проверка в игре: стратегия → лаунчер (от обычного пользователя) → вход в мир по логу игры.
;  После удачного входа запоминаются IP и порты, к которым подключалась игра.
;  Узкая стратегия: правило Game Filter той же стратегии, суженное до этих портов и IP.
; ==========================================================================

global WORLD_MARKER := Cfg("game", "world_marker", "has made it into the game")
global WAIT_GAME_START_MS := 300000
global WAIT_WORLD_MS := 180000
global NarrowIpset := "ipset-bsgo-tester.txt"

GameProcName() {
    if (GameExe = "")
        return "bsgo.exe"
    SplitPath(GameExe, &name)
    return name
}

LauncherProcName() {
    SplitPath(LauncherExe, &name)
    return name
}

; закрыть игру и лаунчер (после неудачной попытки — перед следующим кандидатом)
CloseGameAndLauncher() {
    for name in [GameProcName(), LauncherProcName()]
        loop 30 {
            if !ProcessExist(name)
                break
            ProcessClose(name)
            Sleep(200)
        }
    Sleep(1000)
}

; включить стратегию с режимом Game Filter (состояние Запрета уже сохранено вызывающим)
ApplyStrategy(batName, mode) {
    StopZapret()
    WriteGf(mode, ReadGfSettings())
    return StartStrategy(batName)
}

; ждём запуска игры и входа в мир; попутно собираем адреса соединений игры
WatchGame(progressFn) {
    res := {ok: false, text: "", ports: Map(), cmdHosts: "", sec: 0}
    SplitPath(LauncherExe, , &launcherDir)
    ShellRun(LauncherExe, "", launcherDir, "", 1)
    t0 := A_TickCount
    procName := GameProcName()
    while !(gamePid := ProcessExist(procName)) {
        if ScanStop
            return Finish(res, T("g_cancelled"))
        if (A_TickCount - t0 > WAIT_GAME_START_MS)
            return Finish(res, T("g_not_started"))
        progressFn(Format(T("g_wait_play"), (A_TickCount - t0) / 1000))
        Sleep(500)
    }
    gameStart := DateAdd(A_Now, -2, "Seconds")
    tGame := A_TickCount
    res.cmdHosts := GameCmdHosts(gamePid)
    loop {
        CollectGamePorts(gamePid, res.ports)
        txt := ""
        if (GameLogFile != "" && FileExist(GameLogFile) && FileGetTime(GameLogFile, "M") >= gameStart)
            txt := ReadShared(GameLogFile)
        if InStr(txt, WORLD_MARKER) {
            loop 10 {                                     ; ещё 5 с собираем соединения уже в мире
                CollectGamePorts(gamePid, res.ports)
                Sleep(500)
            }
            res.ok := true
            res.sec := Round((A_TickCount - tGame) / 1000)
            return Finish(res, T("g_world"))
        }
        if RegExMatch(txt, "i)10054|forcibly closed")
            return Finish(res, "WSA 10054")
        if !ProcessExist(gamePid)
            return Finish(res, T("g_closed"))
        if ScanStop
            return Finish(res, T("g_cancelled"))
        if (A_TickCount - tGame > WAIT_WORLD_MS)
            return Finish(res, T("g_hang"))
        progressFn(Format(T("g_wait_world"), (A_TickCount - tGame) / 1000))
        Sleep(1000)
    }
}

Finish(res, text) {
    res.text := text
    return res
}

ReadShared(path) {
    try {
        f := FileOpen(path, "r", "UTF-8")
        txt := f.Read()
        f.Close()
        return txt
    }
    return ""
}

; из командной строки игры — только адреса вида IP[:порт]; остальное (возможные токены) не сохраняется
GameCmdHosts(pid) {
    out := ""
    try {
        for proc in ComObjGet("winmgmts:").ExecQuery("SELECT CommandLine FROM Win32_Process WHERE ProcessId=" pid) {
            cmd := String(proc.CommandLine), pos := 1
            while (pos := RegExMatch(cmd, "\b(\d{1,3}(?:\.\d{1,3}){3})(?::(\d{2,5}))?\b", &m, pos)) {
                if !InStr(out, m[0])
                    out .= (out = "" ? "" : ", ") m[0]
                pos += m.Len
            }
        }
    }
    return out
}

; удалённые адреса TCP-соединений процесса игры (кроме веба 80/443)
CollectGamePorts(pid, store) {
    size := 0
    DllCall("iphlpapi\GetExtendedTcpTable", "Ptr", 0, "UInt*", &size, "Int", 0, "UInt", 2, "Int", 5, "UInt", 0)
    if !size
        return
    buf := Buffer(size + 8192), size := buf.Size
    if DllCall("iphlpapi\GetExtendedTcpTable", "Ptr", buf, "UInt*", &size, "Int", 0, "UInt", 2, "Int", 5, "UInt", 0)
        return
    loop NumGet(buf, 0, "UInt") {
        off := 4 + (A_Index - 1) * 24
        if (NumGet(buf, off + 20, "UInt") != pid)
            continue
        st := NumGet(buf, off, "UInt")
        a := NumGet(buf, off + 12, "UInt")
        if (a = 0 || (a & 0xFF) = 127 || (st != 5 && st != 3))
            continue
        p := NumGet(buf, off + 16, "UInt")
        port := ((p & 0xFF) << 8) | ((p >> 8) & 0xFF)
        if (port = 443 || port = 80)
            continue
        ip := (a & 0xFF) "." ((a >> 8) & 0xFF) "." ((a >> 16) & 0xFF) "." ((a >> 24) & 0xFF)
        store[ip ":" port] := true
    }
}

; после удачного входа: игровой IP и порты → tester.ini; дальше проверки идут по ним
LearnServer(seen) {
    global GamePorts
    if !seen.Count
        return ""
    portList := "", ipCount := Map()
    for key in seen {
        parts := StrSplit(key, ":")
        ipCount[parts[1]] := (ipCount.Has(parts[1]) ? ipCount[parts[1]] : 0) + 1
        if !InStr("," portList ",", "," parts[2] ",")
            portList .= (portList = "" ? "" : ",") parts[2]
    }
    portList := Sort(portList, "N D,")
    bestIp := "", bestN := 0
    for ip, n in ipCount
        if (n > bestN)
            bestIp := ip, bestN := n
    oldPorts := Sort(JoinArr(GamePorts), "N D,")
    oldIp := Cfg("server", "game_ip", "")
    firstTime := Cfg("server", "learned", "") = ""
    CfgSet("server", "game_ports", portList)
    CfgSet("server", "game_ip", bestIp)
    CfgSet("server", "learned", FormatTime(, "yyyy-MM-dd HH:mm"))
    GamePorts := ParsePorts(portList)
    if (portList != oldPorts || (oldIp != "" && bestIp != oldIp))
        return Format(T("learn_changed"), bestIp, portList, oldIp != "" ? oldIp : T("site_ip"), oldPorts)
    return Format(firstTime ? T("learn_first") : T("learn_same"), bestIp, portList)
}

; ==========================================================================
;  Узкая стратегия
; ==========================================================================

NarrowName(batName) => RegExReplace(batName, "i)\.bat$") " - BSGO narrow.bat"

; Возвращает имя созданного файла или "" (причина — в errOut).
; Берётся правило Game Filter TCP ЭТОЙ ЖЕ стратегии (оно только что сработало в игре),
; порты заменяются на выученные, список IP — на файл с игровым IP.
; ---------- самопроверка: не переехал ли игровой сервер ----------
; Узкие стратегии смотрят на IP в lists\ipset-bsgo-tester.txt. Если адрес game-сервера сменился,
; достаточно переписать этот файл — сами .bat менять не нужно.
NarrowIpsetPath() => ZapretRoot "\lists\" NarrowIpset

CheckNarrowIp() {
    res := {stale: false, oldIp: "", newIp: ""}
    if (ZapretRoot = "" || !FileExist(NarrowIpsetPath()))
        return res
    if !RegExMatch(FileRead(NarrowIpsetPath()), "(\d{1,3}(?:\.\d{1,3}){3})", &m)
        return res
    res.oldIp := m[1]
    res.newIp := DnsSystem(GameHost())
    if (res.newIp = "")
        res.newIp := DnsDoh(GameHost())
    res.stale := res.newIp != "" && res.newIp != res.oldIp
    return res
}

FixNarrowIp(newIp) {
    WriteRaw(NarrowIpsetPath(), newIp "/32`r`n")
    CfgSet("server", "game_ip", newIp)
}

MakeNarrowStrategy(batName, &errOut) {
    errOut := ""
    learnedIp := Cfg("server", "game_ip", "")
    if (learnedIp = "") {
        errOut := T("narrow_no_ip")
        return ""
    }
    source := FileRead(ZapretRoot "\" batName, "UTF-8")
    if !RegExMatch(source, "(?m)^[^\r\n]*--filter-tcp=%GameFilterTCP%[^\r\n]*$") {
        errOut := T("narrow_no_gf_rule")
        return ""
    }
    WriteRaw(ZapretRoot "\lists\" NarrowIpset, learnedIp "/32`r`n")
    outName := NarrowName(batName)
    ; у cmd предел длины команды 8191 символ после подстановки путей — при длинном пути к Запрету
    ; правило может не влезть. Тогда сокращаем: 1) без --ipset-exclude в новом правиле
    ; (оно и так для одного IP), 2) без исходного правила Game Filter TCP (при выключенном GF оно холостое).
    lastErr := ""
    for level in [0, 1, 2] {
        WriteRaw(ZapretRoot "\" outName, BuildNarrowText(source, level))
        lastErr := DryRunStrategy(outName, "disabled")
        if (lastErr = "")
            return outName
    }
    try FileDelete(ZapretRoot "\" outName)
    errOut := T("narrow_dryrun_failed") ": " lastErr
    return ""
}

; level 0 — полная копия правила; 1 — без --ipset-exclude; 2 — ещё и без исходного правила Game Filter TCP
BuildNarrowText(source, level) {
    RegExMatch(source, "(?m)^[^\r\n]*--filter-tcp=%GameFilterTCP%[^\r\n]*$", &m)
    ports := JoinArr(GamePorts)
    rule := StrReplace(m[0], "--filter-tcp=%GameFilterTCP%", "--filter-tcp=" ports)
    if RegExMatch(rule, '--ipset="[^"]*"')
        rule := RegExReplace(rule, '--ipset="[^"]*"', '--ipset="%LISTS%' NarrowIpset '"', , 1)
    else
        rule := StrReplace(rule, "--filter-tcp=" ports, "--filter-tcp=" ports ' --ipset="%LISTS%' NarrowIpset '"')
    if (level >= 1)
        rule := RegExReplace(rule, '\s--ipset-exclude="[^"]*"')
    if !RegExMatch(rule, "--new\s*\^\s*$")              ; правило было последним — дописываем разделитель
        rule := RTrim(rule, " ^") " --new ^"
    gfLine := m[0]
    if (level >= 2 && RegExMatch(gfLine, "--new\s*\^\s*$"))
        gfLine := ""                                    ; исходное правило GF убираем, только если оно не последнее
    text := SubStr(source, 1, m.Pos - 1) rule (gfLine != "" ? "`r`n" gfLine : "") SubStr(source, m.Pos + m.Len)

    ; порты — в перехват WinDivert (--wf-tcp), если их там нет
    if RegExMatch(text, "--wf-tcp=([^\s\^]+)", &wf) {
        add := ""
        for port in GamePorts
            if !PortInList(StrReplace(wf[1], "%GameFilterTCP%", "12"), port)
                add .= "," port
        if (add != "")
            text := SubStr(text, 1, wf.Pos[1] - 1) wf[1] add SubStr(text, wf.Pos[1] + wf.Len[1])
    }
    return text
}

; проверка стратегии без запуска: winws --dry-run только разбирает параметры. "" — всё в порядке, иначе текст ошибки
DryRunStrategy(batName, gfMode) {
    lines := StrSplit(FileRead(ZapretRoot "\" batName, "UTF-8"), "`n", "`r")
    startIdx := 0
    for i, ln in lines
        if RegExMatch(ln, "i)^\s*start\s") {
            startIdx := i
            break
        }
    if !startIdx
        return "no start line"
    gf := ReadGfSettings()
    body := "@echo off`r`nchcp 65001 > nul`r`n"
        . 'set "BIN=' ZapretRoot '\bin\"' "`r`n"
        . 'set "LISTS=' ZapretRoot '\lists\"' "`r`n"
        . "set GameFilterTCP=" gf.tcp "`r`nset GameFilterUDP=" gf.udp "`r`n"   ; самые длинные значения — проверка с запасом
        . 'cd /d "%BIN%"' "`r`n"
        ; та же строка, что при настоящем запуске: start с тем же заголовком (имя батника вместо %~n0),
        ; только /b /wait вместо /min и --dry-run — она даже чуть длиннее настоящей, т.е. проверка с запасом
        . RegExReplace(StrReplace(lines[startIdx], "%~n0", RegExReplace(batName, "i)\.bat$"))
            , 'i)^(\s*start\s+"[^"]*")\s+/min\s+"%BIN%winws\.exe"', '$1 /b /wait "%BIN%winws.exe" --dry-run') "`r`n"
    loop lines.Length - startIdx
        body .= lines[startIdx + A_Index] "`r`n"
    body .= "echo EXIT=%ERRORLEVEL%`r`n"
    tmpBat := A_Temp "\bsgo_tester_dry.bat", outFile := A_Temp "\bsgo_tester_dry.txt"
    WriteRaw(tmpBat, body)
    try FileDelete(outFile)
    RunWait(A_ComSpec ' /c ""' tmpBat '" > "' outFile '" 2>&1"', , "Hide")
    txt := FileExist(outFile) ? FileRead(outFile, "UTF-8") : ""
    if InStr(txt, "EXIT=0")
        return ""
    txt := Trim(RegExReplace(txt, "\s+", " "))
    return SubStr(txt != "" ? txt : "no output", 1, 300)
}

; ==========================================================================
;  Журнал проверок в игре
; ==========================================================================

SaveGameResult(name, mode, predicted, res, learned) {
    seenText := ""
    for key in res.ports
        seenText .= (seenText = "" ? "" : ", ") key
    line := FormatTime(, "yyyy-MM-dd HH:mm") " | " name " | GF=" ModeLabel(mode) " | " T("forecast") ": " predicted
        . " | " T("in_game") ": " res.text (res.ok ? " (" res.sec " s)" : "")
        . " | " T("game_conns") ": " (seenText != "" ? seenText : "—")
        . (res.cmdHosts != "" ? " | " T("cmd_hosts") ": " res.cmdHosts : "")
        . (learned != "" ? " | " learned : "")
    DirCreate(ReportsDir)
    FileAppend(line "`r`n", ReportsDir "\" T("report_prefix_ingame") ".txt", "UTF-8")
    return line
}
