# BSGO Connection Doctor

**[Русский](#русский) · [English](#english)**

---

## Русский

Программа для игроков **BSGO Nova** (Battlestar Galactica Online), у которых игра не работает без обхода блокировок. Чаще всего это игроки из России: лаунчер не может получить список файлов, проверка файлов зависает, игра виснет на загрузке мира или пишет **WSA 10054**.

Программа сама выясняет, что именно сломано, перебирает стратегии [Запрета (zapret-discord-youtube от Flowseal)](https://github.com/Flowseal/zapret-discord-youtube) и подтверждает лучшую настоящим входом в игру.

### Скачать
Готовый файл **`BSGO_Tester.exe`** лежит в разделе **[Releases](../../releases)**. Устанавливать ничего не нужно.

### Что нужно
- Windows 10 или 11;
- установленный лаунчер BSGO Nova;
- распакованный Запрет (zapret-discord-youtube 1.10.x). Можно установленный как служба: программа сама остановит службу на время проверки и потом запустит снова;
- права администратора: без них Запрет не запускается.

### Как пользоваться
1. Положите `BSGO_Tester.exe` в **отдельную папку**, например `Рабочий стол\BSGO_Tester\`. Рядом с собой программа создаст файл настроек и папку с отчётами.
2. Запустите и разрешите права администратора. Если программа не нашла папки сама, нажмите **«Папка игры…»** и **«Папка Запрета…»**.
3. Закройте лаунчер и игру, затем выполните шаги по очереди:
   - **1. Диагностика** (1–2 мин): что сломано без обхода и помогает ли ваш текущий Запрет;
   - **2. Подбор стратегии** (3–8 мин в умном режиме): программа перебирает стратегии и находит кандидатов;
   - **3. Проверка в игре**: программа включает лучшего кандидата и запускает лаунчер, вы входите и нажимаете «Играть», а вход в мир программа видит сама. Если стратегия работает только с Game Filter TCP, программа предложит сделать **узкую версию** только для портов и IP игры и тоже проверит её в игре.
4. В конце ответьте «Да», чтобы оставить найденную стратегию включённой.

Если что-то не получилось, пришлите файлы из папки `reports`.

### Что программа делает с компьютером
- **Временно** останавливает Запрет (и службу zapret) и меняет настройку Game Filter (`utils\game_filter.enabled`). После проверки всё возвращается как было, даже если программу закрыли посреди проверки (при следующем запуске).
- В папке Запрета может создать узкую стратегию `… - BSGO narrow.bat` и список `lists\ipset-bsgo-tester.txt`. Оригинальные стратегии не меняются.
- Обращается только к сайту игры (`playbsgo.com`), к игровому серверу и к DNS-сервисам Cloudflare и Google (чтобы сравнить ответ DNS).

### Чего программа НЕ делает
- Не читает пароли, токены и файл сессии лаунчера: проверяется только время изменения файла сессии.
- Никуда не отправляет данные о вас.

### Насколько точен результат
- Шаги 1–2 надёжно показывают, заработает ли **лаунчер** («Соединено», вход, проверка файлов).
- Войдёт ли **игра в мир**, по сети предсказать нельзя, поэтому есть шаг 3 с настоящим входом в игру.
- У разных провайдеров работают разные стратегии. Поэтому программа не даёт общий список «рабочих стратегий», а проверяет их у каждого игрока.

### Антивирус
Программа написана на [AutoHotkey v2](https://www.autohotkey.com/) и собрана в exe. Некоторые антивирусы ложно ругаются на такие файлы. Исходный код открыт в этом репозитории, и exe можно собрать самому (см. ниже).

### Другие (приватные) серверы BSGO
Папку игры можно указать вручную. Игровые порты и IP программа выучивает сама после первого удачного входа. Проверки, которые зависят от сайта Nova (файл установщика, страница сайта), для других серверов работают ограниченно.

### Сборка из исходников
1. Установите [AutoHotkey v2](https://www.autohotkey.com/) (вместе с компилятором Ahk2Exe).
2. Запустите `build.bat`. Готовый файл появится в `build\BSGO_Tester.exe`.

Запустить без сборки: двойной щелчок по `src\BSGO_Tester.ahk`.

### Инструменты
- [`tools/BSGO_Watcher.ahk`](tools/README.md) — наблюдатель: записывает, к каким адресам и портам подключаются лаунчер и игра на каждом этапе. Нужен, чтобы разбираться с новыми проблемами, обновлениями игры и другими серверами.

---

## English

A tool for **BSGO Nova** (Battlestar Galactica Online) players whose game does not work without bypassing network restrictions (mostly players in Russia): the launcher cannot get its file list, the file check hangs, or the game freezes while loading the world / shows **WSA 10054**.

It finds out what exactly is broken, tests [Zapret (Flowseal's zapret-discord-youtube)](https://github.com/Flowseal/zapret-discord-youtube) strategies and confirms the best one by actually entering the game.

### Download
Get **`BSGO_Tester.exe`** from **[Releases](../../releases)** — no installation needed. Switch the interface to English with the **“English”** button.

### Requirements
Windows 10/11, the BSGO Nova launcher, an unpacked Zapret (zapret-discord-youtube 1.10.x; a Windows-service install is fine — it is paused and restored), administrator rights.

### Usage
1. Put the exe into its own folder (it creates settings and a `reports` folder next to itself) and run it as administrator. If paths are not detected, use “Game folder…” / “Zapret folder…”.
2. Close the launcher and the game, then run **1. Diagnostics → 2. Find a strategy → 3. In-game check**. In step 3 you log in and press “Play”; entering the world is detected automatically. If a strategy only works with the global Game Filter TCP, the tool offers a **narrow version** limited to the game's ports and IP and tests it too.
3. Answer “Yes” to keep the found strategy enabled.

### What it changes
Temporarily stops Zapret / the zapret service and changes `utils\game_filter.enabled`, then restores everything (even after a crash — on the next start). It may create `… - BSGO narrow.bat` and `lists\ipset-bsgo-tester.txt` in the Zapret folder; original strategies are never modified. It only contacts the game site, the game server and Cloudflare/Google DNS-over-HTTPS. **It never reads passwords, tokens or the launcher session file** and sends no data about you anywhere.

### Accuracy
Steps 1–2 reliably predict whether the **launcher** will work. Whether the **game** enters the world can only be confirmed by step 3.

### Build from source
Install [AutoHotkey v2](https://www.autohotkey.com/) with Ahk2Exe and run `build.bat` (output: `build\BSGO_Tester.exe`), or run `src\BSGO_Tester.ahk` directly.

---

Author: **TROL** · License: [MIT](LICENSE)
