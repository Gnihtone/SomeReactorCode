# Система управления вакуумными реакторами GTNH

Распределенная система управления вакуумными реакторами для GregTech: New Horizons через OpenComputers.

## Новые возможности

### 1. Поддержка нескольких реакторов на одном клиенте

Теперь один клиент может управлять несколькими реакторами одновременно. Клиент автоматически обнаруживает все доступные реакторы в системе и управляет ими независимо.

**Запуск клиента с несколькими реакторами:**
```bash
vacuum_client_manager.lua [имя_клиента]
```

Клиент автоматически найдет все reactor_chamber компоненты и назначит им уникальные ID в формате `ClientName-R1`, `ClientName-R2` и т.д.

### 2. Мониторинг энергохранилищ

Новый клиент для мониторинга энергохранилищ GregTech автоматически управляет реакторами в зависимости от заполнения хранилищ.

**Запуск клиента энергохранилищ:**
```bash
energy_storage_client.lua [имя_клиента]
```

**Функциональность:**
- Автоматическое обнаружение всех GT энергохранилищ (Battery Buffers, GT машины с большой ёмкостью)
- Приостановка всех реакторов при заполнении любого хранилища на 99% и выше
- Автоматическое возобновление работы при снижении заполнения ниже 95%
- Реакторы получают статус `PAUSED_ENERGY` при приостановке

### 3. Отслеживание времени работы

Каждый реактор теперь отслеживает общее время работы (только в состоянии RUNNING). Время отображается в интерфейсе сервера в формате "Xч Yм Zс".

### 4. Discord интеграция

Система теперь поддерживает полную интеграцию с Discord для удаленного мониторинга и управления.

**Возможности Discord интеграции:**
- Удаленное управление реакторами через команды в чате
- Автоматические уведомления о важных событиях
- Мониторинг состояния системы в реальном времени
- Просмотр логов и статистики

**Доступные команды:**
- `!help` - список всех команд
- `!status` - общий статус системы
- `!reactors` - список всех реакторов
- `!start <имя|all>` - запустить реактор
- `!stop <имя|all>` - остановить реактор
- `!energy` - состояние энергохранилищ
- `!logs` - последние логи системы

Подробные инструкции по настройке Discord интеграции смотрите в [DISCORD_SETUP.md](DISCORD_SETUP.md).

## Архитектура системы

### Компоненты:

1. **Сервер** (`vacuum_server.lua`) - центральный узел управления
   - Управляет всеми подключенными клиентами
   - Принимает решения о приостановке/возобновлении работы реакторов
   - Отображает состояние всех реакторов в едином интерфейсе
   - Обеспечивает интеграцию с Discord

2. **Клиент реакторов** (`vacuum_client_manager.lua`)
   - Управляет одним или несколькими реакторами
   - Автоматически обнаруживает все reactor_chamber в системе
   - Независимо управляет каждым реактором

3. **Клиент энергохранилищ** (`energy_storage_client.lua`)
   - Мониторит состояние энергохранилищ GregTech
   - Отправляет данные о заполнении на сервер
   - Не управляет реакторами напрямую

4. **Discord API** (`discord_api.lua`) и **Discord интеграция** (`discord_integration.lua`)
   - Обеспечивают связь с Discord через Bot API
   - Обрабатывают команды и отправляют уведомления

### Протокол связи

Расширен для поддержки:
- Множественных реакторов на одном клиенте (поле `reactorId`)
- Данных о энергохранилищах (`ENERGY_STORAGE_UPDATE`)
- Команд паузы/возобновления (`PAUSE_FOR_ENERGY_FULL`, `RESUME_FROM_ENERGY_PAUSE`)

### Новые статусы реакторов

- `RUNNING` - реактор работает нормально
- `STOPPED` - реактор остановлен
- `PAUSED_ENERGY` - реактор приостановлен из-за переполнения энергохранилища
- `EMERGENCY` - аварийный режим
- `MAINTENANCE` - техническое обслуживание
- `OFFLINE` - нет связи с клиентом

## Требования

- OpenComputers
- GregTech (GTNH версия)
- Беспроводные сетевые карты для связи между компонентами
- Transposer для каждого реактора
- ME система для автоматической замены компонентов
- Интернет-карта (для Discord интеграции)

## Установка

1. Скопируйте все файлы из `src/` на компьютеры OpenComputers
2. Запустите сервер на центральном компьютере
3. Запустите клиенты реакторов на компьютерах, подключенных к реакторам
4. Запустите клиент энергохранилищ на компьютере с доступом к GT батарейным буферам
5. (Опционально) Настройте Discord интеграцию согласно [DISCORD_SETUP.md](DISCORD_SETUP.md)

## Конфигурация

Основные настройки находятся в `vacuum_config.lua`:
- `ENERGY_STORAGE.FULL_THRESHOLD` - порог заполнения для остановки (99%)
- `ENERGY_STORAGE.RESUME_THRESHOLD` - порог для возобновления работы (95%)
- `NETWORK.HEARTBEAT_INTERVAL` - интервал отправки данных (2 сек)
- `DISCORD.*` - настройки Discord интеграции 