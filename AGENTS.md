# AGENTS.md — СДВГ Киллер

Instructions for a model working on this project. For people — [README.md](README.md), install — [INSTALL.md](INSTALL.md).

## Что это
Программа для строки меню Mac на Swift: человек пишет, чем занят, программа следит за активным
окном и возвращает к задаче, если он отвлёкся. Код — `Sources/`, ресурсы — `Resources/`.

## Сборка и проверка
```bash
./tests/run.sh
./build.sh --install
```
Нужны только Command Line Tools (`xcode-select --install`), полный Xcode не нужен.

## Правила
- Репозиторий открытый: никаких ключей и личных данных в коде. Ключ API пользователь вводит сам
  при первом запуске.
- README двуязычный (русский и English) — менять обе части.
