; ==========================================================================
;  Сетевые проверки: DNS, TCP, HTTPS (curl), «движок лаунчера» (Node внутри лаунчера),
;  «движок Chromium» (Edge без окна). Проверены на BSGO Nova 2026-10-16.
; ==========================================================================

global CurlExe := A_WinDir "\System32\curl.exe"
global RANGE_BYTES := 2097152
global REPEATS := 3
global TmpCurl := A_Temp "\bsgo_tester_curl.txt"
global TmpNode := A_Temp "\bsgo_tester_node.txt"
global NodeScript := A_Temp "\bsgo_tester_check.js"
global EdgeExe := FileExist(A_ProgramFiles " (x86)\Microsoft\Edge\Application\msedge.exe")
    ? A_ProgramFiles " (x86)\Microsoft\Edge\Application\msedge.exe" : A_ProgramFiles "\Microsoft\Edge\Application\msedge.exe"
global EdgeReliable := false
global CurlReliable := true
global NodeReliable := true

; работает ли в лаунчере режим Node (ELECTRON_RUN_AS_NODE)? Если в новой версии его отключат,
; вместо проверки откроется обычный лаунчер — ждём не дольше 10 с и закрываем его
LauncherEngineSelfTest() {
    if !(IsElectron && FileExist(LauncherExe))
        return false
    js := A_Temp "\bsgo_tester_selftest.js", out := A_Temp "\bsgo_tester_selftest.txt"
    try FileDelete(out)
    WriteRaw(js, "require('fs').writeFileSync(process.argv[2], 'ok ' + process.versions.node)")
    EnvSet("ELECTRON_RUN_AS_NODE", "1")
    Run('"' LauncherExe '" "' js '" "' out '"', , "Hide", &pid)
    EnvSet("ELECTRON_RUN_AS_NODE")
    deadline := A_TickCount + 10000
    while (ProcessExist(pid) && A_TickCount < deadline)
        Sleep(100)
    if ProcessExist(pid)
        RunWait("taskkill /T /F /PID " pid, , "Hide")
    return FileExist(out) && InStr(FileRead(out), "ok ") = 1
}

; curl есть и запускается? Проверка без сети: чтение локального файла через file://
; (у некоторых игроков curl отсутствует или его блокирует антивирус — тогда его результаты не учитываем)
CurlSelfTest() {
    if !FileExist(CurlExe)
        return false
    r := RunCurl("--max-time 5", "file:///" StrReplace(A_WinDir, "\", "/") "/win.ini")
    return r.exit = 0 && r.size > 0
}

; ---------- curl (встроенный в Windows, работает через Schannel) ----------
RunCurl(extra, url) {
    try FileDelete(TmpCurl)
    fmt := "%output{" TmpCurl "}%{http_code}|%{size_download}|%{time_total}|%{remote_ip}|%{errormsg}"
    exitCode := RunWait('"' CurlExe '" --noproxy "*" --ssl-no-revoke -s -o NUL ' extra ' -w "' fmt '" "' url '"', , "Hide")
    raw := FileExist(TmpCurl) ? Trim(FileRead(TmpCurl, "UTF-8"), "`r`n ") : ""
    p := StrSplit(raw, "|", , 5)
    while (p.Length < 5)
        p.Push("")
    return {exit: exitCode, http: p[1], size: IsNumber(p[2]) ? Integer(p[2]) : 0
        , time: IsNumber(p[3]) ? Float(p[3]) : 0.0, ip: p[4], err: p[5]}
}

; адрес большой загрузки: у Nova — первые 2 МБ установщика лаунчера (имя из latest.yml), иначе главная страница
ResolveBigUrl() {
    global BigUrl
    if !IsNova() {
        BigUrl := SiteUrl()
        return true
    }
    tmpYml := A_Temp "\bsgo_tester_latest.yml"
    try FileDelete(tmpYml)
    RunWait('"' CurlExe '" --noproxy "*" -s --max-time 15 -o "' tmpYml '" "' SmallUrl() '"', , "Hide")
    if (FileExist(tmpYml) && RegExMatch(FileRead(tmpYml, "UTF-8"), "m)^path:\s*(.+?)\s*$", &m)) {
        BigUrl := "https://playbsgo.com/download/" StrReplace(m[1], " ", "%20")
        CfgSet("server", "installer_url", BigUrl)
        return true
    }
    if (BigUrl = "")
        BigUrl := "https://playbsgo.com/download/BSGO%20Launcher%20Setup%201.0.81.exe"
    return false
}

BigIsRange() => IsNova()
BigNeed() => BigIsRange() ? RANGE_BYTES : 1
BigCurlArgs() => "--connect-timeout 8 --max-time 30 --speed-limit 1 --speed-time 6" (BigIsRange() ? " -r 0-" (RANGE_BYTES - 1) : "")

; ---------- TCP без отправки данных ----------
TcpConnect(ip, port, timeoutMs) {
    static wsaData := 0
    if !wsaData {
        wsaData := Buffer(408, 0)
        DllCall("ws2_32\WSAStartup", "UShort", 0x0202, "Ptr", wsaData)
    }
    sock := DllCall("ws2_32\socket", "Int", 2, "Int", 1, "Int", 6, "Ptr")
    if (sock = -1)
        return false
    nonBlocking := 1
    DllCall("ws2_32\ioctlsocket", "Ptr", sock, "Int", 0x8004667E, "UInt*", &nonBlocking)
    addr := Buffer(16, 0)
    NumPut("UShort", 2, addr, 0)
    NumPut("UShort", DllCall("ws2_32\htons", "UShort", port, "UShort"), addr, 2)
    NumPut("UInt", DllCall("ws2_32\inet_addr", "AStr", ip, "UInt"), addr, 4)
    DllCall("ws2_32\connect", "Ptr", sock, "Ptr", addr, "Int", 16)
    wset := Buffer(16, 0), eset := Buffer(16, 0), tv := Buffer(8, 0)
    NumPut("UInt", 1, wset, 0), NumPut("Ptr", sock, wset, 8)
    NumPut("UInt", 1, eset, 0), NumPut("Ptr", sock, eset, 8)
    NumPut("Int", timeoutMs // 1000, tv, 0), NumPut("Int", Mod(timeoutMs, 1000) * 1000, tv, 4)
    n := DllCall("ws2_32\select", "Int", 0, "Ptr", 0, "Ptr", wset, "Ptr", eset, "Ptr", tv, "Int")
    ok := n > 0 && NumGet(wset, 0, "UInt") = 1 && NumGet(eset, 0, "UInt") = 0
    DllCall("ws2_32\closesocket", "Ptr", sock)
    return ok
}

; ---------- DNS: системный и DNS-over-HTTPS (Cloudflare) ----------
DnsSystem(name) {
    rec := 0
    if (DllCall("dnsapi\DnsQuery_W", "WStr", name, "UShort", 1, "UInt", 0x8, "Ptr", 0, "Ptr*", &rec, "Ptr", 0, "Int") != 0 || !rec)
        return ""
    ip := "", r := rec
    while r {
        if (NumGet(r, 16, "UShort") = 1) {
            a := NumGet(r, 32, "UInt")
            ip := (a & 0xFF) "." ((a >> 8) & 0xFF) "." ((a >> 16) & 0xFF) "." ((a >> 24) & 0xFF)
            break
        }
        r := NumGet(r, 0, "Ptr")
    }
    DllCall("dnsapi\DnsFree", "Ptr", rec, "Int", 1)
    return ip
}

; JSON-сервисы DNS по обычному HTTPS (встроенный в curl режим --doh-url на Windows не работает)
DnsDoh(name) {
    tmp := A_Temp "\bsgo_tester_doh.txt"
    for url in ["https://cloudflare-dns.com/dns-query?name=" name "&type=A", "https://dns.google/resolve?name=" name "&type=A"] {
        try FileDelete(tmp)
        RunWait('"' CurlExe '" --noproxy "*" -s --max-time 10 -H "accept: application/dns-json" -o "' tmp '" "' url '"', , "Hide")
        if FileExist(tmp) && RegExMatch(FileRead(tmp, "UTF-8"), '"type":1,"TTL":\d+,"data":"(\d{1,3}(?:\.\d{1,3}){3})"', &m)
            return m[1]
    }
    return ""
}

; ---------- «движок лаунчера»: Node внутри Electron-лаунчера (ELECTRON_RUN_AS_NODE) ----------
WriteNodeScript() {
    js := "
    (
const https = require('https'), fs = require('fs');
const [, , url, rangeEnd, stallMs, outFile] = process.argv;
const t0 = Date.now(); let n = 0, last = Date.now(), done = false;
function fin(kind, extra) {
  if (done) return; done = true;
  fs.writeFileSync(outFile, kind + '|' + n + '|' + (Date.now() - t0) + '|' + (extra || ''));
  process.exit(0);
}
const opt = { headers: {} };
if (+rangeEnd > 0) opt.headers.Range = 'bytes=0-' + rangeEnd;
const req = https.get(url, opt, res => {
  res.on('data', c => { n += c.length; last = Date.now(); });
  res.on('end', () => fin('ok', 'HTTP ' + res.statusCode));
});
req.on('error', e => fin(n > 0 ? 'stall' : 'fail', e.code || e.message));
setInterval(() => { if (Date.now() - last > +stallMs) { req.destroy(); fin(n > 0 ? 'stall' : 'fail', 'no data ' + stallMs + ' ms'); } }, 250);
setTimeout(() => { req.destroy(); fin(n > 0 ? 'stall' : 'fail', 'timeout'); }, 30000);
    )"
    f := FileOpen(NodeScript, "w", "UTF-8-RAW")
    f.Write(js)
    f.Close()
}

RunLauncherEngine(url, rangeEnd) {
    try FileDelete(TmpNode)
    EnvSet("ELECTRON_RUN_AS_NODE", "1")
    RunWait('"' LauncherExe '" "' NodeScript '" "' url '" ' rangeEnd ' 6000 "' TmpNode '"', , "Hide")
    EnvSet("ELECTRON_RUN_AS_NODE")
    raw := FileExist(TmpNode) ? FileRead(TmpNode, "UTF-8") : "fail|0|0|no output"
    p := StrSplit(raw, "|", , 4)
    while (p.Length < 4)
        p.Push("")
    return {exit: p[1] = "ok" ? 0 : 1, size: IsNumber(p[2]) ? Integer(p[2]) : 0
        , time: IsNumber(p[3]) ? Integer(p[3]) / 1000 : 0.0, err: p[4], ip: ""}
}

; ---------- «движок Chromium»: Edge без окна (как статус «Соединено» в лаунчере) ----------
; 1 — страница пришла целиком, 0 — нет, -1 — нет Edge, -2 — не проверялось
EdgeCheck(url) {
    if !FileExist(EdgeExe)
        return -1
    stamp := A_TickCount
    profile := A_Temp "\bsgo_edge_" stamp
    outFile := A_Temp "\bsgo_edge_out_" stamp ".txt"
    doneFile := A_Temp "\bsgo_edge_done_" stamp ".txt"
    args := '/c ""' EdgeExe '" --headless=new --disable-gpu --no-first-run --no-default-browser-check'
        . ' --no-proxy-server --user-data-dir="' profile '" --dump-dom "' url '" > "' outFile '" 2>NUL & echo done> "' doneFile '""'
    ; от администратора Edge не работает — запускаем от обычного пользователя
    if A_IsAdmin
        ShellRun(A_ComSpec, args, A_Temp, "", 0)
    else
        Run(A_ComSpec " " args, A_Temp, "Hide")
    deadline := A_TickCount + 15000
    while (!FileExist(doneFile) && A_TickCount < deadline)
        Sleep(200)
    KillEdgeProfile(profile)
    Sleep(200)
    txt := FileExist(outFile) ? FileRead(outFile, "UTF-8") : ""
    try FileDelete(outFile)
    try FileDelete(doneFile)
    try DirDelete(profile, true)
    ; у Nova подвал страницы начинается после ~15,6 КБ — при обрыве на 15 КБ его не будет
    if IsNova() || InStr(url, "file:///")
        return (InStr(txt, "BSGO") && InStr(txt, "<footer")) ? 1 : 0
    return InStr(txt, "<body") ? 1 : 0
}

EdgeSelfTest() {
    if !FileExist(EdgeExe)
        return false
    page := A_Temp "\bsgo_edge_selftest.html"
    try FileDelete(page)
    FileAppend("<html><head><title>BSGO selftest</title></head><body><p>ok</p><footer>end</footer></body></html>", page, "UTF-8")
    ok := EdgeCheck("file:///" StrReplace(page, "\", "/")) = 1
    try FileDelete(page)
    return ok
}

KillEdgeProfile(profile) {
    loop 3 {
        found := false
        for proc in ComObjGet("winmgmts:").ExecQuery("SELECT ProcessId, CommandLine FROM Win32_Process WHERE Name='msedge.exe'") {
            try {
                if InStr(String(proc.CommandLine), profile) {
                    ProcessClose(proc.ProcessId)
                    found := true
                }
            }
        }
        if !found
            return
        Sleep(300)
    }
}

; запуск без прав администратора из процесса с правами (через рабочий стол Explorer)
ShellRun(prms*) {
    shellWindows := ComObject("Shell.Application").Windows
    desktop := shellWindows.FindWindowSW(0, 0, 8, 0, 1)                  ; SWC_DESKTOP, SWFO_NEEDDISPATCH
    tlb := ComObjQuery(desktop, "{4C96BE40-915C-11CF-99D3-00AA004AE837}"  ; SID_STopLevelBrowser
        , "{000214E2-0000-0000-C000-000000000046}")                       ; IID_IShellBrowser
    ComCall(15, tlb, "ptr*", sv := ComValue(13, 0))                       ; IShellBrowser.QueryActiveShellView
    NumPut("int64", 0x20400, "int64", 0x46000000000000C0, iidDispatch := Buffer(16))
    ComCall(15, sv, "uint", 0, "ptr", iidDispatch, "ptr*", sfvd := ComValue(9, 0))  ; IShellView.GetItemObject
    sfvd.Application.ShellExecute(prms*)
}

; ---------- повторы загрузки: повторяем, только пока проходит ----------
Attempts(fn, need) {
    a := {ok: 0, n: 0, maxTime: 0.0, firstFail: "", ip: "", stallKb: 0.0}
    loop REPEATS {
        b := fn()
        a.n++
        if (b.ip != "")
            a.ip := b.ip
        if (b.exit = 0 && b.size >= need) {
            a.ok++
            a.maxTime := Max(a.maxTime, b.time)
        } else {
            if (a.firstFail = "") {
                a.firstFail := b.size > 0 ? Format(T("stalled_at"), b.size / 1024) : T("no_answer")
                a.stallKb := b.size / 1024
            }
            if (A_Index = 1)
                break
        }
    }
    return a
}

AttemptsText(a) {
    if !IsObject(a) || (a.n = 0)
        return "—"
    if (a.ok = a.n)
        return Format(T("attempts_ok"), a.ok, a.n, a.maxTime)
    return a.ok "/" a.n " " a.firstFail
}

EdgeText(e) => e = 1 ? T("ok") : e = 0 ? T("no") : e = -1 ? T("no_edge") : T("not_checked")

; ---------- полный набор проверок сети ----------
RunNetChecks() {
    r := {}
    r.dnsSys := DnsSystem(Host)
    r.dnsDoh := DnsDoh(Host)
    r.ip := r.dnsSys != "" ? r.dnsSys : r.dnsDoh
    r.tcp443 := r.ip != "" && TcpConnect(r.ip, 443, 4000)
    if CurlReliable {
        r.small := RunCurl("--connect-timeout 8 --max-time 15 --speed-limit 1 --speed-time 6", SmallUrl())
        r.smallOk := r.small.exit = 0 && r.small.http != "" && r.small.http != "000"
        r.curl := Attempts(() => RunCurl(BigCurlArgs(), BigUrl), BigNeed())
    } else {
        r.small := {exit: -1, http: "", size: 0, time: 0.0, ip: "", err: T("not_checked")}
        r.smallOk := false
        r.curl := ""
    }
    r.node := (NodeReliable && IsElectron && FileExist(LauncherExe))
        ? Attempts(() => RunLauncherEngine(BigUrl, BigIsRange() ? RANGE_BYTES - 1 : 0), BigNeed()) : ""
    r.edge := EdgeReliable ? EdgeCheck(SiteUrl()) : -2
    ; главный судья уровня лаунчера — движок самого лаунчера; curl — только если лаунчер не Electron
    r.main := IsObject(r.node) ? r.node : r.curl
    serverIp := GameIp(r.ip)
    r.ports := Map()
    for port in GamePorts
        r.ports[port] := (serverIp != "") && TcpConnect(serverIp, port, 3000)
    return r
}

; итог уровня лаунчера: ok | chromium | partial | stall | noanswer | unknown
LauncherLevel(r) {
    a := r.main
    if !IsObject(a)
        return "unknown"
    if (a.ok = a.n)
        return r.edge = 0 ? "chromium" : "ok"
    if (a.ok > 0)
        return "partial"
    return a.stallKb > 0 ? "stall" : "noanswer"
}

; curl не прошёл, а движок лаунчера прошёл — на лаунчер не влияет, но стоит показать
CurlDiffers(r) => IsObject(r.curl) && IsObject(r.node) && r.node.ok = r.node.n && r.curl.ok != r.curl.n

PortsText(ports) {
    out := ""
    for port, ok in ports
        out .= (out = "" ? "" : ", ") port " " (ok ? T("ok") : T("no"))
    return out
}

PortsAllOk(ports) {
    for port, ok in ports
        if !ok
            return false
    return ports.Count > 0
}
