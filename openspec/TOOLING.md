# Инструменты OpenSpec

Установлено 27 октября 2026 на macOS arm64 для текущего пользователя:

- Node.js 24.22.1 LTS: `~/.local/share/node-v24.22.1-darwin-arm64`.
- npm 11.19.1, входит в официальный архив Node.js.
- OpenSpec 1.15.0: официальный npm-пакет `@fission-ai/openspec`, prefix `~/.local`.
- Команды `node`, `npm`, `npx`, `openspec`: `~/.local/bin`.
- В `~/.zprofile` добавлен пользовательский каталог команд в PATH. В уже открытом терминале открыть новую login-сессию либо выполнить `export PATH="$HOME/.local/bin:$PATH"`.

Архив Node.js проверен по официальной SHA256: `89c682593d76cd44233fa53b1563264e7de9cbb189cad169135c5b4fadfbc0a7`.

Проект инициализирован командой `openspec init --tools codex --language Russian --no-animation`. В `.agents/skills/` установлены официальные `openspec-propose`, `openspec-explore`, `openspec-apply-change`, `openspec-update-change`, `openspec-sync-specs`, `openspec-archive-change`. Навыки ограничены проектом LSwitcher; CLI доступен пользователю из других проектов. Homebrew и сторонние менеджеры пакетов не требуются.

## Работа с планом

```sh
openspec status --change improve-everyday-reliability
openspec validate improve-everyday-reliability --strict
```

Обе команды выполнены успешно после создания плана: 4/4 артефакта готовы. Это готовность планирования, а не реализации; все задачи пока открыты.

Для реализации выбрать `openspec-apply-change` в Skills или попросить применить изменение `improve-everyday-reliability`. Для нового предложения использовать `openspec-propose`. Новые навыки доступны для выбора со следующего сообщения.

Официальные источники: [OpenSpec installation](https://openspec.dev/docs/installation), [Codex integration](https://openspec.dev/docs/supported-tools), [Node.js](https://nodejs.org/en/download).
