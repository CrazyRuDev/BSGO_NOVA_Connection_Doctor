#Requires AutoHotkey v2.0 64-bit
#SingleInstance Force
Persistent

; ==========================================================================
;  Наблюдатель BSGO Nova — запись этапов подключения лаунчера и игры.
;
;  Только наблюдает:
;   * таблица TCP/UDP-соединений Windows (какой процесс, куда, в каком состоянии);
;   * DNS-кэш Windows (чтобы подписать IP именами);
;   * время изменения файла сессии лаунчера (содержимое НЕ читается);
;   * новые строки лога игры output_log.txt и диагностического лога лаунчера
;     (длинные строки, похожие на токены, и почты вырезаются);
;   * дисковая активность и окна процессов лаунчера и игры.
;  Пароли, токены и содержимое файла сессии не читаются и не записываются.
; ==========================================================================

global WATCHER_VERSION := "0.1"

; ---------- аргументы для самопроверки ----------
global SelfTestSec := 0, ArgExtra := ""
global ArgGameLog := IniRead(A_ScriptDir "\watcher.ini", "paths", "gamelog", "")
loop A_Args.Length {
    if (A_Args[A_Index] = "--gamelog" && A_Index < A_Args.Length)
        ArgGameLog := A_Args[A_Index + 1]
    if (A_Args[A_Index] = "--selftest" && A_Index < A_Args.Length)
        SelfTestSec := Integer(A_Args[A_Index + 1])
    if (A_Args[A_Index] = "--extra" && A_Index < A_Args.Length)
        ArgExtra := A_Args[A_Index + 1]
}

; ---------- настройки ----------
global IniPath := A_ScriptDir "\watcher.ini"
global LauncherExe := IniRead(IniPath, "paths", "launcher", "C:\Games\bsgo nova\BSGO Launcher\BSGO Launcher.exe")
global KnownHosts := StrSplit(IniRead(IniPath, "watch", "hosts", "playbsgo.com,game.playbsgo.com,www.playbsgo.com"), ",", " ")
global WatchNames := Map("bsgo launcher.exe", "лаунчер", "bsgo.exe", "игра")
for extraName in StrSplit(IniRead(IniPath, "watch", "extra", "") "," ArgExtra, ",", " ")
    if (extraName != "")
        WatchNames[StrLower(extraName)] := "доп"

global TokenFile := A_AppData "\bsgo-launcher\bsgo_session_token"
global DiagLogFile := A_AppData "\bsgo-launcher\token-diag.log"

; ---------- состояние ----------
global Recording := false, RecDir := "", RecStartTick := 0, RecStartStamp := ""
global CurrentStage := "до отметок"
global PendingLines := [], StageMarks := []
global Procs := Map(), Conns := Map(), Endpoints := Map(), DoneConns := []
global UdpSeen := Map(), UdpLog := []
global IpNames := Map(), DnsQueried := Map()
global TailState := Map()
global IoPrev := Map(), IoAcc := Map()
global WinTitles := Map()
global TokenStamp := "", ZapretOn := -1
global GameStartStamp := "", GameLogPendingReset := false, GameSeenInRec := false
global GameLineCount := Map(), GameLogCopies := 0
global FirstProcPoll := true, FirstTcpPoll := true

; строки лога игры, которые обозначают этапы: [текст в логе, подпись, ставить авто-отметку]
global GameMarkers := [
    ["has made it into the game", "ВХОД В МИР", true],
    ["Game.Me.ServerID", "игровой сервер принял вход (ServerID)", true],
    ["PlayerShip.OnRead IsMe-true", "получены данные своего корабля", true],
    ["Loading player ship", "загрузка своего корабля", false],
    ["Welcome to BGO Console", "клиент игры инициализирован", false],
    ["Game / Sector Start", "старт клиента / смена сектора", false],
    ["Loading Next Scene", "загрузка сцены", false]
]
global GameErrorRx := "i)error|exception|disconnect|connect|10054|timeout|timed out|lost|refused|connection reset|reset by peer|fail|kick|socket|ssl"
global GameNoiseRx := "i)Unloading|BsgoPaths|shader|AssetCatalogue\] (Placeholder|Bundle cached)|LOADOUT-DBG"

global MarkTexts := ["1. Лаунчер: «Соединено»", "2. Вошёл в аккаунт", "3. «Играть» доступна"
    , "4. Нажал «Играть»", "5. Экран загрузки игры", "6. Я в мире", "7. Ошибка / WSA 10054"
    , "8. Зависло", "9. Лаунчер завис", "0. Заметка…"]

; адреса, про которые уже известно, что на вход в игру они не влияют
global KnownHarmless := Map("178.132.246.28", "телеметрия Bigpoint (eventstream), на вход в игру не влияет")

; проверка файлов лаунчером видна как чтение диска: порог — МБ за окно 5 с
global FILECHECK_MB := 150
global FileCheckActive := false

; ---------- окно ----------
global MainGui := Gui("+AlwaysOnTop +Resize +MinSize660x430", "Наблюдатель BSGO Nova " WATCHER_VERSION)
MainGui.SetFont("s9", "Segoe UI")
global BtnStart := MainGui.AddButton("xm w150 h28", "▶ Начать запись")
BtnStart.OnEvent("Click", StartRec)
global BtnStop := MainGui.AddButton("x+6 w170 h28 Disabled", "■ Остановить и сохранить")
BtnStop.OnEvent("Click", StopRecClick)
MainGui.AddButton("x+6 w140 h28", "Запустить лаунчер").OnEvent("Click", LaunchLauncher)
MainGui.AddButton("x+6 w150 h28", "Папка записей").OnEvent("Click", OpenRecords)
global StatusText := MainGui.AddText("xm w640 h34", "Запись не идёт.")
MainGui.AddGroupBox("xm w640 h94", "Отметки этапов — нажимайте, когда этап наступил (или Ctrl+Alt+цифра)")
loop MarkTexts.Length {
    markOpt := (A_Index = 1) ? "xp+8 yp+22 w122 h28" : (A_Index = 6) ? "xm+8 y+6 w122 h28" : "x+4 w122 h28"
    MainGui.AddButton(markOpt, MarkTexts[A_Index]).OnEvent("Click", MarkClick.Bind(A_Index))
}
global EventsLV := MainGui.AddListView("xm y+18 w640 h320", ["Время", "Источник", "Событие"])
EventsLV.ModifyCol(1, 85), EventsLV.ModifyCol(2, 80), EventsLV.ModifyCol(3, 460)
MainGui.OnEvent("Size", GuiResized)
MainGui.OnEvent("Close", GuiClosed)
MainGui.Show(SelfTestSec ? "NoActivate" : "")

loop 10
    Hotkey("^!" Mod(A_Index, 10), MarkHotkey.Bind(A_Index))

AddEvent("старт", "Наблюдатель запущен. Лаунчер: " LauncherExe (FileExist(LauncherExe) ? "" : "  (НЕ НАЙДЕН — укажите при запуске)"))
SetTimer(FastTick, 200)
SetTimer(SlowTick, 1000)
SetTimer(DnsTick, 3000)
SetTimer(FlushJournal, 1000)
SetTimer(UpdateStatus, 500)
SetTimer(ResolveKnownHosts, -300)

if SelfTestSec {
    SetTimer(StartRec, -1500)
    SetTimer(SelfTestEnd, -(SelfTestSec * 1000 + 1500))
}
return

; ==========================================================================
;  Журнал событий
; ==========================================================================

AddEvent(src, text) {
    stamp := FormatTime(, "HH:mm:ss") "." Format("{:03}", A_MSec)
    if Recording
        PendingLines.Push(stamp "  " Format("{:-9}", RelTime(A_TickCount)) " [" src "] " text)
    EventsLV.Insert(1, , stamp, src, text)
    if (EventsLV.GetCount() > 400)
        EventsLV.Delete(401)
}

AutoMark(text) {
    if Recording
        StageMarks.Push({tick: A_TickCount, text: "[авто] " text})
}

RelTime(tick) => Recording || RecStartTick ? Format("+{:.1f}с", (tick - RecStartTick) / 1000) : ""

FlushJournal() {
    if (!Recording || !PendingLines.Length)
        return
    out := ""
    for ln in PendingLines
        out .= ln "`r`n"
    PendingLines.Length := 0
    try FileAppend(out, RecDir "\журнал.txt", "UTF-8")
}

ReportError(where, e) {
    static lastShown := Map()
    key := where e.Message
    if (lastShown.Has(key) && A_TickCount - lastShown[key] < 30000)
        return
    lastShown[key] := A_TickCount
    AddEvent("ошибка", where ": " e.Message " (строка " e.Line ")")
}

Shorten(s) => StrLen(s) > 220 ? SubStr(s, 1, 220) "…" : s

Redact(s) {
    s := RegExReplace(s, "[\w.+-]+@[\w-]+(\.[\w-]+)+", "<почта>")
    s := RegExReplace(s, "[A-Za-z0-9_\-+/=]{24,}", "<скрыто>")
    s := RegExReplace(s, "i)(token|password|passwd|pwd|secret|ticket|auth)(\W{1,3})\S+", "$1$2<скрыто>")
    return s
}

; ==========================================================================
;  Таймеры
; ==========================================================================

FastTick() {
    static busy := false
    if busy
        return
    busy := true
    try PollProcesses()
    catch as e
        ReportError("процессы", e)
    try PollTcp()
    catch as e
        ReportError("TCP", e)
    busy := false
}

SlowTick() {
    for fn in [PollUdp, PollToken, PollDiagLog, PollGameLog, PollIo, PollWindows, PollZapret] {
        try fn()
        catch as e
            ReportError(fn.Name, e)
    }
}

DnsTick() {
    try PollDnsCache()
    catch as e
        ReportError("DNS", e)
}

UpdateStatus() {
    nL := 0, nG := 0
    for pid, p in Procs {
        if (p.role = "лаунчер")
            nL++
        else if (p.role = "игра")
            nG++
    }
    head := Recording ? "● ИДЁТ ЗАПИСЬ  " RelTime(A_TickCount) : "Запись не идёт."
    StatusText.Value := head "     Текущий этап: " CurrentStage "`nПроцессов лаунчера: " nL ",  игры: " nG
        . "     TCP-соединений сейчас: " Conns.Count "     Запрет (winws.exe): " (ZapretOn = 1 ? "работает" : "не запущен")
}

; ==========================================================================
;  Процессы
; ==========================================================================

PollProcesses() {
    global FirstProcPoll, GameStartStamp, GameLogPendingReset, GameSeenInRec, LauncherExe
    seen := Map()
    snap := DllCall("CreateToolhelp32Snapshot", "UInt", 2, "UInt", 0, "Ptr")
    if (snap = -1)
        return
    pe := Buffer(568, 0)
    NumPut("UInt", 568, pe, 0)
    ok := DllCall("Process32FirstW", "Ptr", snap, "Ptr", pe)
    while ok {
        exe := StrGet(pe.Ptr + 44, 260, "UTF-16")
        low := StrLower(exe)
        if WatchNames.Has(low) {
            pid := NumGet(pe, 8, "UInt")
            seen[pid] := true
            if !Procs.Has(pid) {
                role := WatchNames[low]
                parent := NumGet(pe, 32, "UInt")
                kind := ProcKind(pid, role)
                Procs[pid] := {name: exe, role: role, parent: parent, kind: kind, tick: A_TickCount}
                AddEvent(role, (FirstProcPoll ? "Уже запущен " : "Запущен ") exe " (PID " pid
                    . (kind != "" ? ", тип: " kind : "") ")")
                if (role = "лаунчер" && kind = "главный") {
                    try {
                        path := ProcessGetPath(pid)
                        if (path != "" && path != LauncherExe) {
                            LauncherExe := path
                            IniWrite(LauncherExe, IniPath, "paths", "launcher")
                        }
                    }
                }
                if (role = "игра" && !FirstProcPoll) {
                    GameStartStamp := DateAdd(A_Now, -1, "Seconds")
                    GameLogPendingReset := true
                    GameSeenInRec := GameSeenInRec || Recording
                    AutoMark("запущен процесс игры bsgo.exe")
                }
            }
        }
        ok := DllCall("Process32NextW", "Ptr", snap, "Ptr", pe)
    }
    DllCall("CloseHandle", "Ptr", snap)

    for pid in KeysOf(Procs) {
        if seen.Has(pid)
            continue
        p := Procs[pid]
        AddEvent(p.role, "Завершён " p.name " (PID " pid ", работал " Format("{:.0f}", (A_TickCount - p.tick) / 1000) " с)")
        if (p.role = "игра") {
            AutoMark("процесс игры завершился")
            CopyGameLog("после выхода игры")
        }
        Procs.Delete(pid)
        if IoPrev.Has(pid)
            IoPrev.Delete(pid)
        if WinTitles.Has(pid)
            WinTitles.Delete(pid)
    }
    FirstProcPoll := false
}

; тип процесса Electron (главный / сетевой / gpu…) — из командной строки берём только --type
ProcKind(pid, role) {
    if (role != "лаунчер")
        return ""
    try {
        for proc in ComObjGet("winmgmts:").ExecQuery("SELECT CommandLine FROM Win32_Process WHERE ProcessId=" pid) {
            cmd := String(proc.CommandLine)
            if InStr(cmd, "NetworkService")
                return "сетевой"
            if RegExMatch(cmd, "--type=([\w-]+)", &m)
                return m[1]
            return "главный"
        }
    }
    return "?"
}

KeysOf(m) {
    arr := []
    for k in m
        arr.Push(k)
    return arr
}

; ==========================================================================
;  TCP / UDP
; ==========================================================================

Ip4Str(a) => (a & 0xFF) "." ((a >> 8) & 0xFF) "." ((a >> 16) & 0xFF) "." ((a >> 24) & 0xFF)
PortOf(p) => ((p & 0xFF) << 8) | ((p >> 8) & 0xFF)

Ip6Str(ptr) {
    out := Buffer(96, 0)
    DllCall("ntdll\RtlIpv6AddressToStringW", "Ptr", ptr, "Ptr", out)
    return StrGet(out, "UTF-16")
}

StateName(st) {
    static names := ["CLOSED", "LISTEN", "SYN_SENT", "SYN_RCVD", "ESTABLISHED", "FIN_WAIT1", "FIN_WAIT2"
        , "CLOSE_WAIT", "CLOSING", "LAST_ACK", "TIME_WAIT", "DELETE_TCB"]
    return (st >= 1 && st <= 12) ? names[st] : "?" st
}

EpStr(ip, port) => ip ":" port (IpNames.Has(ip) ? " (" IpNames[ip] ")" : "")

GetTable(fn, fam, cls) {
    size := 0
    DllCall("iphlpapi\" fn, "Ptr", 0, "UInt*", &size, "Int", 0, "UInt", fam, "Int", cls, "UInt", 0)
    if !size
        return 0
    buf := Buffer(size + 8192)
    size := buf.Size
    if DllCall("iphlpapi\" fn, "Ptr", buf, "UInt*", &size, "Int", 0, "UInt", fam, "Int", cls, "UInt", 0)
        return 0
    return buf
}

PollTcp() {
    global FirstTcpPoll
    now := A_TickCount
    seen := Map()
    buf := GetTable("GetExtendedTcpTable", 2, 5)        ; IPv4, TCP_TABLE_OWNER_PID_ALL
    if buf {
        loop NumGet(buf, 0, "UInt") {
            off := 4 + (A_Index - 1) * 24
            pid := NumGet(buf, off + 20, "UInt")
            if !Procs.Has(pid)
                continue
            rAddr := NumGet(buf, off + 12, "UInt")
            if (rAddr = 0 || (rAddr & 0xFF) = 127)
                continue
            SeeConn(seen, pid, Ip4Str(rAddr), PortOf(NumGet(buf, off + 16, "UInt"))
                , PortOf(NumGet(buf, off + 8, "UInt")), NumGet(buf, off, "UInt"), now)
        }
    }
    buf := GetTable("GetExtendedTcpTable", 23, 5)       ; IPv6
    if buf {
        loop NumGet(buf, 0, "UInt") {
            off := 4 + (A_Index - 1) * 56
            pid := NumGet(buf, off + 52, "UInt")
            if !Procs.Has(pid)
                continue
            if (NumGet(buf, off + 24, "Int64") = 0 && NumGet(buf, off + 32, "Int64") = 0)
                continue
            rip := Ip6Str(buf.Ptr + off + 24)
            if (rip = "::1")
                continue
            SeeConn(seen, pid, rip, PortOf(NumGet(buf, off + 44, "UInt"))
                , PortOf(NumGet(buf, off + 20, "UInt")), NumGet(buf, off + 48, "UInt"), now)
        }
    }

    for key in KeysOf(Conns) {
        if seen.Has(key)
            continue
        c := Conns[key]
        c.closed := now
        life := (now - c.first) / 1000
        if c.estab
            AddEvent(c.role, "Закрыто " EpStr(c.ip, c.port) " — жило " Format("{:.1f}", life) " с, путь: " c.states)
        else if (life < 1.0) {
            ; открылось и закрылось между двумя опросами — успех или отказ не различить
            AddEvent(c.role, "Короткое " EpStr(c.ip, c.port) " — пропало через " Format("{:.1f}", life) " с, установление не успели увидеть")
            EpGet(c).short++
        } else {
            AddEvent(c.role, "НЕ УСТАНОВЛЕНО " EpStr(c.ip, c.port) " — пропало через " Format("{:.1f}", life) " с, путь: " c.states)
            EpGet(c).failed++
        }
        ep := EpGet(c)
        if (life > ep.maxLife)
            ep.maxLife := life
        if Recording
            DoneConns.Push(c)
        Conns.Delete(key)
    }
    FirstTcpPoll := false
}

SeeConn(seen, pid, rip, rport, lport, st, now) {
    key := pid "|" lport "|" rip "|" rport
    seen[key] := true
    if !Conns.Has(key) {
        p := Procs[pid]
        c := {pid: pid, role: p.role, kind: p.kind, ip: rip, port: rport, lport: lport, state: st
            , first: now, stateTick: now, closed: 0, estab: false, synWarn: false, finWarn: false
            , stage: FirstTcpPoll ? "было до запуска наблюдателя" : CurrentStage, states: StateName(st)}
        Conns[key] := c
        AddEvent(c.role, (FirstTcpPoll ? "Уже открыто " : "Новое TCP → ") EpStr(rip, rport) "  [" StateName(st) "]"
            . (c.kind != "" ? "  (процесс: " c.kind ")" : ""))
        ep := EpGet(c)
        ep.count++
        if (st = 5) {
            c.estab := true
            ep.estab++
        }
    } else {
        c := Conns[key]
        if (c.state != st) {
            AddEvent(c.role, EpStr(c.ip, c.port) ": " StateName(c.state) " → " StateName(st)
                . " (через " Format("{:.1f}", (now - c.stateTick) / 1000) " с)")
            c.state := st
            c.stateTick := now
            c.states .= " > " StateName(st)
            if (st = 5 && !c.estab) {
                c.estab := true
                EpGet(c).estab++
            }
        }
    }
    ; FIN_WAIT1 дольше 3 с: мы закрыли соединение, а сервер не подтверждает — пакеты не доходят
    if (c.state = 6 && !c.finWarn && now - c.stateTick > 3000) {
        c.finWarn := true
        EpGet(c).finStuck++
        AddEvent(c.role, "ОБРЫВ? " EpStr(c.ip, c.port) " — сервер не подтверждает закрытие больше 3 с (FIN_WAIT1),"
            . " похоже, пакеты этого соединения теряются. До этого соединение жило "
            . Format("{:.1f}", (c.stateTick - c.first) / 1000) " с")
    }
    if (c.state = 3 && !c.synWarn && now - c.stateTick > 3000) {
        c.synWarn := true
        EpGet(c).synStuck++
        AddEvent(c.role, "НЕТ ОТВЕТА: " EpStr(c.ip, c.port) " — сервер не ответил на подключение больше 3 с (SYN_SENT)")
    }
}

EpGet(c) {
    key := c.role "|" c.ip "|" c.port
    if !Endpoints.Has(key)
        Endpoints[key] := {role: c.role, ip: c.ip, port: c.port, count: 0, estab: 0, failed: 0, short: 0, synStuck: 0, finStuck: 0
            , firstTick: Max(c.first, RecStartTick), stage: c.stage, maxLife: 0.0}
    return Endpoints[key]
}

PollUdp() {
    seen := Map()
    buf := GetTable("GetExtendedUdpTable", 2, 1)        ; IPv4, UDP_TABLE_OWNER_PID
    if buf {
        loop NumGet(buf, 0, "UInt") {
            off := 4 + (A_Index - 1) * 12
            pid := NumGet(buf, off + 8, "UInt")
            if !Procs.Has(pid)
                continue
            lip := NumGet(buf, off, "UInt")
            if ((lip & 0xFF) = 127)
                continue
            lport := PortOf(NumGet(buf, off + 4, "UInt"))
            key := pid "|" lport
            seen[key] := true
            if !UdpSeen.Has(key) {
                role := Procs[pid].role
                UdpSeen[key] := {pid: pid, role: role, lport: lport, first: A_TickCount, closed: 0, stage: CurrentStage}
                AddEvent(role, "UDP: открыт локальный порт " lport " (куда идут пакеты, Windows не показывает)")
            }
        }
    }
    for key in KeysOf(UdpSeen) {
        if seen.Has(key)
            continue
        u := UdpSeen[key]
        u.closed := A_TickCount
        AddEvent(u.role, "UDP: закрыт локальный порт " u.lport)
        if Recording
            UdpLog.Push(u)
        UdpSeen.Delete(key)
    }
}

; ==========================================================================
;  DNS
; ==========================================================================

ResolveKnownHosts() {
    for h in KnownHosts {
        if (h = "")
            continue
        n := QueryDns(h, 1, 0)
        if (n = 0)
            AddEvent("dns", h " — не удалось получить IP (DNS не ответил)")
    }
}

PollDnsCache() {
    p := 0
    if (!DllCall("dnsapi\DnsGetCacheDataTable", "Ptr*", &p, "Int") || !p)
        return
    names := []
    e := p
    while e {
        np := NumGet(e, 8, "Ptr")
        wt := NumGet(e, 16, "UShort")
        if (np && (wt = 1 || wt = 28))
            names.Push([StrGet(np, "UTF-16"), wt])
        nx := NumGet(e, 0, "Ptr")
        if np
            DllCall("dnsapi\DnsFree", "Ptr", np, "Int", 0)
        DllCall("dnsapi\DnsFree", "Ptr", e, "Int", 0)
        e := nx
    }
    now := A_TickCount
    for item in names {
        key := item[1] "|" item[2]
        if (DnsQueried.Has(key) && now - DnsQueried[key] < 60000)
            continue
        DnsQueried[key] := now
        QueryDns(item[1], item[2], 0x10)                ; 0x10 = только из кэша, без запроса в сеть
    }
}

QueryDns(name, qtype, flags) {
    found := 0
    rec := 0
    st := DllCall("dnsapi\DnsQuery_W", "WStr", name, "UShort", qtype, "UInt", flags, "Ptr", 0, "Ptr*", &rec, "Ptr", 0, "Int")
    if (st != 0 || !rec)
        return 0
    r := rec
    while r {
        rt := NumGet(r, 16, "UShort")
        ip := (rt = 1) ? Ip4Str(NumGet(r, 32, "UInt")) : (rt = 28) ? Ip6Str(r + 32) : ""
        if (ip != "") {
            NoteIpName(ip, name)
            found++
        }
        r := NumGet(r, 0, "Ptr")
    }
    DllCall("dnsapi\DnsFree", "Ptr", rec, "Int", 1)
    return found
}

NoteIpName(ip, name) {
    if IpNames.Has(ip) {
        if (InStr("," IpNames[ip] ",", "," name ",") || StrLen(IpNames[ip]) > 80)
            return
        IpNames[ip] := IpNames[ip] "," name
    } else
        IpNames[ip] := name
    ; в журнал — только имена игры и адреса, с которыми соединялись лаунчер или игра
    if (RegExMatch(name, "i)bsgo|bigpoint|playbsgo") || IpInUse(ip))
        AddEvent("dns", name " = " ip)
}

IpInUse(ip) {
    for key, c in Conns
        if (c.ip = ip)
            return true
    return false
}

; ==========================================================================
;  Файлы лаунчера и игры
; ==========================================================================

GameLogPath() {
    if (ArgGameLog != "")
        return ArgGameLog
    SplitPath(LauncherExe, , &launcherDir)
    return launcherDir "\client\live\bsgo_Data\output_log.txt"
}

PollToken() {
    global TokenStamp
    if !FileExist(TokenFile) {
        if (TokenStamp != "" && TokenStamp != "нет")
            AddEvent("лаунчер", "Файл сессии удалён (лаунчер закрыт или выход из аккаунта)")
        TokenStamp := "нет"
        return
    }
    mt := FileGetTime(TokenFile, "M")
    stamp := mt "|" FileGetSize(TokenFile)
    if (TokenStamp = "") {
        TokenStamp := stamp
        AddEvent("лаунчер", "Файл сессии последний раз обновлялся " FormatTime(mt, "dd.MM HH:mm:ss") " (содержимое не читается)")
        return
    }
    if (stamp != TokenStamp) {
        TokenStamp := stamp
        AddEvent("лаунчер", "ФАЙЛ СЕССИИ ОБНОВЛЁН — похоже, выполнен вход в аккаунт (содержимое не читается)")
        AutoMark("обновлён файл сессии лаунчера (вход в аккаунт)")
    }
}

; новые строки файла с прошлого раза (при первом вызове — с конца файла)
TailLines(path) {
    if !FileExist(path)
        return []
    size := FileGetSize(path)
    if !TailState.Has(path) {
        TailState[path] := {off: size, part: ""}
        return []
    }
    st := TailState[path]
    if (size < st.off) {
        st.off := 0
        st.part := ""
    }
    if (size = st.off)
        return []
    if (size - st.off > 4000000)
        st.off := size - 4000000
    try {
        f := FileOpen(path, "r", "UTF-8")
        f.Pos := st.off
        chunk := f.Read()
        st.off := f.Pos
        f.Close()
    } catch
        return []
    lines := StrSplit(st.part StrReplace(chunk, Chr(0xFEFF)), "`n")
    st.part := lines.Pop()
    out := []
    for ln in lines {
        ln := Trim(ln, "`r `t")
        if (ln != "")
            out.Push(ln)
    }
    return out
}

PollDiagLog() {
    for ln in TailLines(DiagLogFile)
        if (!InStr(ln, "[updater] Checking for update") && !InStr(ln, "is not available"))
            AddEvent("лаунчер-лог", Shorten(Redact(ln)))
}

PollGameLog() {
    global GameLogPendingReset
    path := GameLogPath()
    if !FileExist(path)
        return
    if GameLogPendingReset {
        ; ждём, пока новый запуск игры перезапишет лог — старые строки прошлой сессии не читаем
        if (FileGetTime(path, "M") < GameStartStamp)
            return
        TailState[path] := {off: 0, part: ""}
        GameLogPendingReset := false
        AddEvent("игра", "Лог игры начат заново новым запуском — читаю его с начала")
    }
    for ln in TailLines(path)
        HandleGameLine(ln)
}

HandleGameLine(ln) {
    for mk in GameMarkers {
        if InStr(ln, mk[1]) {
            AddEvent("игра", mk[2] "   |   " Shorten(Redact(ln)))
            if mk[3]
                AutoMark(mk[2])
            return
        }
    }
    if (RegExMatch(ln, GameErrorRx) && !RegExMatch(ln, GameNoiseRx)) {
        key := SubStr(RegExReplace(ln, "\d+", "#"), 1, 120)
        cnt := GameLineCount.Has(key) ? GameLineCount[key] + 1 : 1
        GameLineCount[key] := cnt
        if (cnt <= 3)
            AddEvent("игра!", Shorten(Redact(ln)) (cnt = 3 ? "   (дальше одинаковые строки не показываю)" : ""))
    }
}

CopyGameLog(reason) {
    global GameLogCopies
    if !Recording
        return
    src := GameLogPath()
    if (!FileExist(src) || FileGetTime(src, "M") < RecStartStamp || !GameSeenInRec && ArgGameLog = "")
        return
    GameLogCopies++
    dst := RecDir "\лог_игры_" Format("{:02}", GameLogCopies) ".txt"
    try FileCopy(src, dst, 1)
    catch {
        try FileAppend(FileRead(src, "UTF-8"), dst, "UTF-8")
    }
    if FileExist(dst)
        AddEvent("запись", "Сохранена копия лога игры (" reason "): " dst)
}

; ==========================================================================
;  Диск, окна, Запрет
; ==========================================================================

PollIo() {
    io := Buffer(48, 0)
    now := A_TickCount
    for pid, p in Procs {
        h := DllCall("OpenProcess", "UInt", 0x1000, "Int", 0, "UInt", pid, "Ptr")
        if !h
            continue
        ok := DllCall("GetProcessIoCounters", "Ptr", h, "Ptr", io)
        DllCall("CloseHandle", "Ptr", h)
        if !ok
            continue
        rd := NumGet(io, 24, "Int64"), wr := NumGet(io, 32, "Int64"), ot := NumGet(io, 40, "Int64")
        if IoPrev.Has(pid) {
            prev := IoPrev[pid]
            if !IoAcc.Has(p.role)
                IoAcc[p.role] := {r: 0, w: 0, o: 0, t0: now}
            acc := IoAcc[p.role]
            acc.r += rd - prev.r
            acc.w += wr - prev.w
            acc.o += ot - prev.o
        }
        IoPrev[pid] := {r: rd, w: wr, o: ot}
    }
    global FileCheckActive
    for role, acc in IoAcc {
        if (now - acc.t0 < 5000)
            continue
        if ((acc.r + acc.w) / 1048576 >= 3)
            AddEvent(role, Format("Диск: прочитано {:.1f} МБ, записано {:.1f} МБ, прочий обмен {:.1f} МБ за {:.0f} с"
                , acc.r / 1048576, acc.w / 1048576, acc.o / 1048576, (now - acc.t0) / 1000))
        ; проверка файлов = лаунчер читает сотни МБ (файлы игры) за несколько секунд
        if (role = "лаунчер") {
            big := acc.r / 1048576 >= FILECHECK_MB
            if (big && !FileCheckActive) {
                FileCheckActive := true
                AddEvent("лаунчер", "ПРОВЕРКА ФАЙЛОВ идёт (лаунчер читает файлы игры)")
                AutoMark("проверка файлов началась (чтение диска)")
            } else if (!big && FileCheckActive) {
                FileCheckActive := false
                AddEvent("лаунчер", "Проверка файлов закончилась (чтение диска прекратилось)")
                AutoMark("проверка файлов закончилась")
            }
        }
        acc.r := 0, acc.w := 0, acc.o := 0, acc.t0 := now
    }
}

PollWindows() {
    for pid, p in Procs {
        titles := ""
        try {
            for hwnd in WinGetList("ahk_pid " pid) {
                t := WinGetTitle(hwnd)
                if (t != "" && !InStr(titles, t))
                    titles .= (titles = "" ? "" : " | ") t
            }
        }
        old := WinTitles.Has(pid) ? WinTitles[pid] : ""
        if (titles != old) {
            WinTitles[pid] := titles
            if (titles != "") {
                AddEvent(p.role, "Окно: «" titles "»")
                if (p.role = "лаунчер")
                    AutoMark("окно лаунчера: «" titles "»")
            }
            else
                AddEvent(p.role, "Окно скрыто или закрыто")
        }
    }
}

PollZapret() {
    global ZapretOn
    on := ProcessExist("winws.exe") ? 1 : 0
    if (on != ZapretOn) {
        AddEvent("запрет", on ? "winws.exe работает (Запрет включён)" : "winws.exe не запущен (Запрет выключен)")
        ZapretOn := on
    }
}

; ==========================================================================
;  Запись: начало и конец
; ==========================================================================

StartRec(*) {
    global Recording, RecDir, RecStartTick, RecStartStamp, CurrentStage, Endpoints, DoneConns, StageMarks
    global UdpLog, GameSeenInRec, GameLogCopies, FileCheckActive
    if Recording
        return
    RecDir := A_ScriptDir "\records\" FormatTime(, "yyyy-MM-dd_HH-mm-ss")
    DirCreate(RecDir)
    Endpoints := Map(), DoneConns := [], StageMarks := [], UdpLog := []
    PendingLines.Length := 0
    GameSeenInRec := false, GameLogCopies := 0, FileCheckActive := false
    CurrentStage := "0. до отметок"
    RecStartTick := A_TickCount
    RecStartStamp := A_Now
    Recording := true
    for key, c in Conns {
        c.stage := "было до начала записи"
        EpGet(c).count++
        if c.estab
            EpGet(c).estab++
    }
    BtnStart.Enabled := false
    BtnStop.Enabled := true
    WriteInfo()
    AddEvent("запись", "Запись начата → " RecDir)
    ; исходное состояние — в журнал
    AddEvent("запрет", ProcessExist("winws.exe") ? "winws.exe работает (Запрет включён)" : "winws.exe не запущен (Запрет выключен)")
    if FileExist(TokenFile)
        AddEvent("лаунчер", "Файл сессии последний раз обновлялся " FormatTime(FileGetTime(TokenFile, "M"), "dd.MM HH:mm:ss"))
    else
        AddEvent("лаунчер", "Файла сессии нет (в лаунчер не входили или вышли из аккаунта)")
    if !Procs.Count
        AddEvent("процесс", "Лаунчер и игра сейчас не запущены")
    for pid, p in Procs
        AddEvent(p.role, "Уже запущен " p.name " (PID " pid (p.kind != "" ? ", тип: " p.kind : "") ")")
    for key, c in Conns
        AddEvent(c.role, "Уже открыто " EpStr(c.ip, c.port) "  [" StateName(c.state) "]")
    for pid, p in Procs
        if (p.role = "игра")
            GameSeenInRec := true
    SetTimer(ResolveKnownHosts, -10)
}

StopRecClick(*) => StopRec(false)

StopRec(silent) {
    global Recording
    if !Recording
        return
    AddEvent("запись", "Запись остановлена")
    now := A_TickCount
    CopyGameLog("при остановке записи")
    FlushJournal()
    try WriteSummary(now)
    catch as e
        ReportError("сводка", e)
    try WriteConnsTsv(now)
    catch as e
        ReportError("таблица", e)
    Recording := false
    BtnStart.Enabled := true
    BtnStop.Enabled := false
    if !silent {
        MsgBox("Запись сохранена в папку:`n" RecDir "`n`nГлавное — файлы «сводка.txt» и «журнал.txt».", "Наблюдатель BSGO Nova", "Iconi")
        Run('explorer.exe "' RecDir '"')
    }
}

WriteInfo() {
    out := "Наблюдатель BSGO Nova " WATCHER_VERSION "`r`n"
    out .= "Начало записи: " FormatTime(, "yyyy-MM-dd HH:mm:ss") "`r`n"
    out .= "Windows: " A_OSVersion (A_Is64bitOS ? " 64-бит" : " 32-бит") "`r`n"
    out .= "Лаунчер: " LauncherExe (FileExist(LauncherExe) ? "" : "  (файл не найден)") "`r`n"
    out .= "Лог игры: " GameLogPath() "`r`n"
    out .= "Запрет (winws.exe): " (ProcessExist("winws.exe") ? "работает" : "не запущен") "`r`n"
    out .= "Наблюдаемые программы: "
    for nm, role in WatchNames
        out .= nm " (" role ")  "
    out .= "`r`nПроцессы на момент начала:`r`n"
    for pid, p in Procs
        out .= "  " p.name " PID " pid (p.kind != "" ? " (" p.kind ")" : "") "`r`n"
    out .= "`r`nЗаписывается: соединения процессов лаунчера и игры, DNS-имена этих адресов, время изменения файла сессии,"
    out .= "`r`nстроки-маркеры лога игры, строки диагностического лога лаунчера (с вырезанными токенами и почтами)."
    out .= "`r`nНЕ записывается: пароли, токены, содержимое файла сессии, командная строка игры.`r`n"
    out .= "Внимание: копии лога игры содержат имя вашего персонажа.`r`n"
    FileAppend(out, RecDir "\сведения.txt", "UTF-8")
}

WriteSummary(now) {
    nl := "`r`n"
    out := "СВОДКА ЗАПИСИ " FormatTime(RecStartStamp, "yyyy-MM-dd HH:mm:ss") ", длительность " Format("{:.0f}", (now - RecStartTick) / 1000) " с" nl
    out .= "Запрет (winws.exe) в конце записи: " (ZapretOn = 1 ? "работает" : "не запущен") nl nl

    out .= "== Этапы: ваши отметки и автоматические признаки ==" nl
    if !StageMarks.Length
        out .= "  (отметок нет)" nl
    for m in StageMarks
        out .= Format("{:9}", RelTime(m.tick)) "  " m.text nl

    ; соединения, открытые до конца записи, тоже учитываем в «дольше всех жило»
    for key, c in Conns {
        ep := EpGet(c)
        if ((now - c.first) / 1000 > ep.maxLife)
            ep.maxLife := (now - c.first) / 1000
    }

    ; сортировка адресов по времени первого появления
    list := ""
    for key, ep in Endpoints
        list .= Format("{:012}", ep.firstTick - RecStartTick + 100000000) "`t" key "`n"
    list := Sort(RTrim(list, "`n"))

    warn := ""
    out .= nl "== Адреса по порядку появления ==" nl
    out .= "(«не установлено» — соединение пропало, так и не получив ответа сервера; «ждали > 3 с» — сервер долго не отвечал)" nl
    if (list = "")
        out .= "  (соединений не было)" nl
    for row in StrSplit(list, "`n") {
        if (row = "")
            continue
        ep := Endpoints[StrSplit(row, "`t")[2]]
        host := IpNames.Has(ep.ip) ? IpNames[ep.ip] : "имя неизвестно"
        out .= nl "[" ep.role "] " ep.ip ":" ep.port "   " host nl
        out .= "    впервые " RelTime(ep.firstTick) ", этап: " ep.stage nl
        out .= "    соединений: " ep.count ", установлено: " ep.estab ", НЕ установлено: " ep.failed
            . ", короткие (не различить): " ep.short ", ждали ответа > 3 с: " ep.synStuck
            . ", обрыв при закрытии (FIN_WAIT1 > 3 с): " ep.finStuck ", дольше всех жило: " Format("{:.1f}", ep.maxLife) " с" nl
        if KnownHarmless.Has(ep.ip)
            out .= "    известно: " KnownHarmless[ep.ip] nl
        else if (ep.failed || ep.synStuck || ep.finStuck)
            warn .= "  " ep.role ": " ep.ip ":" ep.port " (" host ") — не установлено " ep.failed
                . ", долгое ожидание ответа " ep.synStuck ", обрыв при закрытии " ep.finStuck nl
    }

    out .= nl "== UDP: локальные порты, открытые лаунчером или игрой ==" nl
    udpAll := []
    for u in UdpLog
        udpAll.Push(u)
    for key, u in UdpSeen
        udpAll.Push(u)
    if !udpAll.Length
        out .= "  (не было)" nl
    for u in udpAll
        out .= "  [" u.role "] порт " u.lport ", открыт " RelTime(Max(u.first, RecStartTick)) (u.closed ? ", закрыт " RelTime(u.closed) : ", открыт до конца") ", этап: " u.stage nl

    out .= nl "== Докуда дошли (по автоматическим признакам) ==" nl
    stepsAll := [["обновлён файл сессии", "1) вход в аккаунт лаунчера"]
        , ["проверка файлов началась", "2) проверка файлов"]
        , ["запущен процесс игры", "3) запуск игры"]
        , ["игровой сервер принял вход", "4) игровой сервер принял вход (порт 27050)"]
        , ["получены данные своего корабля", "5) получены данные мира"]
        , ["ВХОД В МИР", "6) вход в мир"]]
    reached := 0
    for i, step in stepsAll
        for m in StageMarks
            if InStr(m.text, step[1]) {
                reached := i
                break
            }
    for i, step in stepsAll
        out .= "  " (i <= reached ? "[да]  " : "[нет] ") step[2] nl
    if (reached < stepsAll.Length)
        out .= "  → Остановились после этапа «" (reached ? stepsAll[reached][2] : "запуск лаунчера") "»." nl

    out .= nl "== На что обратить внимание ==" nl
    out .= (warn != "") ? warn : "  Неудачных соединений не замечено." nl
    out .= nl "Подробности по секундам — в «журнал.txt», каждое соединение — в «соединения.tsv» (открывается в Excel)." nl
    FileAppend(out, RecDir "\сводка.txt", "UTF-8")
}

WriteConnsTsv(now) {
    t := "`t"
    out := "роль" t "процесс" t "PID" t "IP" t "порт" t "имя" t "лок.порт" t "начало" t "конец" t "жило, с" t "установлено" t "состояния" t "этап`r`n"
    all := []
    for c in DoneConns
        all.Push(c)
    for key, c in Conns
        all.Push(c)
    for c in all {
        endTick := c.closed ? c.closed : now
        out .= c.role t c.kind t c.pid t c.ip t c.port t (IpNames.Has(c.ip) ? IpNames[c.ip] : "") t c.lport
            . t RelTime(Max(c.first, RecStartTick)) t (c.closed ? RelTime(c.closed) : "открыто") t Format("{:.1f}", (endTick - c.first) / 1000)
            . t (c.estab ? "да" : "НЕТ") t c.states t c.stage "`r`n"
    }
    FileAppend(out, RecDir "\соединения.tsv", "UTF-8")
}

SelfTestEnd() {
    StopRec(true)
    ExitApp()
}

; ==========================================================================
;  Кнопки и окно
; ==========================================================================

MarkClick(i, *) => DoMark(i)
MarkHotkey(i, *) => DoMark(i)

DoMark(i) {
    global CurrentStage
    if (i = 10) {
        ib := InputBox("Коротко опишите, что сейчас происходит:", "Заметка", "w440 h130")
        if (ib.Result != "OK" || Trim(ib.Value) = "")
            return
        AddEvent("ЗАМЕТКА", Trim(ib.Value))
        if Recording
            StageMarks.Push({tick: A_TickCount, text: "заметка: " Trim(ib.Value)})
        return
    }
    CurrentStage := MarkTexts[i]
    if Recording
        StageMarks.Push({tick: A_TickCount, text: MarkTexts[i]})
    AddEvent("ОТМЕТКА", MarkTexts[i])
    if !Recording {
        ToolTip("Запись не идёт — отметка не сохранится. Нажмите «Начать запись».")
        SetTimer(() => ToolTip(), -3000)
    }
}

LaunchLauncher(*) {
    global LauncherExe
    if !FileExist(LauncherExe) {
        sel := FileSelect(1, "C:\Games", "Где находится BSGO Launcher.exe?", "Лаунчер (*.exe)")
        if (sel = "")
            return
        LauncherExe := sel
        IniWrite(LauncherExe, IniPath, "paths", "launcher")
    }
    for pid, p in Procs {
        if (p.role = "лаунчер") {
            ans := MsgBox("Лаунчер уже запущен. Для чистой записи этапа «Соединено» закройте его полностью"
                . " (и в трее возле часов), затем нажмите эту кнопку снова.`n`nВсё равно продолжить?", "Лаунчер уже запущен", "YesNo Icon!")
            if (ans != "Yes")
                return
            break
        }
    }
    SplitPath(LauncherExe, , &launcherDir)
    Run('"' LauncherExe '"', launcherDir)
    AddEvent("запуск", "Запущен лаунчер: " LauncherExe)
    if Recording
        StageMarks.Push({tick: A_TickCount, text: "[авто] наблюдатель запустил лаунчер"})
}

OpenRecords(*) {
    dir := A_ScriptDir "\records"
    DirCreate(dir)
    Run('explorer.exe "' dir '"')
}

GuiResized(g, minMax, w, h) {
    if (minMax = -1)
        return
    EventsLV.GetPos(, &ly)
    EventsLV.Move(, , w - 20, h - ly - 10)
    EventsLV.ModifyCol(3, w - 20 - 85 - 80 - 25)
}

GuiClosed(*) {
    if Recording {
        ans := MsgBox("Идёт запись. Сохранить её и выйти?", "Наблюдатель BSGO Nova", "YesNoCancel Icon?")
        if (ans = "Cancel")
            return true
        if (ans = "Yes")
            StopRec(true)
    }
    ExitApp()
}
