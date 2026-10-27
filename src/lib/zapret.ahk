; ==========================================================================
;  Управление Запретом (Flowseal zapret-discord-youtube): папка, служба, winws.exe,
;  Game Filter. Перед любым вмешательством состояние сохраняется в файлы восстановления,
;  чтобы вернуть его даже после аварийного закрытия.
; ==========================================================================

global ZapretRoot := ""
global RestoreDir := A_ScriptDir "\restore"

LoadZapret() {
    global ZapretRoot
    ZapretRoot := Cfg("zapret", "root", "")
    if (ZapretRoot = "" || !IsZapretRoot(ZapretRoot))
        ZapretRoot := GuessZapretRoot()
    if (ZapretRoot != "")
        CfgSet("zapret", "root", ZapretRoot)
}

IsZapretRoot(dir) => FileExist(dir "\service.bat") && FileExist(dir "\bin\winws.exe")

; запущенный winws.exe → путь службы zapret → рабочий стол / загрузки (до 2 уровней вложенности)
GuessZapretRoot() {
    try {
        for proc in ComObjGet("winmgmts:").ExecQuery("SELECT ExecutablePath FROM Win32_Process WHERE Name='winws.exe'") {
            dir := RegExReplace(String(proc.ExecutablePath), "i)\\bin\\winws\.exe$")
            if IsZapretRoot(dir)
                return dir
        }
    }
    svc := ServiceInfo()
    if (svc.binDir != "" && IsZapretRoot(svc.binDir))
        return svc.binDir
    for searchDir in [A_Desktop, EnvGet("USERPROFILE") "\Downloads", "C:\"] {
        loop files, searchDir "\*", "D" {
            if IsZapretRoot(A_LoopFileFullPath)
                return A_LoopFileFullPath
            loop files, A_LoopFileFullPath "\*", "D"
                if IsZapretRoot(A_LoopFileFullPath)
                    return A_LoopFileFullPath
        }
    }
    return ""
}

PickZapretFolder() {
    global ZapretRoot
    dir := DirSelect(, 0, T("pick_zapret_folder"))
    if (dir = "")
        return false
    if !IsZapretRoot(dir) {
        MsgBox(T("not_zapret_folder"), , "Icon!")
        return false
    }
    ZapretRoot := dir
    CfgSet("zapret", "root", dir)
    return true
}

; ---------- служба zapret ----------
ScOutput(args) {
    tmp := A_Temp "\bsgo_tester_sc.txt"
    try FileDelete(tmp)
    RunWait(A_ComSpec ' /c sc.exe ' args ' > "' tmp '" 2>&1', , "Hide")
    return FileExist(tmp) ? FileRead(tmp) : ""
}

ServiceInfo() {
    q := ScOutput("query zapret")
    info := {exists: InStr(q, "SERVICE_NAME") > 0, running: InStr(q, "RUNNING") > 0, binDir: ""}
    if info.exists {
        qc := ScOutput("qc zapret")
        if RegExMatch(qc, 'i)BINARY_PATH_NAME\s*:\s*"?([^"\r\n]*?\\bin\\winws\.exe)', &m)
            info.binDir := RegExReplace(m[1], "i)\\bin\\winws\.exe$")
    }
    return info
}

WaitService(running, timeoutMs := 15000) {
    deadline := A_TickCount + timeoutMs
    while (A_TickCount < deadline) {
        if (ServiceInfo().running = running)
            return true
        Sleep(500)
    }
    return false
}

; ---------- winws.exe ----------
SnapshotWinws() {
    arr := []
    try {
        for proc in ComObjGet("winmgmts:").ExecQuery("SELECT ExecutablePath, CommandLine FROM Win32_Process WHERE Name='winws.exe'")
            try arr.Push({exe: String(proc.ExecutablePath), cmd: String(proc.CommandLine)})
    }
    return arr
}

KillWinws() {
    loop 20 {
        if !ProcessExist("winws.exe")
            return true
        ProcessClose("winws.exe")
        Sleep(150)
    }
    return !ProcessExist("winws.exe")
}

; запуск стратегии (.bat) и ожидание winws.exe
StartStrategy(batName) {
    Run(A_ComSpec ' /d /c ""' ZapretRoot "\" batName '""', ZapretRoot, "Hide")
    loop 60 {
        if ProcessExist("winws.exe") {
            Sleep(1500)
            return ProcessExist("winws.exe") ? true : false
        }
        Sleep(250)
    }
    return false
}

ZapretActiveText() {
    svc := ServiceInfo()
    if svc.running
        return T("zapret_service_on")
    if ProcessExist("winws.exe")
        return T("zapret_winws_on")
    return T("zapret_off")
}

; ---------- Game Filter (utils\game_filter.enabled) ----------
GfPath() => ZapretRoot "\utils\game_filter.enabled"

ReadGfSettings() {
    gfs := {mode: "disabled", tcp: "1024-65535", udp: "1024-65535"}
    if !FileExist(GfPath())
        return gfs
    for ln in StrSplit(FileRead(GfPath()), "`n", "`r ") {
        if RegExMatch(ln, "i)^\s*mode\s*=\s*(\S+)", &m)
            gfs.mode := StrLower(m[1])
        else if RegExMatch(ln, "i)^\s*tcp\s*=\s*(\S+)", &m)
            gfs.tcp := m[1]
        else if RegExMatch(ln, "i)^\s*udp\s*=\s*(\S+)", &m)
            gfs.udp := m[1]
    }
    return gfs
}

WriteGf(mode, settings) {
    f := FileOpen(GfPath(), "w", "UTF-8-RAW")
    f.Write("mode=" mode "`r`ntcp=" settings.tcp "`r`nudp=" settings.udp "`r`n")
    f.Close()
}

ModeLabel(mode) => mode = "tcp" ? "TCP" : mode = "disabled" ? T("gf_off") : mode

; ==========================================================================
;  Сохранение и восстановление состояния Запрета
; ==========================================================================

; сохраняет всё, что будет меняться: служба, команды winws, файл Game Filter
SaveZapretState() {
    DirCreate(RestoreDir)
    svc := ServiceInfo()
    state := "service_running=" (svc.running ? 1 : 0) "`n"
    if FileExist(GfPath()) {
        FileCopy(GfPath(), RestoreDir "\game_filter.enabled", 1)
        state .= "gf=EXISTS`n"
    } else
        state .= "gf=ABSENT`n"
    winws := ""
    if !svc.running                           ; winws службы вернётся вместе со службой
        for item in SnapshotWinws()
            winws .= item.exe "|" item.cmd "`n"
    WriteRaw(RestoreDir "\winws.txt", winws)
    WriteRaw(RestoreDir "\state.txt", state)    ; пишется последним: его наличие = «есть что восстанавливать»
}

HasSavedState() => FileExist(RestoreDir "\state.txt")

; останавливает Запрет целиком (службу и/или winws)
StopZapret() {
    if ServiceInfo().running {
        RunWait("sc.exe stop zapret", , "Hide")
        WaitService(false)
    }
    return KillWinws()
}

RestoreZapretState() {
    if !HasSavedState()
        return false
    state := FileRead(RestoreDir "\state.txt")
    KillWinws()
    if InStr(state, "gf=EXISTS") && FileExist(RestoreDir "\game_filter.enabled")
        FileCopy(RestoreDir "\game_filter.enabled", GfPath(), 1)
    else if InStr(state, "gf=ABSENT")
        try FileDelete(GfPath())
    if InStr(state, "service_running=1") {
        RunWait("sc.exe start zapret", , "Hide")
        WaitService(true)
    } else if FileExist(RestoreDir "\winws.txt") {
        for ln in StrSplit(FileRead(RestoreDir "\winws.txt"), "`n", "`r") {
            if (ln = "")
                continue
            parts := StrSplit(ln, "|", , 2)
            exe := parts[1], cmd := parts.Length > 1 ? parts[2] : ""
            if RegExMatch(cmd, '^\s*"[^"]*"\s*(.*)$', &m)
                args := m[1]
            else
                args := Trim(SubStr(cmd, StrLen(exe) + 1))
            SplitPath(exe, , &exeDir)
            try Run('"' exe '" ' args, exeDir, "Min")
        }
    }
    DiscardZapretState()
    return true
}

; после «оставить новую стратегию» — восстанавливать больше нечего
DiscardZapretState() {
    try FileDelete(RestoreDir "\state.txt")
    try FileDelete(RestoreDir "\winws.txt")
    try FileDelete(RestoreDir "\game_filter.enabled")
}

WriteRaw(path, text) {
    f := FileOpen(path, "w", "UTF-8-RAW")
    f.Write(text)
    f.Close()
}
