; ==========================================================================
;  Тексты интерфейса и отчётов: русский / английский.
;  T("ключ") — строка на выбранном языке; если её нет — русская; если и её нет — сам ключ.
; ==========================================================================

global Lang := IniRead(A_ScriptDir "\tester.ini", "ui", "lang", "ru")
global Strings := Map("ru", Map(), "en", Map())

T(key) {
    if Strings[Lang].Has(key)
        return Strings[Lang][key]
    return Strings["ru"].Has(key) ? Strings["ru"][key] : key
}

S(key, ru, en) {
    Strings["ru"][key] := ru
    Strings["en"][key] := en
}

; ---------- окно ----------
S("app_title", "BSGO Connection Doctor", "BSGO Connection Doctor")
S("intro", "Проверяет, почему BSGO не подключается, и подбирает стратегию Запрета. Пароли и токены не читаются."
    , "Finds out why BSGO cannot connect and picks a Zapret strategy. Passwords and tokens are never read.")
S("lang_btn", "English", "Русский")
S("game_group", "Игра", "Game")
S("zapret_group", "Запрет (zapret-discord-youtube)", "Zapret (zapret-discord-youtube)")
S("btn_game_folder", "Папка игры…", "Game folder…")
S("btn_zapret_folder", "Папка Запрета…", "Zapret folder…")
S("btn_diag", "1. Диагностика (~1–2 мин)", "1. Diagnostics (~1–2 min)")
S("btn_pick", "2. Подбор стратегии", "2. Find a strategy")
S("btn_ingame", "3. Проверка в игре", "3. In-game check")
S("btn_reports", "Папка отчётов", "Reports folder")
S("coming_soon", "1 → 2 → 3. Перед шагом 3 выделите строку в таблице, чтобы проверить только её.", "1 → 2 → 3. Before step 3, select a table row to test only that one.")
S("launcher", "Лаунчер", "Launcher")
S("game_exe", "Игра", "Game")
S("launcher_not_set", "Лаунчер не найден — нажмите «Папка игры…» и выберите папку с лаунчером вашего сервера."
    , "Launcher not found — click “Game folder…” and choose your server's launcher folder.")
S("not_electron", "не Electron-лаунчер: проверка его движком недоступна", "not an Electron launcher: engine check unavailable")
S("state_now", "Сейчас", "Now")
S("not_found", "не найден", "not found")
S("pick_game_folder", "Выберите папку игры (где лежит лаунчер)", "Choose the game folder (where the launcher is)")
S("pick_launcher_exe", "Выберите файл лаунчера игры", "Choose the game launcher file")
S("pick_game_exe", "Выберите bsgo.exe вашего сервера", "Choose your server's bsgo.exe")
S("pick_zapret_folder", "Выберите папку Запрета (где service.bat)", "Choose the Zapret folder (with service.bat)")
S("not_zapret_folder", "В этой папке нет service.bat или bin\winws.exe.", "This folder has no service.bat or bin\winws.exe.")
S("zapret_service_on", "работает как служба Windows", "running as a Windows service")
S("zapret_winws_on", "работает (winws.exe)", "running (winws.exe)")
S("zapret_off", "выключен", "off")
S("gf_off", "выкл", "off")
S("close_game_first", "Закройте игру BSGO перед проверкой.", "Close the BSGO game before the check.")
S("restored_after_crash", "Прошлая проверка была прервана — Запрет и Game Filter возвращены как были."
    , "The previous check was interrupted — Zapret and Game Filter were restored.")
S("confirm_abort", "Идёт проверка. Прервать и вернуть Запрет как было?", "A check is running. Abort and restore Zapret?")
S("report_saved", "Отчёт сохранён", "Report saved")
S("report_prefix_diag", "диагностика", "diagnostics")
S("error", "Ошибка", "Error")

; ---------- ход проверки ----------
S("p_prepare", "Подготовка: адрес установщика, проверка Edge…", "Preparing: installer address, Edge self-test…")
S("p_with_zapret", "Проверка с текущим Запретом…", "Checking with the current Zapret…")
S("p_stop_zapret", "Временно останавливаю Запрет…", "Temporarily stopping Zapret…")
S("p_without", "Проверка без обхода…", "Checking without bypass…")
S("p_restore", "Возвращаю Запрет как было…", "Restoring Zapret…")

; ---------- строки результатов ----------
S("ok", "да", "ok")
S("no", "НЕТ", "NO")
S("no_answer", "нет ответа", "no answer")
S("stalled_at", "ВСТАЛО {:.1f} КБ", "STALLED {:.1f} KB")
S("attempts_ok", "{}/{} ок {:.1f} с", "{}/{} ok {:.1f} s")
S("no_edge", "нет Edge", "no Edge")
S("not_checked", "не провер.", "not checked")
S("dns_system", "системный", "system")
S("short", "короткий", "short")
S("download", "Загрузка", "Download")
S("launcher_engine", "движком лаунчера", "via launcher engine")
S("connected_status", "статус «Соединено»", "“Connected” status")
S("game_tcp", "TCP игры", "Game TCP")
S("diag_title", "ДИАГНОСТИКА ПОДКЛЮЧЕНИЯ К BSGO", "BSGO CONNECTION DIAGNOSTICS")
S("game", "Игра", "Game")
S("server", "Сервер", "Server")
S("game_ports", "игровые порты", "game ports")
S("learned_at", "подтверждены входом в игру", "confirmed by entering the game")
S("ports_default", "по умолчанию, ещё не подтверждались", "default, not yet confirmed")
S("zapret", "Запрет", "Zapret")
S("state_before", "до проверки", "before the check")
S("warn", "ВНИМАНИЕ", "WARNING")
S("edge_unavailable", "Edge не работает на этом ПК — проверка статуса «Соединено» пропущена."
    , "Edge does not work on this PC — the “Connected” status check was skipped.")
S("curl_unavailable", "встроенный curl Windows на этом ПК не работает (нет или блокируется антивирусом) — проверка идёт движком самого лаунчера."
    , "the built-in Windows curl does not work on this PC (missing or blocked by antivirus) — the launcher's own engine is used instead.")
S("node_unavailable", "движок лаунчера не запустился в режиме проверки (возможно, лаунчер обновился) — проверка идёт через curl."
    , "the launcher engine did not start in check mode (the launcher may have been updated) — curl is used instead.")
S("chromium_ignored", "проверка Chromium провалилась у всех стратегий, где лаунчер прошёл, — похоже, изменился сайт, а не сеть. Её результат не учитывался."
    , "the Chromium check failed for every strategy where the launcher passed — the site probably changed, not the network. It was ignored.")
S("server_moved_q", "Игровой сервер переехал: {} → {}.`n`nУзкая стратегия всё ещё смотрит на старый адрес. Обновить её список IP?"
    , "The game server moved: {} → {}.`n`nThe narrow strategy still points to the old address. Update its IP list?")
S("server_moved_fixed", "Список IP узкой стратегии обновлён: {}. Перезапустите стратегию.", "The narrow strategy IP list was updated: {}. Restart the strategy.")
S("server_moved_warn", "игровой сервер переехал ({} → {}) — узкая стратегия смотрит на старый адрес.", "the game server moved ({} → {}) — the narrow strategy points to the old address.")
S("main_check", "главная проверка", "main check")
S("r_curl_differs", "curl не прошёл, лаунчер прошёл — на игру не влияет", "curl failed, launcher passed — does not affect the game")
S("r_unknown", "нечем проверить: curl не работает, лаунчер не Electron", "nothing to test with: curl broken, launcher is not Electron")
S("v_unknown", "Проверить загрузку нечем: curl на этом ПК не работает, а лаунчер не на Electron.", "Downloads cannot be tested: curl does not work on this PC and the launcher is not Electron-based.")
S("n_unknown", "Перейдите сразу к шагам 2–3: стратегии подтвердятся входом в игру.", "Go straight to steps 2–3: strategies will be confirmed by entering the game.")
S("v_partial", "Загрузки с сервера то проходят, то обрываются — лаунчер будет работать нестабильно.", "Downloads from the server sometimes pass and sometimes stall — the launcher will be unstable.")
S("latest_unreadable", "latest.yml не прочитан — взят последний известный адрес установщика."
    , "latest.yml could not be read — the last known installer address was used.")
S("without_bypass", "Без обхода", "Without bypass")
S("with_current_zapret", "С текущим Запретом", "With the current Zapret")
S("current_ok", "текущий Запрет решает проблему лаунчера", "the current Zapret fixes the launcher problem")
S("current_not_ok", "текущий Запрет НЕ решает проблему", "the current Zapret does NOT fix the problem")
S("conclusion", "Вывод", "Conclusion")
S("what_next", "Что делать", "What to do")

; ---------- шаг 2: подбор стратегии ----------
S("scan_dialog_title", "Подбор стратегии", "Find a strategy")
S("mode_smart", "Умный (быстрее)", "Smart (faster)")
S("mode_full", "Полный", "Full")
S("smart_desc", "Только Game Filter TCP, остановка после 3 найденных кандидатов. Обычно 3–8 минут."
    , "Game Filter TCP only, stops after 3 candidates are found. Usually 3–8 minutes.")
S("full_desc", "Все выбранные стратегии × Game Filter (выкл и TCP). 15–25 минут при всех стратегиях."
    , "All selected strategies × Game Filter (off and TCP). 15–25 minutes for all strategies.")
S("btn_pick_strats", "Выбрать стратегии…", "Choose strategies…")
S("btn_start", "▶ Начать", "▶ Start")
S("btn_stop", "■ Остановить", "■ Stop")
S("stop_requested", "Остановлю после текущей стратегии…", "Stopping after the current strategy…")
S("scan_warn", "Закройте лаунчер и игру. Интернет во время подбора может мигать. Прежний Запрет вернётся сам."
    , "Close the launcher and the game. Internet may flicker during the search. Your previous Zapret will be restored.")
S("close_launcher_first", "Закройте лаунчер и игру BSGO (и в трее) перед подбором.", "Close the BSGO launcher and game (including the tray) first.")
S("no_zapret", "Сначала укажите папку Запрета.", "Choose the Zapret folder first.")
S("no_strategies", "В папке Запрета не найдено стратегий (*.bat с winws.exe).", "No strategies (*.bat with winws.exe) in the Zapret folder.")
S("pick_strategies", "Какие стратегии проверять", "Which strategies to test")
S("all", "Все", "All")
S("none", "Ни одной", "None")
S("done", "Готово", "Done")
S("pick_at_least_one", "Отметьте хотя бы одну стратегию.", "Tick at least one strategy.")
S("sel_all", "Проверяются все стратегии ({})", "All strategies are tested ({})")
S("sel_some", "Выбрано стратегий: {} из {}", "Strategies chosen: {} of {}")
S("p_strategy", "[{}/{}] {}  |  Game Filter: {}   (прошло {:.0f} мин)", "[{}/{}] {}  |  Game Filter: {}   ({:.0f} min elapsed)")
S("row_baseline", "(без обхода)", "(no bypass)")
S("did_not_start", "не запустилась", "did not start")
S("slow", "медленно", "slow")
S("r_chromium", "Chromium не проходит — в лаунчере не будет «Соединено»", "Chromium fails — the launcher will not show “Connected”")
S("r_unstable", "часть загрузок оборвалась", "some downloads stalled")
S("not_electron_short", "нет", "n/a")
S("c_candidate", "кандидат для игры", "game candidate")
S("c_launcher_only", "только лаунчер", "launcher only")
S("c_unstable", "нестабильно", "unstable")
S("c_fail", "не проходит", "fails")
S("c_not_started", "не запустилась", "did not start")
S("c_baseline", "исходное состояние", "baseline")
S("col_n", "№", "#")
S("col_strategy", "Стратегия", "Strategy")
S("col_curl", "curl 2 МБ", "curl 2 MB")
S("col_launcher", "Лаунчер 2 МБ", "Launcher 2 MB")
S("col_game_ports", "Игр. порты в .bat", "Game ports in .bat")
S("col_result", "Итог", "Result")
S("col_ingame", "В игре", "In game")
S("covers_yes", "обрабатывает", "handled")
S("covers_no", "не трогает", "not handled")
S("scan_title", "ПОДБОР СТРАТЕГИИ ЗАПРЕТА ДЛЯ BSGO", "ZAPRET STRATEGY SEARCH FOR BSGO")
S("scan_mode", "Режим", "Mode")
S("scan_progress", "проверено {} из {}", "{} of {} checked")
S("minutes", "{:.1f} мин", "{:.1f} min")
S("stopped_early", "остановлено досрочно", "stopped early")
S("installer", "установщик", "installer")
S("ports_closed_baseline", "игровые порты {} не открываются даже без Запрета — порты или IP игрового сервера могли смениться. Подтвердите стратегию входом в игру (шаг 3) — данные обновятся сами."
    , "game ports {} do not open even without Zapret — the game server's ports or IP may have changed. Confirm a strategy in game (step 3) — the data will update itself.")
S("launcher_short", "лаунчер", "launcher")
S("none_found", "нет", "none")
S("recommendation", "Рекомендация", "Recommendation")
S("rec_confirm", "Это прогноз по сети. Подтвердите входом в игру — шаг 3.", "This is a network forecast. Confirm it in game — step 3.")
S("rec_only_launcher", "Лаунчер заработает, но ни одна стратегия не обрабатывает игровые порты. Попробуйте Game Filter = TCP или добавьте порты {} в стратегию."
    , "The launcher will work, but no strategy handles the game ports. Try Game Filter = TCP or add ports {} to a strategy.")
S("rec_none", "Ни одна стратегия не прошла загрузку. Возможно, нужен VPN или обновление списков Запрета."
    , "No strategy passed the download test. You may need a VPN or updated Zapret lists.")
S("report_prefix_scan", "подбор", "search")

; ---------- шаг 3: проверка в игре ----------
S("need_step2", "Сначала выполните шаг 2 — подбор стратегии.", "Run step 2 (strategy search) first.")
S("no_candidates", "Нет кандидатов для проверки. Выделите строку в таблице или запустите полный подбор.", "No candidates to test. Select a table row or run a full search.")
S("ingame_intro", "Проверю в игре по очереди:`n{}`nДля каждой: включу стратегию и запущу лаунчер — войдите и нажмите «Играть». Вход в мир увижу сам. Если не получится — сам закрою игру и лаунчер и возьму следующую.`n`nНачать?"
    , "I will test in game, one by one:`n{}`nFor each: I enable the strategy and start the launcher — log in and press “Play”. I detect entering the world myself. If it fails, I close the game and launcher and take the next one.`n`nStart?")
S("g_trying", "Проверка в игре: {}  (Game Filter: {})", "In-game check: {}  (Game Filter: {})")
S("g_wait_play", "Лаунчер запущен. Войдите и нажмите «Играть»… ({:.0f} с)", "Launcher started. Log in and press “Play”… ({:.0f} s)")
S("g_wait_world", "Игра запущена {:.0f} с назад, жду входа в мир…", "Game started {:.0f} s ago, waiting for the world…")
S("g_world", "ВОШЁЛ В МИР", "ENTERED THE WORLD")
S("g_not_started", "игра не запущена за 5 мин", "game not started within 5 min")
S("g_closed", "игра закрылась до входа в мир", "game closed before entering the world")
S("g_hang", "зависло (нет входа за 3 мин)", "hung (no world within 3 min)")
S("g_cancelled", "отменено", "cancelled")
S("narrow_offer", "Вход в мир подтверждён, но с Game Filter TCP — он перехватывает все порты 1024–65535 и может мешать другим играм.`n`nСделать узкую версию этой стратегии только для портов и IP игры и проверить её в игре (с выключенным Game Filter)?"
    , "Entering the world is confirmed, but with Game Filter TCP — it intercepts all ports 1024–65535 and may affect other games.`n`nCreate a narrow version of this strategy only for the game's ports and IP and test it in game (with Game Filter off)?")
S("narrow", "узкая версия", "narrow version")
S("narrow_failed", "Узкую версию сделать не удалось", "Could not create a narrow version")
S("narrow_not_ok", "узкая версия в игре не прошла — остаётся исходная стратегия с Game Filter TCP", "the narrow version failed in game — the original strategy with Game Filter TCP stays")
S("narrow_no_ip", "игровой IP ещё не выучен", "the game IP has not been learned yet")
S("narrow_deleted", "(файл узкой версии удалён из папки Запрета)", "(the narrow version file was removed from the Zapret folder)")
S("narrow_dryrun_failed", "winws отклонил параметры узкой стратегии", "winws rejected the narrow strategy's parameters")
S("narrow_no_gf_rule", "в стратегии нет правила Game Filter TCP (--filter-tcp=%GameFilterTCP%)", "the strategy has no Game Filter TCP rule (--filter-tcp=%GameFilterTCP%)")
S("keep_q", "Оставить включённой стратегию`n{}`nс Game Filter: {}?`n`nДа — оставить. Нет — вернуть прежний Запрет.", "Keep the strategy`n{}`nwith Game Filter: {} enabled?`n`nYes — keep it. No — restore the previous Zapret.")
S("keep_service_note", "У вас установлена служба zapret — она остановлена. После перезагрузки она запустит старую стратегию. Чтобы закрепить новую, переустановите службу через service.bat с этой стратегией."
    , "You have the zapret service installed — it is stopped now. After a reboot it will start the old strategy. To make the new one permanent, reinstall the service via service.bat with this strategy.")
S("kept", "Оставлена: {} (Game Filter: {}).", "Kept: {} (Game Filter: {}).")
S("no_winner", "Ни один кандидат не вошёл в мир. Попробуйте полный подбор или других кандидатов (выделите строку).", "No candidate entered the world. Try a full search or other candidates (select a row).")
S("ingame_done", "Проверка в игре завершена.", "In-game check finished.")
S("forecast", "прогноз", "forecast")
S("in_game", "в игре", "in game")
S("game_conns", "соединения игры", "game connections")
S("cmd_hosts", "адреса в команде запуска", "addresses in launch command")
S("report_prefix_ingame", "проверка_в_игре_история", "ingame_history")
S("site_ip", "IP сайта", "site IP")
S("learn_first", "Игровой сервер впервые подтверждён входом в игру: {}, порты {}.", "Game server confirmed by entering the game for the first time: {}, ports {}.")
S("learn_same", "Игровой сервер и порты подтверждены: {}, порты {}.", "Game server and ports confirmed: {}, ports {}.")
S("learn_changed", "Игровой сервер ИЗМЕНИЛСЯ: теперь {}, порты {} (было: {}, {}). Дальше проверяются новые.", "The game server CHANGED: now {}, ports {} (was: {}, {}). The new ones are checked from now on.")

; ---------- выводы ----------
S("v_dns", "Системный DNS не находит сервер игры, а защищённый DNS (DoH) находит. Проблема в DNS провайдера."
    , "The system DNS cannot find the game server, but secure DNS (DoH) can. Your provider's DNS is the problem.")
S("v_offline", "Адрес сервера игры не находится вообще: нет интернета или домен недоступен."
    , "The game server address cannot be resolved at all: no internet or the domain is unavailable.")
S("v_ip_block", "Сервер недоступен даже на уровне подключения (TCP 443) — похоже на блокировку IP-адреса."
    , "The server is unreachable even at connection level (TCP 443) — looks like an IP block.")
S("v_tls", "Подключение есть, но защищённое соединение обрывается сразу — похоже на блокировку по имени сайта."
    , "The connection opens, but the secure session breaks immediately — looks like blocking by site name.")
S("v_volume", "Сервер отвечает, но данные обрываются примерно на {:.0f} КБ. Лаунчер не сможет получить список файлов (manifest) и проверить игру."
    , "The server answers, but data stops at about {:.0f} KB. The launcher will not get its file list (manifest).")
S("v_chromium", "Короткие загрузки проходят, но браузерный движок лаунчера страницу не получает — в лаунчере не будет «Соединено»."
    , "Small downloads work, but the launcher's browser engine cannot load the page — the launcher will not show “Connected”.")
S("v_ports", "Сайт и лаунчер работают, но игровые порты ({}) не открываются."
    , "The site and launcher work, but the game ports ({}) do not open.")
S("v_ok", "Без обхода сеть до сервера в порядке: для лаунчера Запрет не нужен."
    , "Without bypass the network to the server is fine: the launcher does not need Zapret.")
S("n_ok", "Если игра всё же зависает при загрузке мира или пишет WSA 10054 — это уровень игры: проверьте шагом 3 (вход в игру)."
    , "If the game still hangs while loading the world or shows WSA 10054, it is a game-level issue: use step 3 (in-game check).")
S("n_dns", "Смените DNS на 1.1.1.1 или 8.8.8.8 (или включите DNS-over-HTTPS в настройках Windows) и повторите диагностику."
    , "Switch DNS to 1.1.1.1 or 8.8.8.8 (or enable DNS-over-HTTPS in Windows) and run diagnostics again.")
S("n_offline", "Проверьте интернет и что сайт игры вообще открывается.", "Check your internet and that the game site opens at all.")
S("n_vpn", "Стратегии Запрета обходят фильтрацию, но не блокировку IP. Нужен VPN или прокси."
    , "Zapret strategies bypass filtering, not IP blocks. You need a VPN or proxy.")
S("n_current_works", "Ваш текущий Запрет уже решает это ✓. Чтобы убедиться, что войдёт и в игровой мир, используйте шаг 3."
    , "Your current Zapret already fixes this ✓. To make sure the game world loads too, use step 3.")
S("n_go_step2", "Перейдите к шагу 2 — подбор стратегии Запрета.", "Go to step 2 — find a Zapret strategy.")
S("n_install_zapret", "Это решается Запретом (zapret-discord-youtube). Установите его и укажите папку — затем шаг 2."
    , "Zapret (zapret-discord-youtube) can fix this. Install it, choose its folder, then use step 2.")
