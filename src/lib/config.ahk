; ==========================================================================
;  Настройки тестера: tester.ini рядом с программой.
;  Игра (лаунчер, bsgo.exe, лог), сервер (сайт, игровые порты, IP) — всё хранится у игрока.
; ==========================================================================

global CfgPath := A_ScriptDir "\tester.ini"

Cfg(section, key, def := "") => IniRead(CfgPath, section, key, def)
CfgSet(section, key, value) => IniWrite(value, CfgPath, section, key)

; ---------- игра ----------
global LauncherExe := "", GameExe := "", GameLogFile := "", IsElectron := false

LoadGame() {
    global LauncherExe, GameExe
    LauncherExe := Cfg("game", "launcher", "")
    if !FileExist(LauncherExe)
        LauncherExe := DetectLauncher()
    GameExe := Cfg("game", "game_exe", "")
    if !FileExist(GameExe)
        GameExe := FindGameExe(LauncherExe)
    UpdateGameDerived()
}

; запущенный лаунчер Nova → стандартная папка Nova → пусто (тогда игрок выберет сам)
DetectLauncher() {
    try {
        for proc in ComObjGet("winmgmts:").ExecQuery("SELECT ExecutablePath FROM Win32_Process WHERE Name='BSGO Launcher.exe'") {
            path := String(proc.ExecutablePath)
            if FileExist(path)
                return path
        }
    }
    for cand in ["C:\Games\bsgo nova\BSGO Launcher\BSGO Launcher.exe", A_ProgramFiles "\BSGO Launcher\BSGO Launcher.exe"
        , EnvGet("LOCALAPPDATA") "\Programs\bsgo-launcher\BSGO Launcher.exe"]
        if FileExist(cand)
            return cand
    return ""
}

; bsgo.exe внутри папки лаунчера; если их несколько — тот, что в ...\live\
FindGameExe(launcher) {
    if (launcher = "")
        return ""
    SplitPath(launcher, , &dir)
    found := ""
    loop files, dir "\bsgo.exe", "R" {
        if InStr(A_LoopFileFullPath, "\live\")
            return A_LoopFileFullPath
        if (found = "")
            found := A_LoopFileFullPath
    }
    return found
}

UpdateGameDerived() {
    global GameLogFile, IsElectron
    GameLogFile := ""
    if (GameExe != "") {
        SplitPath(GameExe, , &gameDir)
        GameLogFile := gameDir "\bsgo_Data\output_log.txt"
    }
    IsElectron := false
    if (LauncherExe != "") {
        SplitPath(LauncherExe, , &launcherDir)
        IsElectron := FileExist(launcherDir "\resources\app.asar") ? true : false
    }
}

SaveGame() {
    CfgSet("game", "launcher", LauncherExe)
    CfgSet("game", "game_exe", GameExe)
}

; ручной выбор: у приватных серверов BSGO свои лаунчеры, и у всех есть bsgo.exe
PickGameFolder(ownerHwnd) {
    global LauncherExe, GameExe
    dir := DirSelect(, 0, T("pick_game_folder"))
    if (dir = "")
        return false
    launcher := ""
    if FileExist(dir "\BSGO Launcher.exe")
        launcher := dir "\BSGO Launcher.exe"
    else {
        exes := []
        loop files, dir "\*.exe"
            if !RegExMatch(A_LoopFileName, "i)^(unins|uninstall|setup|update|elevate)")
                exes.Push(A_LoopFileFullPath)
        if (exes.Length = 1)
            launcher := exes[1]
        else
            launcher := FileSelect(1, dir, T("pick_launcher_exe"), "*.exe")
    }
    if (launcher = "")
        return false
    game := FindGameExe(launcher)
    if (game = "")
        game := FileSelect(1, dir, T("pick_game_exe"), "bsgo.exe")
    if (game = "")
        return false
    LauncherExe := launcher, GameExe := game
    UpdateGameDerived()
    SaveGame()
    return true
}

; ---------- сервер ----------
; Host — сайт/API игры. Порты и IP игрового сервера выучиваются при подтверждённом входе в мир.
global Host := Cfg("server", "host", "playbsgo.com")
global GamePorts := ParsePorts(Cfg("server", "game_ports", "27050,9338"))
global BigUrl := Cfg("server", "installer_url", "")

IsNova() => Host = "playbsgo.com"
SiteUrl() => "https://" Host "/"
; имя игрового сервера: лаунчер Nova находит сервер по этому имени (с версии 1.0.81)
GameHost() => Cfg("server", "game_host", IsNova() ? "game.playbsgo.com" : Host)
; маленький ответ: у Nova — фид обновлений лаунчера, у других серверов — любая короткая страница
SmallUrl() => IsNova() ? "https://playbsgo.com/download/latest.yml" : "https://" Host "/favicon.ico"
GameIp(siteIp) {
    learned := Cfg("server", "game_ip", "")
    return learned != "" ? learned : siteIp
}

ParsePorts(portText) {
    arr := []
    for part in StrSplit(portText, ",", " ")
        if IsInteger(part)
            arr.Push(Integer(part))
    return arr.Length ? arr : [27050, 9338]
}

JoinArr(arr, sep := ",") {
    out := ""
    for v in arr
        out .= (out = "" ? "" : sep) v
    return out
}
