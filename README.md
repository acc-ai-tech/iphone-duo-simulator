# DuoPreviewKit

Эмуляция форм-фактора iPhone Duo (складной iPhone) внутри приложения, запущенного в симуляторе **iPad Pro 13"**.
Размеры экранов, fold/unfold, полусложенное положение, трейты/environment, debug-панель, скриншоты, stress test,
управление из терминала.

```
Package.swift, Sources/, Tests/   Swift Package DuoPreviewKit (iOS 17+, Swift 6)
Examples/DuoExampleUIKit/      тестовое UIKit-приложение (split view, лента, галерея, чат, формы, видео, модалки, posture)
Examples/DuoExampleSwiftUI/    тестовое SwiftUI-приложение (NavigationSplitView, reader/player по posture/hingeRect)
NOTES.md                       решения, результаты исследований, ограничения, открытые вопросы
```

## Быстрый старт (тестовые приложения)

```sh
cd Examples/DuoExampleUIKit && xcodegen generate && open DuoExampleUIKit.xcodeproj
cd Examples/DuoExampleSwiftUI && xcodegen generate && open DuoExampleSwiftUI.xcodeproj
```

В Debug эмулятор включается сам, аргументы не нужны (в т.ч. при запуске с домашнего экрана симулятора).
Destination: **iPad Pro 13-inch**. Дополнительные аргументы примеров:

| Аргумент | Что делает |
|---|---|
| `-screen <name>` | открыть экран сразу. UIKit: `feed gallery article chat form video modals deepNavigation posture`. SwiftUI: `library grid reader compose player settings posture` |
| `-duoPresets /path/presets.json` | подменить пресеты (`DuoPreview.configure(presetsURL:)`) |

## Подключение в своё приложение

**Xcode:** File → Add Package Dependencies… → URL репозитория → продукт `DuoPreviewKit` в app target.
Локально: Add Local… → корень репозитория.

**Package.swift:**
```swift
dependencies: [
    .package(url: "https://github.com/<owner>/<repo>.git", from: "0.1.0"),
],
targets: [
    .target(name: "App", dependencies: [.product(name: "DuoPreviewKit", package: "<repo>")]),
]
```

```swift
#if DEBUG
import DuoPreviewKit
#endif

// UIKit (SceneDelegate) — до makeKeyAndVisible
window.rootViewController = root
#if DEBUG
DuoPreview.install(in: window)
#endif
window.makeKeyAndVisible()

// SwiftUI
WindowGroup { RootView().duoPreviewHost() }
```

Включается в DEBUG по умолчанию; выключить — `-DuoPreviewOff` или `DUO_PREVIEW=0`. В release всегда выключен.
В остальных случаях все API — no-op (`posture == .open`, `contentSize` = размер окна).

Чтение позы: `traitCollection.duoPosture`, `traitCollection.duoHinge` (UIKit), `@Environment(\.duoPosture)`,
`@Environment(\.duoHinge)` (SwiftUI), `DuoPreview.posture / hingeAngle / hingeRect`, `DuoPreview.onStateChange`,
`statePublisher`, `stateStream`. `hingeRect` — в координатах корневого view контента.

## Управление

**Панель** — сверху, над устройством (перетаскивается за заголовок, сворачивается в кнопку). Простой вид: пресеты,
Fold, угол, 3D, анимация (3D fold / Live resize / Instant), Blur, Screenshots. **Advanced** добавляет stress test,
свой размер, Frame/Hinge/Sizes, шаги Live resize. Показывается при каждом запуске; скрыть: ⌘⇧D или двойной тап тремя пальцами.
**Side toolbar** (включён по умолчанию, кнопка на панели): в Open Landscape и Outer кнопки navigation bar и toolbar
(назад, поиск, кнопки баров, переключатель сайдбара) переносятся в стеклянную капсулу у правого края, бары приложения
скрываются, контент получает safe area справа (`sideToolbarWidth` в JSON, флаг `sideToolbar` у пресета).
В полураскрытом положении бары приложения возвращаются.
Если окно меньше экрана Duo (Stage Manager, ландшафт), устройство показывается уменьшенным — размеры контента в pt не меняются.

| Клавиши | Действие |
|---|---|
| ⌘1…⌘5 | пресеты (порядок из JSON) |
| ⌘F | fold / unfold |
| ⌘← / ⌘→ | угол −/+15° |
| ⌘⇧A | режим анимации realistic → continuous → none |
| ⌘⇧S | скриншоты всех состояний → `Documents/DuoPreview/<timestamp>/` |

В симуляторе нужно включить I/O → Keyboard → Send Keyboard Input to Device (или ⌘⇧K).

**Терминал** (Darwin notifications):

```sh
N() { xcrun simctl spawn booted notifyutil -p "com.duolab.$1"; }
N fold; N unfold
N state.inner.portrait            # outer | inner.landscape | inner.portrait | inner.split.half | inner.split.stacked
N angle.90                        # 0…180, шаг 5
N anim.continuous                 # realistic | continuous | none
N option.3d.on                    # frame | hinge | 3d | blur | sidetoolbar | sizes | hud | advanced  × on | off
N report                          # → Library/Caches/duolab-report.json
cat "$(xcrun simctl get_app_container booted <bundle-id> data)/Library/Caches/duolab-report.json"
```

## Тесты пакета

```sh
xcodebuild test -scheme DuoPreviewKit -destination 'platform=iOS Simulator,name=iPad Pro 13-inch (M5)'
```
