# BSGO Watcher — наблюдатель / watcher

**[Русский](#русский) · [English](#english)**

## Русский

### Зачем он нужен
Наблюдатель **записывает, что делают лаунчер и игра в сети** на каждом этапе: к каким адресам и портам они подключаются, какие соединения обрываются, когда лаунчер проверяет файлы и когда игра входит в мир.

Обычным игрокам он **не нужен**, для них есть `BSGO_Tester.exe`. Наблюдатель пригодится, если:
- после обновления игры или лаунчера тестер стал ошибаться и нужно понять, что поменялось (новые адреса, порты, строки в логе игры);
- нужно разобраться с **другим (приватным) сервером** BSGO: какие адреса и файлы использует его лаунчер;
- нужно подробно показать разработчикам игры, на каком этапе и на каком адресе ломается подключение.

### Что записывается и что нет
**Записывается:**
- TCP/UDP-соединения процессов лаунчера и игры (адрес, порт, состояние, время);
- имена адресов из DNS-кэша Windows;
- время изменения файла сессии лаунчера;
- строки-маркеры из лога игры `output_log.txt`;
- дисковая активность лаунчера (так видна проверка файлов).

**НЕ записывается:** пароли, токены, содержимое файла сессии.

**Внимание:** копии лога игры в записи содержат **имя вашего персонажа**. Не выкладывайте их публично без проверки.

### Как пользоваться
1. Нужен [AutoHotkey v2](https://www.autohotkey.com/). Права администратора не нужны.
2. Полностью закройте лаунчер (и в трее).
3. Двойной щелчок по `BSGO_Watcher.ahk` → **«▶ Начать запись»** → **«Запустить лаунчер»**.
4. Нажимайте кнопки-отметки в момент, когда этап наступил: «Соединено», вход в аккаунт, «Играть», экран загрузки, «Я в мире», ошибка и т. д. В игре удобнее **Ctrl+Alt+цифра**. Многие этапы программа отмечает сама.
5. Когда вы в мире (или всё сломалось), подождите ~30 секунд и нажмите **«■ Остановить и сохранить»**.

Лучше сделать две записи, **с рабочей и с нерабочей** настройкой (например, Запрет включён и выключен), и сравнить их.

### Что получится
Папка `records\<дата_время>\`:
- `сводка.txt` — главное: этапы по времени, все адреса с итогами и раздел «Докуда дошли»;
- `журнал.txt` — всё по секундам;
- `соединения.tsv` — каждое соединение отдельной строкой (открывается в Excel);
- `лог_игры_NN.txt` — копия лога игры этого запуска.

### Ограничения
- Соединения опрашиваются 5 раз в секунду: очень короткие могут быть видны частично.
- Для UDP Windows не показывает адрес назначения.
- Путь к лаунчеру Nova по умолчанию: `C:\Games\bsgo nova\BSGO Launcher\`. Если лаунчер в другом месте, программа спросит путь при первом запуске лаунчера из неё.

---

## English

### What it is for
The watcher **records what the launcher and the game do on the network** at every stage: which addresses and ports they connect to, which connections break, when the launcher checks files and when the game enters the world.

Regular players don't need it (use `BSGO_Tester.exe`). It is useful to investigate what changed after a game/launcher update, to study **another (private) BSGO server**, or to show the game developers exactly where the connection breaks.

It records connections, DNS names, the session file's modification time (never its content), marker lines from the game log and launcher disk activity. **It never records passwords or tokens.** Note: the saved game-log copies contain your **character name**.

### Usage
Requires [AutoHotkey v2](https://www.autohotkey.com/) (no admin rights). Fully close the launcher, run `BSGO_Watcher.ahk` → **Start recording** → **Start launcher**, press the stage buttons (or **Ctrl+Alt+digit**) as stages happen, then **Stop and save**. The result is in `records\<date_time>\` (`сводка.txt` = summary, `журнал.txt` = timeline, `соединения.tsv` = connections). The interface is in Russian.
