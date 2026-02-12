# Часть 1а: Техническое задание и Архитектурный дизайн: LLMService (Swift Package)

## 1. Видение продукта

**LLMService** — это высокоуровневая Swift-библиотека, предназначенная для интеграции различных поставщиков больших
языковых моделей (LLM) в приложения для iOS и macOS.

Основная ценность сервиса заключается в **абстракции сложности**:

1. **Унификация протоколов**: Перевод различных форматов запросов/ответов (OpenAI, Gemini, Claude) в единый внутренний
   стандарт.
2. **Эмуляция CLI-возможностей**: Поддержка "reverse-engineered" API (таких как Claude Code или Gemini CLI), которые
   официально доступны только через терминальные инструменты, но через LLMService становятся доступны как обычные API.
3. **Управление жизненным циклом**: Автоматическая обработка OAuth-авторизации, рефреша токенов, квотирования и
   сложных "Thinking" (рассуждающих) моделей.




---

## 2. Функциональные требования

### 2.1. Поддержка провайдеров

Сервис должен поддерживать три категории провайдеров:

* **Reverse Engineered (CLI-based)**: `geminiCLI`, `antigravity`, `claudeCode`, `codex`. Эти провайдеры требуют эмуляции
  поведения CLI-инструментов, специфических заголовков (User-Agent spoofing) и работы с OAuth.
* **Official API**: `openai`, `anthropic`, `google` (Generative Language API), `vertex` (Google Cloud). Работают через
  API-ключи или сервисные аккаунты.
* **Agnostic/Local**: `ollama`, `openRouter`. Провайдеры, использующие стандартные протоколы (обычно
  OpenAI-совместимые).

### 2.2. Управление аккаунтами и сессиями

* **Унифицированный доступ**: Весь доступ к провайдерам должен идти через объект «Сессия» (`LLMAccountSession`).
* **Делегированное хранение**: Сервис не должен навязывать способ хранения секретов. Он должен требовать реализации
  протокола, где приложение само решает, класть ли токены в Keychain, а метаданные в базу данных.
* **Login Flow**: Для OAuth-провайдеров сервис должен брать на себя весь цикл: генерация URL, поднятие сессии
  авторизации и получение токенов.

### 2.3. Работа с чатом (Core API)

* **Smart Chat**: Метод, который автоматически выбирает между обычным HTTP-запросом и стримингом. Если модель/провайдер
  поддерживает только стриминг, сервис должен «молча» собрать стрим в единый ответ и вернуть его как `LLMResponse`.
* **Streaming**: Нативная поддержка `AsyncThrowingStream` для отображения ответов в реальном времени.
* **Multi-modal**: Поддержка текста, системных инструкций, путей к файлам и бинарных данных (изображений) в сообщениях.
* **Reasoning/Thinking**: Корректная обработка блоков рассуждений, которые могут приходить до, после или вперемешку с
  основным текстом.

### 2.4. Дебаггинг и трассировка

* **TraceID**: Каждый логический запрос получает UUID, который пробрасывается через все уровни (включая автоматические
  рефреши токенов).
* **Deep Logging**: Запись каждого этапа запроса в JSON-файлы и системный лог (OSLog) с разделением по категориям
  провайдеров.
* **HAR Export**: Возможность выгрузить историю запросов в формате HTTP Archive (.har) для анализа в Proxyman/Charles.

---

## 3. Ключевые архитектурные решения и их Reasoning

### 3.1. Паттерн «Identity-based Session» (LLMAccountSession)

**Решение**: Мы отказались от передачи отдельных API-ключей или репозиториев токенов в методы сервиса. Вместо этого
сервис инициализируется объектом, реализующим протокол `LLMAccountSession`.

**Reasoning**:

* **Консистентность**: Провайдеру `OpenAI` нужен ключ, а `ClaudeCode` — сложный OAuth-объект. Через протокол мы скрываем
  эту разницу.
* **Безопасность (Separation of Concerns)**: Пакет `LLMService` умеет *добывать* токены (через логин) и *обновлять* их,
  но он не должен знать, *где* они лежат. Приложение реализует `save()` и само распределяет данные: email — в БД для UI,
  токены — в Keychain для безопасности.
* **Active Record**: Объект сессии является «живым». Когда сервис обновляет токен, он вызывает `session.save()`, и
  состояние приложения обновляется автоматически.

### 3.2. Использование ASWebAuthenticationSession

**Решение**: Для всех OAuth-процессов используется системный фреймворк Apple `AuthenticationServices`.

**Reasoning**:

* **Безопасность**: Это стандарт индустрии на iOS/macOS. Он работает в изолированном процессе и поддерживает системные
  куки.
* **Отказ от локальных серверов**: В отличие от Go-прототипа, где поднимается HTTP-сервер на порту 8085, в Swift-пакете
  мы используем `callbackURLScheme`. Это позволяет избежать проблем с брандмауэрами и песочницами (App Sandbox).

### 3.3. Архитектура «Smart Streaming»

**Решение**: Метод `chat()` всегда пытается вернуть полную структуру `LLMResponse`. Если провайдер поддерживает только
стриминг (как `antigravity`), сервис запускает внутренний стрим, накапливает данные и выдает финальный результат.

**Reasoning**:

* **Упрощение логики приложения**: 80% задач (перевод, суммаризация) не требуют стриминга в UI. Разработчику проще
  вызвать `await chat()`, чем подписываться на стрим и вручную собирать строки.
* **Единообразие**: Приложение работает с любой моделью одинаково, независимо от капризов API провайдера.

### 3.4. Слоистая структура ответа (Message -> Part)

**Решение**: Ответ модели (`LLMResponse`) содержит не просто текст, а массив фрагментов (`LLMResponsePart`), каждый из
которых имеет тип (`text`, `thinking`, `toolCall`).

**Reasoning**:

* **Будущее "Reasoning" моделей**: Модели типа Claude 3.7 или o1 могут сначала «подумать», потом «вызвать инструмент»,
  потом «снова подумать» и только потом «ответить». Простая пометка `isThinking` на уровне всего сообщения не подходит.
  Нужен массив блоков, сохраняющий хронологию.
* **UI-флексибильность**: Приложение может по-разному отрисовывать каждый блок (например, прятать блоки `.thinking` под
  спойлер).

### 3.5. Система трассировки и HAR-экспорта

**Решение**: Введение `traceId` и обязательное сохранение каждого HTTP-транзакции в отдельный JSON-файл в заданной
директории.

**Reasoning**:

* **Сложные цепочки**: Один вызов `chat()` может инициировать: 1. `refresh_token`, 2. `get_account_info`, 3. собственно
  `chat_request`. Без общего `traceId` невозможно понять в логах, что эти три запроса связаны.
* **Отладка в продакшене**: Если у пользователя произошла ошибка, приложение может выгрузить HAR за последние 5 минут и
  отправить разработчику. HAR — это стандарт, его поймет любой инструмент анализа трафика.
* **Маскирование**: Встроенный `LLMRedactor` позволяет включать/выключать скрытие ключей. Это критично: для внутреннего
  дебага ключи могут быть нужны, для логов пользователю — категорически нет.

---

## 4. Применяемые паттерны проектирования

### Внешние (API к приложению):

1. **Strategy (Стратегия)**: Провайдеры (`LLMProvider`) определяют стратегию поведения сервиса.
2. **Observer / Configuration**: Настройка логирования через `LLMLoggingConfig` позволяет приложению «подписаться» на
   системные логи через `Logger` или `subsystem`.
3. **Bridge (Мост)**: Протокол `LLMAccountSession` разделяет абстракцию работы с ИИ и реализацию хранения данных.

### Внутренние (внутри пакета):

1. **Translator (Адаптер)**: Группа классов-трансляторов (по одному на провайдера), которые переводят унифицированный
   `LLMRequest` в специфический JSON провайдера.
2. **Chain of Responsibility (Цепочка ответственности)**: При обработке ответа (особенно стриминга), данные проходят
   через фильтры (например, `UsageFilter` для вырезания технических метаданных).
3. **Factory (Фабрика)**: Создание конкретного сетевого клиента на основе выбранного провайдера.
4. **Coordinator**: Внутренний объект, управляющий процессом логина через `ASWebAuthenticationSession`.

---

> Вот те пункты, которые необходимо добавить в раздел требований и решений, чтобы картина была полной:
> 1. **Детальные возможности моделей (Capabilities)**: Ты явно просил не просто список, а конкретные флаги:
     `supportsText`, `supportsAudio`, `supportsImage`, `maxInputTokens`, `maxOutputTokens`. Это критично для того, чтобы
     UI приложения мог адаптироваться (например, скрывать кнопку прикрепления фото, если модель его не потянет).
> 2. **Учет квот (Quota Status)**: В Go-коде есть сложная логика «модельного кулдауна» и отслеживания лимитов. В
     Swift-пакете это должно быть выведено в явный метод, чтобы приложение могло показать пользователю: «У вас осталось
     5 запросов» или «Модель будет доступна через 2 минуты».
> 3. **Выбор проекта (Project Selection)**: В Go-коде для Gemini и Antigravity часто требуется выбор GCP Project ID. Это
     часть процесса логина или настройки аккаунта, которую мы должны предусмотреть в `LLMAccountInfo`.
> 4. **Глобальный Прокси (Proxy Support)**: Поскольку сервис работает с API, которые часто блокируются, поддержка
     `proxyURL` — это не «фича дебага», а базовое требование для работоспособности.
> 5. **Идемпотентность (Idempotency)**: Для надежных чатов (особенно при плохой связи) важно уметь передавать
     `idempotency_key`, чтобы повторный запрос из-за сбоя сети не списал квоту дважды.

---

# Часть 1б: Цели, Требования и Архитектурный Дизайн (Дополненная)

## 1. Видение продукта (Дополненная часть)

**LLMService** — это Swift-пакет, который служит «черным ящиком» для работы с любыми ИИ-провайдерами. Он берет на себя
самую грязную и сложную работу: эмуляцию CLI-клиентов, OAuth-авторизацию в системах, не предназначенных для сторонних
приложений, и бесшовную трансформацию данных между несовместимыми форматами.

---

## 2. Расширенные функциональные требования

### 2.1. Авторизация и управление сессиями

* **Унификация (Identity Object)**: Сервис работает через объект `LLMAccountSession`. Приложение передает этот объект, и
  сервис через него получает всё необходимое: тип провайдера, текущие ключи/токены и метаданные.
* **OAuth через ASWebAuthenticationSession**: Весь процесс входа (Login Flow) инкапсулирован внутри. Сервис сам знает,
  какие `scopes` нужны для Anthropic, а какие для Google. Он поднимает системное окно авторизации и обрабатывает
  `callbackURL`.
* **Автоматический менеджмент токенов**: Сервис сам проверяет `expiresAt`. Если токен истек или провайдер вернул
  `401 Unauthorized`, сервис делает попытку `refresh`, сохраняет новые данные через сессию и повторяет исходный запрос.

### 2.2. Работа с моделями и квотами

* **Инспекция возможностей**: Для каждой модели сервис должен отдавать структуру `Capabilities`:
    * `maxInputTokens` / `maxOutputTokens` (Int).
    * `supportsText`, `supportsImage`, `supportsAudio`, `supportsVideo` (Bool).
    * `supportsThinking` (Bool) — умеет ли модель в рассуждения.
* **Контроль квот**: Метод получения остатков квот. Если провайдер отдает информацию о `RateLimits` в заголовках (как
  OpenAI или Anthropic) или в теле ошибки (как Antigravity), сервис должен парсить это и отдавать в структурированном
  виде: `resetIn`, `remainingRequests`.

### 2.3. Продвинутый чат

* **Мультимодальность**: Поддержка сообщений с вложениями. Вложения могут быть:
    * `Path`: путь к локальному файлу (сервис сам читает и кодирует в Base64).
    * `Data`: сырые бинарные данные.
    * `String`: текстовое содержимое файла.
* **Smart Non-Streaming**: Эмуляция синхронного ответа для моделей, поддерживающих только поток. Это избавляет
  приложение от написания бойлерплейта по накоплению текста.

---

## 3. Технические решения и их Reasoning (Дополненная часть)

### 3.1. Почему "Identity" и "Credentials" разделены?

**Решение**: В протоколе `LLMAccountSession` мы разделяем `info` (email, провайдер, id проекта) и `credentials` (токены,
ключи).
**Reasoning**: Это позволяет приложению эффективно строить интерфейс. Список аккаунтов в настройках можно грузить из
легкой БД, не обращаясь к Keychain за каждым токеном. Кроме того, для некоторых провайдеров (например, Google) один
логин (email) может иметь доступ к разным проектам — это разные «личности» (Identities) при одних и тех же «ключах» (
Credentials).

### 3.2. Почему "Smart Chat" обязателен?

**Решение**: Метод `chat()` автоматически агрегирует чанки стрима, если это необходимо.
**Reasoning**: Провайдеры типа `antigravity` или `codex` часто работают только через `SSE` (Server-Sent Events). Если
заставлять приложение всегда работать со стримом, это усложнит простые задачи (например, «проверь это слово на
опечатку»). Сервис берет эту сложность на себя.

### 3.3. Почему мы используем TraceID везде?

**Решение**: Каждое действие в рамках одного «намерения» пользователя помечается единым `traceId`.
**Reasoning**: В логах чата мы увидим всю цепочку: `[Trace-123] Refresh Token` -> `[Trace-123] List Models` ->
`[Trace-123] Chat Request`. Это единственный способ понять, почему на самом деле упал чат, если ошибка произошла на
этапе обновления токена.

### 3.4. Маскирование и HAR

**Решение**: Реализация `LLMRedactor`, который по умолчанию включен.
**Reasoning**: Безопасность. Разработчики часто просят пользователей прислать логи при ошибках. Если в логе будет сырой
HAR с `Authorization: Bearer ...`, аккаунт пользователя будет скомпрометирован. Мы даем возможность выключить
маскирование только для локального дебага самого разработчика.

### 3.5. Поддержка Прокси

**Решение**: Конфигурация сервиса включает опциональный `proxyURL`.
**Reasoning**: Многие провайдеры (особенно `google`, `anthropic`) недоступны в ряде стран напрямую. Без встроенной
поддержки прокси на уровне `URLSession`, сервис будет бесполезен для большой части аудитории.

---

## 4. Паттерны внутри LLMService

1. **Proxy / Decorator (Redactor)**: Обертка над данными запроса/ответа, которая «вырезает» чувствительную информацию
   перед сохранением в файл.
2. **Adapter (Translators)**: Мощный слой трансформации. Например, `AntigravityTranslator` преобразует стандартный
   массив сообщений в формат Google Cloud Internal API, включая вставку системных промптов и обработку подписей (
   signatures).
3. **State Machine**: Для управления процессом `ASWebAuthenticationSession`. У процесса есть состояния: `idle`,
   `waitingForCode`, `exchangingToken`, `fetchingUserInfo`.
4. **Repository (External)**: Пакет не хранит данные, он лишь определяет интерфейс репозитория, который реализует
   приложение. Это классический **Dependency Inversion Principle**.

[//]: # (MARK: Part 2)

Это вторая часть проектной документации для **LLMService**, переписанная «на чистовик». Документ объединяет все
утвержденные архитектурные решения, обновленные модели данных и финальный интерфейс взаимодействия.

---

# Часть 2: Детальная спецификация API, моделей и протоколов

Эта часть описывает технический контракт между приложением и сервисом. Все структуры спроектированы для работы в
асинхронной среде Swift (Async/Await) с использованием современных стандартов безопасности Apple.

## 1. Идентификация и Сессии (Account Management)

Мы используем паттерн **Delegated Storage**. Сервис управляет логикой (авторизация, рефреш), но делегирует физическое
сохранение данных приложению.

### 1.1. LLMAccountInfo (Identity)

Объект, описывающий «личность» аккаунта. Приложение может хранить этот объект в базе данных.

```swift
public struct LLMAccountInfo: Codable {
    /// Уникальный ключ, генерируемый приложением (напр. UUID или ID из БД).
    /// Если не задан, приложение берет на себя риск создания дубликатов.
    public let appUniqueKey: String?

    /// Тип провайдера.
    public let provider: LLMProvider

    /// Технический ID (email для OAuth, ID организации для API).
    public var identifier: String?

    /// Человекочитаемое имя для UI (напр. "user@gmail.com" или "Work Account").
    public var displayName: String?

    /// Контекстные данные (project_id для Google, org_id для OpenAI и т.д.).
    public var metadata: [String: String]

    public init(provider: LLMProvider, appUniqueKey: String? = nil, metadata: [String: String] = [:]) {
        self.provider = provider
        self.appUniqueKey = appUniqueKey
        self.metadata = metadata
    }
}
```

### 1.2. LLMCredentials (Secrets)

Объект с чувствительными данными, которые приложение должно сохранять в **Keychain**.

```swift
public struct LLMCredentials {
    public var apiKey: String?
    public var accessToken: String?
    public var refreshToken: String?
    public var expiresAt: Date?

    public init(apiKey: String? = nil, accessToken: String? = nil, refreshToken: String? = nil, expiresAt: Date? = nil) {
        self.apiKey = apiKey
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.expiresAt = expiresAt
    }
}
```

### 1.3. Протокол LLMAccountSession

Единственный мост между сервисом и хранилищем приложения.

```swift
public protocol LLMAccountSession: AnyObject {
    /// Возвращает текущую информацию об аккаунте
    var info: LLMAccountInfo { get }

    /// Вызывается сервисом для получения токенов/ключей перед каждым сетевым запросом
    func getCredentials() async throws -> LLMCredentials

    /// Вызывается сервисом после успешного Login или Refresh.
    /// Приложение должно сохранить info (в БД) и credentials (в Keychain).
    func save(info: LLMAccountInfo, credentials: LLMCredentials) async throws
}
```

---

## 2. Работа с контентом (Multi-modal API)

### 2.1. LLMContent (Input)

Мы используем «умный» интерфейс для файлов, чтобы упростить работу разработчика.

```swift
public enum LLMContent {
    case text(String)

    /// «Ленивый» интерфейс. Сервис сам определяет:
    /// - Если MIME-тип мультимедийный (.png, .mp3, .pdf) -> шлет как мультимодальные данные.
    /// - Если текстовый (.txt, .swift, .log) -> читает и вставляет в промпт с разделителями.
    case file(URL)

    /// Явная передача данных.
    case fileContent(Data, mimeType: String, filename: String?)
}

public struct LLMMessage {
    public let role: LLMChatRole
    public let content: [LLMContent]

    public enum LLMChatRole: String, Codable {
        case system, user, assistant, tool
    }
}
```

---

## 3. Результаты ответов (Unified Output)

Ответы разделены на части (**Parts**), где каждая часть имеет строго один тип. Это позволяет корректно обрабатывать
перемешанные данные (мысли -> инструменты -> текст).

### 3.1. LLMResponse (Non-streaming)

```swift
public struct LLMResponse {
    public let id: String
    public let model: String
    public let traceId: String
    public let content: [LLMResponsePart]
    public let usage: LLMUsage?

    /// Удобный метод: возвращает только текст, склеенный из всех .text частей.
    public var fullText: String {
        content.compactMap {
            part -> String? in
            if case .text(let str) = part {
                return str
            }
            return nil
        }.joined()
    }
}

public enum LLMResponsePart {
    case thinking(String)
    case text(String)
    case toolCall(id: String, function: String, arguments: String)
}
```

### 3.2. LLMChatChunk (Streaming)

```swift
public struct LLMChatChunk {
    public let id: String
    /// Тип контента в этом чанке. Позволяет UI переключать отображение (напр. начать рисовать блок мыслей).
    public let partType: LLMPartTypeDelta
    public let delta: String
    public let usage: LLMUsage?
    // Только в финальном чанке
}

public enum LLMPartTypeDelta {
    case thinking , text , toolCall(id: String, function: String)
}
```

---

## 4. Модели моделей и квот

### 4.1. LLMModelInfo

Детальное описание возможностей модели для адаптации UI приложения.

```swift
public struct LLMModelInfo {
    public let id: String
    public let displayName: String

    // Возможности
    public let supportsText: Bool
    public let supportsImage: Bool
    public let supportsAudio: Bool
    public let supportsVideo: Bool
    public let supportsThinking: Bool
    public let supportsTools: Bool

    // Технические режимы
    public let supportsStreaming: Bool
    public let supportsNonStreaming: Bool

    // Лимиты
    public let maxInputTokens: Int?
    public let maxOutputTokens: Int?
    public let contextLength: Int?
}
```

### 4.2. LLMQuotaStatus

```swift
public struct LLMQuotaStatus {
    public let modelId: String
    public let isAvailable: Bool
    public let resetIn: TimeInterval?
    public let remainingRequests: Int?
}
```

---

## 5. Конфигурация и Логирование

Мы используем систему OSLog для системных нужд и JSON-файлы для глубокого трейсинга.

```swift
public struct LLMLoggingConfig {
    /// Имя подсистемы для OSLog (напр. "com.myapp.llmservice")
    public let subsystem: String?

    /// Локальная директория для хранения JSON-логов запросов
    public let storageDirectory: URL?

    /// Флаг маскирования токенов и ключей (default: true)
    public var shouldMaskTokens: Bool

    public init(subsystem: String? = nil, storageDirectory: URL? = nil, shouldMaskTokens: Bool = true) {
        self.subsystem = subsystem
        self.storageDirectory = storageDirectory
        self.shouldMaskTokens = shouldMaskTokens
    }
}
```

---

## 6. Public API: LLMService

Основной класс, инкапсулирующий всю логику.

```swift
public final class LLMService {
    public let session: LLMAccountSession
    public let loggingConfig: LLMLoggingConfig

    /// Поддержка прокси-сервера (опционально)
    public var proxyURL: URL?

    public init(session: LLMAccountSession, loggingConfig: LLMLoggingConfig)

    // MARK: - Auth

    /// Инициализирует вход через ASWebAuthenticationSession.
    /// После успеха Service сам дергает session.save()
    public func login() async throws

    /// Получение информации об аккаунте (выполняется через провайдера)
    public func getAccountInfo() async throws -> LLMAccountInfo

    // MARK: - Chat Methods

    /// Умный чат: автоматически эмулирует non-streaming через накопление стрима, 
    /// если модель поддерживает только поток.
    public func chat(modelId: String,
    messages: [LLMMessage],
    thinking: ThinkingConfig? = nil,
    idempotencyKey: String? = nil) async throws -> LLMResponse

    /// Стриминг чата
    public func chatStream(modelId: String,
    messages: [LLMMessage],
    thinking: ThinkingConfig? = nil,
    idempotencyKey: String? = nil) -> AsyncThrowingStream<LLMChatChunk, Error>

    // MARK: - Inspection

    public func listModels() async throws -> [LLMModelInfo]

    public func getQuotaStatus(formodelId: String) async throws -> LLMQuotaStatus

    // MARK: - Debug

    /// Собирает все JSON файлы из storageDirectory за период и отдает HAR-файл.
    /// Доп. данные (TraceID, AccountIdentifier) пишутся в поле 'comment'.
    public func exportHAR(lastMinutes: Int) async throws -> Data
}
```

---

## 7. Внутренняя логика (Reasoning для разработчика)

### 7.1. Механизм "Smart File" (.file case)

Внутри сервиса при получении `LLMContent.file(URL)`:

1. Определяем расширение.
2. Если это изображение/видео/аудио — используем `fileContent` с соответствующим MIME.
3. Если это текст — читаем содержимое и оборачиваем его:
   `"--- FILE: <filename> ---\n<content>\n--- END FILE ---"`.

### 7.2. Механизм "Smart Chat"

Если вызван `chat()`, а провайдер (напр. `antigravity`) умеет только стрим:

1. Сервис создает `AsyncThrowingStream` (через `chatStream`).
2. Итерируется по нему, сохраняя `id`, `usage` и накапливая `delta` в соответствующие `LLMResponsePart`.
3. Когда стрим закрывается, сервис возвращает готовый `LLMResponse`.

### 7.3. Авто-рефреш

При получении HTTP 401:

1. Сервис вызывает `session.getCredentials()`, чтобы получить `refreshToken`.
2. Выполняет запрос на обновление к провайдеру.
3. Вызывает `session.save()` с новыми ключами.
4. Повторяет оригинальный запрос (прозрачно для приложения).

### 7.4. Логирование

Каждая транзакция (даже рефреш токена) записывается в JSON. Поле `category` в OSLog формируется динамически:
`{provider}.{method}.{type}`. Пример: `antigravity.chat.stream`.

# Часть 3: Сценарии использования и примеры (Implementation Guide)

В этой части мы разберем, как интегрировать сервис в реальное приложение, используя паттерны, заложенные в архитектуру.

## 1. Реализация "Моста" (Account Session)

Прежде чем использовать сервис, приложение должно реализовать протокол хранения. Это «чистая» реализация, где данные
разделены между БД и Keychain.

```swift
class AppAccountSession: LLMAccountSession {
    // Представим, что это ваша модель в CoreData/SwiftData/GRDB
    var dbRecord: MyAccountDatabaseModel

    var info: LLMAccountInfo {
        return LLMAccountInfo(
            provider: LLMProvider(rawValue: dbRecord.providerType) ?? .openai,
            appUniqueKey: dbRecord.id, // UUID из вашей базы данных
            metadata: dbRecord.metadataDict
        )
    }

    func getCredentials() async throws -> LLMCredentials {
        // Загружаем секреты из Keychain по ID записи в базе
        let secrets = try KeychainHelper.load(key: dbRecord.id)
        return LLMCredentials(
            apiKey: secrets.apiKey,
            accessToken: secrets.accessToken,
            refreshToken: secrets.refreshToken,
            expiresAt: secrets.expiresAt
        )
    }

    func save(info: LLMAccountInfo, credentials: LLMCredentials) async throws {
        // 1. Обновляем метаданные в основной базе
        dbRecord.identifier = info.identifier
        dbRecord.displayName = info.displayName
        dbRecord.metadataDict = info.metadata
        try dbRecord.save()

        // 2. Обновляем секреты в Keychain
        try KeychainHelper.save(credentials, key: dbRecord.id)
    }
}
```

---

## 2. Flow: Добавление нового OAuth аккаунта (Claude Code / Antigravity)

Разработчику не нужно знать детали OAuth-хендшейка. Сервис сам поднимет окно и обменяет коды на токены.

```swift
func addNewClaudeAccount() async {
    // 1. Создаем пустую запись в БД и сессию
    let newRecord = MyAccountDatabaseModel(provider: .claudeCode)
    let session = AppAccountSession(dbRecord: newRecord)

    // 2. Инициализируем сервис
    let service = LLMService(session: session, loggingConfig: myConfig)

    do {
        // 3. Запускаем логин. В этот момент iOS/macOS покажет системный 
        // диалог "App wants to use cluade.ai to sign in"
        try await service.login()

        // К этому моменту service уже вызвал session.save(), 
        // и в вашей БД есть email и токены.
        print("Successfully logged in as \(session.info.identifier ?? "unknown")")

    } catch {
        // Если ошибка — она содержит traceId для логов
        if let llmErr = error as ? LLMError {
            print("Login failed. TraceID: \(llmErr.traceId)")
        }
    }
}
```

---

## 3. Flow: Использование Smart Chat (Авто-агрегация)

Пример использования метода `chat()`, который скрывает стриминговую природу некоторых моделей.

```swift
func simpleTranslation(text: String, session: LLMAccountSession) async throws -> String {
    let service = LLMService(session: session, loggingConfig: myConfig)

    // Модель 'antigravity' в Go-коде требует стрим, но мы используем chat()
    let response = try await service.chat(
        modelId: "antigravity",
        messages: [
            LLMMessage(role: .system, content: [.text("You are a translator.")]),
            LLMMessage(role: .user, content: [.text("Translate to French: \(text)")])
        ]
    )

    // Используем удобный метод fullText, который склеил все части ответа
    return response.fullText
}
```

---

## 4. Flow: Продвинутый чат со стримингом и размышлениями

Пример для UI, где мы хотим отдельно показывать процесс «раздумий» модели.

```swift
func startChatStream(session: LLMAccountSession) async {
    let service = LLMService(session: session, loggingConfig: myConfig)

    let messages = [LLMMessage(role: .user, content: [.text("Write a complex algorithm")])]
    let stream = service.chatStream(modelId: "claude-3-7-sonnet", messages: messages)

    do {
        for try await chunk in stream {
            switch chunk.partType {
            case .thinking:
                // Обновляем UI блок с серым текстом "Model is thinking..."
                UI.updateThinkingView(delta: chunk.delta)
            case .text:
                // Обновляем основной бабл чата
                UI.updateMainBubble(delta: chunk.delta)
            case .toolCall(let id, let function):
                // Показываем индикатор вызова инструмента
                UI.showToolIndicator(name: function)
            }

            if let usage = chunk.usage {
                print("Total tokens spent: \(usage.totalTokens)")
            }
        }
    } catch {
        handleError(error)
    }
}
```

---

## 5. Flow: Работа с файлами (Smart File Handling)

Сервис берет на себя рутину по определению типа контента.

```swift
func sendCodeReviewRequest(fileURL: URL, session: LLMAccountSession) async throws {
    let service = LLMService(session: session, loggingConfig: myConfig)

    let message = LLMMessage(role: .user, content: [
        .text("Please review this file for bugs:"),
        // Сервис сам поймет: если это .swift — прочитать как текст,
        // если это .png со скриншотом ошибки — отправить как изображение.
        .file(fileURL)
    ])

    let response = try await service.chat(modelId: "gemini-2.0-pro", messages: [message])
    print(response.fullText)
}
```

---

## 6. Flow: Дебаггинг и экспорт HAR

Если пользователь жалуется на ошибку, приложение может предложить отправить «технический отчет».

```swift
func prepareSupportDiagnostic(service: LLMService) async throws -> URL {
    // 1. Собираем HAR архив за последние 15 минут
    // Сервис найдет JSON-файлы всех запросов (чат, рефреш токенов, логин)
    let harData = try await service.exportHAR(lastMinutes: 15)

    // 2. Сохраняем во временный файл
    let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("logs.har")
    try harData.write(to: tempURL)

    // 3. Очищаем старые логи, чтобы не забивать память устройства
    try service.cleanupLogs(olderThanDays: 1)

    return tempURL
}
```

---

## 7. Внутренние паттерны (для разработчика LLMService)

### 7.1. Паттерн "Automatic Refresh Retry"

Внутри сетевого слоя сервиса (приватная часть) должна быть реализована следующая логика:

```swift
// Внутри метода выполнения запроса

func performRequest(_ request: URLRequest, traceId: String) async throws -> Data {
    let (data, response) = try await urlSession.data(for: request)

    if (response as ? HTTPURLResponse)?.statusCode == 401 {
        // 1. Пытаемся обновить токен
        let newCredentials = try await self.refreshOAuthToken()

        // 2. Сообщаем приложению, что нужно сохранить новые данные
        try await session.save(info: session.info, credentials: newCredentials)

        // 3. Повторяем исходный запрос с новым токеном
        var newRequest = request
        newRequest.setValue

("Bearer \(newCredentials.accessToken ! )", forHTTPHeaderField: "Authorization") return try await performRequest (newRequest, traceId: traceId)
}

return data
}
```

### 7.2. Паттерн "Dynamic Logger"

При каждом запросе создается `LLMTraceEntry`. Сервис заполняет его поля `request`, а после получения ответа — `response`
и `duration`.

```swift
// Логика формирования системного лога
let category = "\(session.info.provider.rawValue).chat.\(isStream ? "stream": "sync")"
let logger = Logger(subsystem: loggingConfig.subsystem ?? "LLMService", category: category)

// Если включено маскирование:
let displayURL = loggingConfig.shouldMaskTokens ? request.url.sanitized: request.url
logger.debug("[\(traceId)] Sending request to \(displayURL)")
```

---

### Резюме для разработчика:

* **Convenience**: Всегда предоставляйте `fullText` и аналогичные хелперы, чтобы API было «вкусным» для использования.
* **Transparency**: Никогда не «глотайте» ошибки провайдеров — оборачивайте их в `LLMError` с оригинальным кодом и
  `traceId`.
* **Resilience**: Автоматический рефреш токена должен быть незаметен для пользователя.

# Часть 4: Система отладки, логирования и трассировки

## 1. Концепция Трассировки (Tracing)

В основе системы лежит понятие **TraceID** — уникального идентификатора (UUID), который генерируется при каждом вызове
публичного метода API (например, `chat()` или `login()`).

### Жизненный цикл TraceID:

1. **Начало**: Пользователь вызывает `service.chat(...)`. Сервис создает новый `traceId`.
2. **Промежуточные шаги**: Если для выполнения чата требуется обновить токен, запрос на рефреш выполняется с тем же
   `traceId`.
3. **Сетевой слой**: Каждый HTTP-запрос помечается этим ID (в логах и, опционально, в заголовках).
4. **Ошибка**: Если запрос падает, выбрасываемая `LLMError` содержит этот `traceId`.
5. **Финал**: Разработчик может найти все файлы логов, относящиеся к этой операции, используя один идентификатор.

---

## 2. Конфигурация: LLMLoggingConfig

Приложение настраивает логирование один раз при инициализации `LLMService`.

```swift
public struct LLMLoggingConfig {
    /// Имя подсистемы для OSLog (напр. "com.company.app.ai")
    public let subsystem: String?

    /// Директория для хранения JSON-файлов логов. 
    /// Если nil, запись файлов на диск отключена.
    public let storageDirectory: URL?

    /// Флаг маскирования чувствительных данных (ключа АПИ, токенов).
    /// По умолчанию true.
    public var shouldMaskTokens: Bool

    public init(subsystem: String? = nil,
    storageDirectory: URL? = nil,
    shouldMaskTokens: Bool = true) {
        self.subsystem = subsystem
        self.storageDirectory = storageDirectory
        self.shouldMaskTokens = shouldMaskTokens
    }
}
```

---

## 3. Модель лога: LLMTraceEntry

Каждый сетевой запрос (или важное событие) сохраняется на диск как отдельный JSON-файл. Структура файла максимально
приближена к формату HAR, но содержит дополнительные поля.

```swift
public struct LLMTraceEntry: Codable {
    // --- Метаданные трейса ---
    public let traceId: String
    // Группирующий ID
    public let requestId: String
    // ID конкретного HTTP-вызова
    public let timestamp: Date
    public let provider: LLMProvider
    public let accountIdentifier: String?
    // email или ID аккаунта
    public let method: String
    // "chat", "token_refresh", "user_info"
    public let isStreaming: Bool

    // --- Данные запроса ---
    public let request: HTTPDetails

    // --- Данные ответа ---
    public var response: HTTPDetails?
    public var error: String?
    // Описание ошибки, если запрос упал
    public var duration: TimeInterval?

    public struct HTTPDetails: Codable {
        public let url: URL
        public let method: String
        public let headers: [String: String]
        public let body: Data?
        public let statusCode: Int?
    }
}
```

---

## 4. Системные логи (Apple OSLog)

Сервис автоматически распределяет логи по категориям для удобной фильтрации в приложении **Console.app**.

### Алгоритм формирования категории:

Категория имеет формат: `{provider}.{method}.{mode}`

* `openai.chat.sync`
* `claudeCode.chat.stream`
* `antigravity.token_refresh.sync`

Разработчик может ожидать, что `LLMService` будет писать сообщения уровня `.debug` для тела запросов и `.error` для
сбоев API.

---

## 5. Маскирование данных (Redaction)

Если `shouldMaskTokens == true`, сервис применяет `LLMRedactor` перед записью лога на диск или выводом в OSLog.

**Что подлежит маскированию:**

1. **Заголовки**: `Authorization`, `api-key`, `x-goog-api-key`, `Cookie`.
2. **Тело запроса**: Поля JSON `access_token`, `refresh_token`, `session_key`.
3. **URL**: Параметры запроса, содержащие токены (например, для некоторых OAuth callback-ов).

*Примечание: Маскирование заменяет значение на строку `"REDACTED (sha256_suffix)"`, где суффикс — это последние 4
символа хеша, чтобы можно было понять, использовался ли один и тот же токен в разных запросах, не зная самого токена.*

---

## 6. Экспорт в HAR (HTTP Archive)

Одной из ключевых функций является метод `exportHAR`. Он позволяет превратить разрозненные JSON-файлы в один стандартный
файл, который можно открыть в **Proxyman**, **Charles** или браузере.

### Метод API:

```swift
/// Собирает историю запросов и упаковывает в формат HAR 1.2
/// - Parameter lastMinutes: Глубина поиска логов на диске
/// - Returns: Data, содержащая JSON в формате HAR
public func exportHAR(lastMinutes: Int) async throws -> Data
```

### Реализация экспорта:

1. Сервис сканирует `storageDirectory`.
2. Читает все файлы, дата создания которых входит в указанный интервал.
3. Группирует их по `traceId`.
4. Для каждого запроса заполняет стандартные поля HAR (`log.entries`).
5. **Поле "comment"**: В HAR-запись каждого запроса добавляется расширенная информация в поле `comment`:
   ```json
   "comment": "TraceID: 550e8400-e29b; Provider: antigravity; Account: dev@example.com; Method: chat_translated"
   ```

---

## 7. Обработка ошибок и TraceID

Когда сервис выбрасывает `LLMError`, он гарантирует, что разработчик сможет найти «концы» в логах.

```swift
do {
    try await service.chat(...)
} catch let error as LLMError {
    // Разработчик может вывести это в алерт или логгер приложения
    print("Ошибка API: \(error.message). Для диагностики используйте TraceID: \(error.traceId)")

    // В папке логов теперь гарантированно лежит файл {error.traceId}.json
}
```

---

## 8. Автоматическая очистка (Maintenance)

Чтобы не забивать память устройства (особенно если логов много и они содержат тяжелые бинарные данные), сервис реализует
логику ротации.

```swift
/// Рекомендуется вызывать при запуске приложения или перед экспортом
public func cleanupLogs(olderThanDays days: Int) throws
```

Метод удаляет все файлы из `storageDirectory`, дата изменения которых превышает заданный порог.

---

## 9. Чего ожидать разработчику (Best Practices)

1. **Конфиденциальность**: Включайте `shouldMaskTokens = true` для всех релизных сборок. Выключайте только в процессе
   внутренней разработки.
2. **Объем данных**: Помните, что `LLMTraceEntry` сохраняет тело запроса полностью. Если вы часто пересылаете файлы (
   фото/аудио), папка логов будет расти быстро.
3. **Имена файлов**: Файлы на диске именуются по принципу `YYYYMMDD_HHmmss_TraceID.json` для естественной сортировки в
   файловой системе.
4. **Асинхронность**: Запись логов на диск происходит в фоновом режиме (через выделенную `DispatchQueue` или `Actor`),
   чтобы не блокировать основной поток выполнения запроса.

Это пятая часть проектной документации. Она закрывает критический вопрос качества и надежности библиотеки. Без
соблюдения этих принципов разработка превратится в кошмар при первой же попытке отладить сложный сценарий (например,
рефреш токена во время стриминга).

---

# Часть 5: Требования к тестируемости и Руководство по реализации (Testability Guide)

Поскольку **LLMService** является библиотекой (SDK), от которой зависит стабильность хост-приложения, к качеству кода
предъявляются повышенные требования. Мы не можем полагаться на то, что у CI/CD сервера есть доступ в интернет или
аккаунт Google.

## 1. Философия: "Zero I/O in Unit Tests"

Все Unit-тесты должны работать:

1. **Без сети**: Никаких реальных запросов к OpenAI или Google.
2. **Без UI**: Никаких всплывающих окон браузера (`ASWebAuthenticationSession`).
3. **Мгновенно**: Тест не должен ждать `sleep(5)` для проверки таймаута.

Для достижения этого архитектура сервиса должна строиться на принципе **Dependency Injection (DI)**.

---

## 2. Абстракция Сетевого Слоя (HTTPClient)

Сервис **не должен** использовать `URLSession.shared` напрямую в методах бизнес-логики. Вместо этого он должен зависеть
от протокола.

### 2.1. Протокол HTTPClient

Этот протокол должен уметь обрабатывать как обычные запросы, так и потоковые.

```swift
public protocol HTTPClient: Sendable {
    /// Выполняет обычный запрос (аналог URLSession.data(for:))
    func data(forrequest: URLRequest) async throws -> (Data, HTTPURLResponse)

    /// Выполняет потоковый запрос (аналог URLSession.bytes(for:))
    /// Возвращает AsyncSequence байт
    func bytes(forrequest: URLRequest) async throws -> (AnyAsyncSequence<UInt8>, HTTPURLResponse)
}

// Обертка для стирания типа (Type Erasure), чтобы тесты могли подсовывать свои стримы

public struct AnyAsyncSequence<Element>: AsyncSequence, Sendable {
    public typealias Element = Element
    private let _makeAsyncIterator: @Sendable () -> AsyncIterator

    public init<S: AsyncSequence>(_ base: S) where S.Element == Element, S: Sendable {
        self._makeAsyncIterator = {
            AnyAsyncSequence.AsyncIterator(base.makeAsyncIterator())
        }
    }

    public func makeAsyncIterator() -> AsyncIterator {
        _makeAsyncIterator()
    }

    public struct AsyncIterator: AsyncIteratorProtocol {
        private var _next: () async throws -> Element?

        init<I: AsyncIteratorProtocol>(_ iterator: I) where I.Element == Element {
            var iterator = iterator
            self._next = {
                try await iterator.next()
            }
        }

        public mutating func next() async throws -> Element? {
            try await _next()
        }
    }
}
```

### 2.2. Реализация для Production

Разработчик должен создать обертку над `URLSession`.

```swift
final class URLSessionClient: HTTPClient {
    private let session: URLSession

    init(configuration: URLSessionConfiguration = .default) {
        self.session = URLSession(configuration: configuration)
    }

    func data(forrequest: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as ?HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        return (data, httpResponse)
    }

    func bytes(forrequest: URLRequest) async throws -> (AnyAsyncSequence<UInt8>, HTTPURLResponse) {
        let (bytes, response) = try await session.bytes(for: request)
        guard let httpResponse = response as ?HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        return (AnyAsyncSequence(bytes), httpResponse)
    }
}
```

---

## 3. Абстракция Авторизации (OAuthSessionLauncher)

Тесты не могут нажимать кнопки в браузере. Мы должны изолировать запуск системного окна.

### 3.1. Протокол

```swift
public protocol OAuthSessionLauncher: Sendable {
    /// Запускает флоу авторизации.
    /// - Parameters:
    ///   - url: URL, который нужно открыть в браузере.
    ///   - callbackScheme: Схема, которую мы ждем (напр. "myapp").
    /// - Returns: Полный URL коллбэка (напр. "myapp://auth?code=123").
    @MainActor func authenticate(url: URL, callbackScheme: String?) async throws -> URL
}
```

---

## 4. Инициализация LLMService (Внедрение зависимостей)

Чтобы это работало, у `LLMService` должно быть два инициализатора: публичный (для удобства) и внутренний (для тестов).

```swift
public final class LLMService {
    // Внутренние свойства, закрытые протоколами
    internal let httpClient: HTTPClient
    internal let oauthLauncher: OAuthSessionLauncher

    // MARK: - Internal Init (для тестов)

    internal init(session: LLMAccountSession,
    loggingConfig: LLMLoggingConfig,
    httpClient: HTTPClient,
    oauthLauncher: OAuthSessionLauncher) {
        self.session = session
        self.loggingConfig = loggingConfig
        self.httpClient = httpClient
        self.oauthLauncher = oauthLauncher
    }

    // MARK: - Public Init (для приложения)

    public convenience init(session: LLMAccountSession,
    loggingConfig: LLMLoggingConfig) {
        // В продакшене подставляем реальные реализации
        let realClient = URLSessionClient()
        let realLauncher = SystemOAuthLauncher()

        self.init(
            session: session,
            loggingConfig: loggingConfig,
            httpClient: realClient,
            oauthLauncher: realLauncher
        )
    }
}
```

---

## 5. Как писать Mocks (Инструкция для разработчика)

Разработчик обязан реализовать класс `MockHTTPClient` для тестов.

### 5.1. Требования к MockHTTPClient

1. **Сценарии**: Мок должен уметь принимать массив ответов (очередь). Например:
   `[401 Unauthorized, 200 OK (Token), 200 OK (Chat Response)]`.
2. **Инспекция**: Мок должен сохранять все пришедшие запросы (`capturedRequests`), чтобы тест мог проверить заголовки (
   `Authorization: Bearer new_token`).
3. **Контролируемый поток**: Для тестирования стриминга мок должен уметь отдавать байты с задержкой или по команде (
   чтобы проверить отмену запроса).

### 5.2. Пример теста сложного сценария (Refresh Token)

```swift
func testRefreshTokenFlow() async throws {
    // 1. Настраиваем Mock
    let mockClient = MockHTTPClient()
    mockClient.enqueue(response: .error(401)) // Первый запрос чата упадет
    mockClient.enqueue(response: .json(["access_token": "new_fake_token"])) // Рефреш успешен
    mockClient.enqueue(response: .json (["choices": [...]])) // Повтор чата успешен let service = LLMService (..., httpClient: mockClient, ...)

// 2. Действие _ = try await service.chat (modelId: "gpt", messages: [])

// 3. Проверки XCTAssertEqual (mockClient.requestCount, 3)
// Проверяем, что 3-й запрос ушел с НОВЫМ токеном XCTAssertEqual (mockClient.requests[2].header ("Authorization"), "Bearer new_fake_token")
}
```

---

## 6. Что нужно протестировать (Checklist)

Разработчик должен покрыть тестами следующие аспекты:

1. **Сериализация запросов**:
    * Проверить, что для `LLMProvider.anthropic` JSON-тело формируется в формате `{ "messages": [...] }`.
    * Проверить, что для `LLMProvider.antigravity` добавляются специфичные поля `client_metadata`.
2. **Обработка ответов**:
    * Парсинг ошибок (превращение JSON-ошибки провайдера в `LLMError` с правильным кодом).
    * Склейка чанков в методе `chat()` (Smart Non-Streaming).
3. **Логика авторизации**:
    * Проверить, что `login()` вызывает `save()` у сессии.
    * Проверить формирование `state` и `PKCE` параметров для OAuth URL.
4. **Дебаг**:
    * Проверить, что `LLMRedactor` реально заменяет токены на `REDACTED` в логах.

---

## 7. Рекомендации по структуре проекта

```
LLMService/
├── Sources/
│   ├── Core/
│   │   ├── LLMService.swift
│   │   ├── LLMAccountSession.swift
│   ├── Networking/
│   │   ├── HTTPClient.swift (Protocol + URLSession impl)
│   │   ├── OAuthLauncher.swift (Protocol + ASWeb impl)
│   ├── Translators/
│   │   ├── OpenAITranslator.swift
│   │   ├── GeminiTranslator.swift
├── Tests/
│   ├── Mocks/
│   │   ├── MockHTTPClient.swift
│   │   ├── MockOAuthLauncher.swift
│   │   ├── MockAccountSession.swift
│   ├── LLMServiceTests.swift
```

Соблюдение этих требований гарантирует, что `LLMService` будет стабильным, предсказуемым и легким в поддержке.
