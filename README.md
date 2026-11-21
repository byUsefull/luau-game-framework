# Luau Game Framework

Каркас Roblox-игры на Luau, на котором работают мои игры [Grow Your Parts](https://www.roblox.com/games/107905084876273/Grow-Your-Parts) и [Build a Bonfire](https://www.roblox.com/games/119301185261693/Build-a-Bonfire). Здесь только ядро — запуск, сеть, сохранения, игрок — и одна маленькая система для примера. Игровая логика самих игр закрыта.

*English summary below.*

- **59 модулей, ~5 200 строк** строго типизированного Luau (`--!strict` в каждом файле)
- **133 проверки** в 9 наборах тестов на [lune](https://github.com/lune-org/lune)
- Rojo, StyLua, Selene; инструменты закреплены в `rokit.toml`

## Что внутри

| Часть | Что делает |
|---|---|
| **Boot** | Один `Script` на сервере и один `LocalScript` на клиенте. Они находят все `…Service` / `…Controller` по имени и поднимают их. Новая система — новый файл, загрузчики не правятся. |
| **ModuleLoader** | Порядок по зависимостям, две фазы: все `Init`, потом все `Start`. Упавший модуль помечается `FAILED`, зависящие от него — `SKIPPED`, остальная игра поднимается. В конце — отчёт с временем каждого модуля. |
| **Lifecycle** | База синглтонов: `_bind`, `_spawn`, `_delay` складывают подписки и потоки в уборку, `Destroy` снимает всё сам. |
| **EventBus** | Шина событий внутри одной стороны. Отправитель не знает получателей: квест «купи 3 зелья» — новый подписчик, магазин не трогаем. |
| **Network** | Каждый канал объявлен в `<System>Channels` с направлением и лимитом частоты. Сервер не зарегистрирует обработчик без `validate`. Проверки по порядку: частота → игрок готов → форма данных. Отказы — с кодом ошибки, сырых `RemoteEvent` в коде систем нет. |
| **Validate** | Набор проверок данных клиента: `int`, `num`, `str`, `oneOf`, `array`, `shape`… |
| **DataService** | Обёртка над ProfileStore. Профиль живёт в памяти сервера всю сессию, в DataStore уходит автосохранением и при выходе; покупки за Robux — `SaveAndWait` до ответа «выдано». Миграции схемы по версиям, приватные поля не уходят клиенту, в Studio — отдельное хранилище. |
| **Player** | Порядок входа и выхода для всех систем: `PlayerReady` → `ClientReady` → `PlayerLeaving`. `PlayerScope` убирает всё, что связано с игроком, когда он уходит. |
| **Logger** | Области и уровни `Debug / Info / Warn / Critical`. Строка форматируется только после проверки уровня. |
| **Coins** (пример) | Клиент копит клики и шлёт пачкой → канал с лимитом и `validate` → `CoinsService` считает награду (`CoinsMath`) → `DataService:Update` → клиент получает изменения → `CoinsEarned` на шине. |

Подробнее — в [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md).

## Структура

```
src/
  boot/      ServerMain.server.luau, ClientMain.client.luau
  shared/    Core, Network, Data, Player, Coins   → ReplicatedStorage.Shared
  server/    Core, Data, Player, Coins            → ServerStorage.Server
  client/    Data, Player, Coins                  → ReplicatedStorage.Client
tests/       lune-тесты чистой логики
```

Каждая система раскладывается одинаково: `<S>Config` (все числа и тексты), `<S>Channels` (сеть), `<S>Events` (шина), `<S>Types`, чистая логика в `shared/`, `<S>Service` на сервере, `<S>Controller` на клиенте. У каждого поля профиля и каждого атрибута один владелец.

## Запуск

```bash
rokit install                      # rojo, stylua, selene, lune
rojo serve                         # подключиться плагином Rojo в Studio
lune run tests/network_validate.spec
stylua --check src tests && selene src
```

ProfileStore — сторонняя библиотека ([loleris / MadStudio](https://github.com/MadStudioRoblox/ProfileStore)), в репозиторий не входит. Положите `ProfileStore.luau` в `src/server/Data/Packages/`. Для сохранений в Studio включите *Game Settings → Security → Enable Studio Access to API Services*.

---

## English summary

The core of my Roblox games ([Grow Your Parts](https://www.roblox.com/games/107905084876273/Grow-Your-Parts), [Build a Bonfire](https://www.roblox.com/games/119301185261693/Build-a-Bonfire)): boot, networking, saving, player lifecycle, plus one small example system. Game logic stays private. Code comments are in Russian.

- Dependency-ordered `Init` → `Start` boot; a failing module is marked `FAILED`, its dependents `SKIPPED`, the rest of the game still starts.
- Every network channel is declared with a direction and a rate limit; the server refuses to register a handler without a payload validator.
- ProfileStore wrapper: the profile lives in server memory for the session, Robux purchases use `SaveAndWait`, versioned migrations, private fields never reach the client.
- Event bus, scoped leveled logger, per-player cleanup scope, strict types everywhere, 133 lune test checks.

## Автор

Кирилл Скорик — Roblox / Luau-разработчик. Telegram: [@stf_use](https://t.me/stf_use)

Лицензия: [MIT](LICENSE).
