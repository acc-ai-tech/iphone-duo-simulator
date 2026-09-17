# NOTES — DuoPreviewKit

Окружение проверки: Xcode 27.0, Swift 6.4, iOS 27.0 simulator, **iPad Pro 13-inch (M5)** (1032×1376 pt), 2026-09-17.

## Статус этапов

| Этап | Статус | Проверено |
|---|---|---|
| M1 ядро | готово | 32 юнит-теста; UIKit-пример в симуляторе во всех пресетах |
| M2 SwiftUI + трейты | готово | SwiftUI-пример: environment, size class, NavigationSplitView collapse |
| M3 анимации | готово | покадровые скриншоты realistic и continuous (замедленный JSON через `-duoPresets`) |
| M4 HUD и клавиатура | готово | HUD визуально; key commands собраны, **нажатия в симуляторе не проверены** (нет автоматизации клавиатуры) |
| M5 полусложенное положение | готово | 3D-вид в портрете и ландшафте, плашка «preview only», `hingeRect` в UIKit и SwiftUI |
| M6 инструменты | готово | скриншоты всех состояний и stress test (юнит-тесты), `notifyutil` из терминала, report JSON |

Сборка пакета и обоих примеров: 0 warnings (кроме системного `appintentsmetadataprocessor`, к коду не относится).

## Решения

- **Все размеры, пороги, тайминги только из `DuoPresets.json`.** В коде нет чисел для размеров экрана, углов и порогов.
  Цвета и отступы HUD/рамки — визуальные константы, не часть модели.
- **Split-пресеты** (`inner.split.half`, `inner.split.stacked`) ссылаются на физический экран (`"screen": "inner.landscape"`).
  Рамка устройства рисуется по полному внутреннему экрану, вторая половина — плейсхолдер «другое приложение».
  Шарнир лежит ровно на границе контента, поэтому `hingeRect == .null` (правило: шарнир принадлежит контенту,
  только если его осевая линия строго внутри контента).
- **Выбор пресета через ⌘N / `state.<id>`**: внутренние пресеты сохраняют текущий угол, если внутренний экран уже активен
  (можно переключать ориентацию в halfOpen); из outer — угол `angles.open`. `outer` — угол `angles.closed`.
- **Токены состояний** для JSON-списков скриншотов и stress test: `presetId[@angle]`, например `inner.portrait@90`.
- **`DuoPreview.state` — целевое состояние.** Коммитится в начале перехода; наблюдатели и HUD видят цель сразу.
  Во время `.continuous` трейты posture/hinge меняются при пересечении порогов posture, в конце выставляется целевой угол.
  При изменении угла без анимации (слайдер HUD, `setHingeAngle(_:animated: false)`) трейты обновляются на каждое изменение.
- **Release**: проверено в рантайме — Release-сборка примера с `-DuoPreview` работает на весь iPad, без HUD, логов
  и реакции на `notifyutil`.
- **Параллельные запросы**: пока идёт переход, новый запрос ставится в очередь; побеждает последний, completion'ы всех вызываются.
- **API async-варианта** называется `DuoPreview.transition(to:animation:) async`, а не перегрузка `set`
  (sync/async перегрузки с одинаковой сигнатурой делают вызов без `await` в async-контексте неоднозначным).
- **Transition coordinator**: собственный `DuoTransitionCoordinator` (протокол `UIViewControllerTransitionCoordinator`).
  Alongside-блоки выполняются внутри `UIView.animate` эмулятора, completion — по окончании.
  Хост **не** вызывает `super.viewWillTransition` при повороте iPad — размер контента от окна не зависит.
- **Снимки для створок**: `drawHierarchy(in:afterScreenUpdates:)` в `UIImage` + `CALayer.contentsRect` для половин,
  вместо `resizableSnapshotView`. Так один и тот же код работает для анимации и для 3D-вида с обновлением по таймеру.
  Снимается тело устройства (рамка + экран + линия шарнира), поэтому створки выглядят как устройство.
- **Геометрия `.realistic`**: створки поворачиваются симметрично на `(180−angle)/2` каждая (V-образно к зрителю).
  На внешнем экране одна створка поворачивается на `angle/displaySwitchAngle × rotation(displaySwitchAngle)`,
  так что на пороге углы совпадают и переключение выглядит непрерывно.
- **Смена ориентации/split без пересечения порога** в `.realistic` — обычный анимированный UIKit-переход (без створок).
- **Внешнее управление расширено** командами `com.duolab.option.<frame|hinge|3d|sizes|hud>.<on|off>`:
  без них из терминала нельзя проверить 3D-вид (cfprefsd кэширует UserDefaults, запись plist снаружи не работает).
- **LifecycleTracker** без swizzling: `DuoPreview.track(self)` считает загрузки, `deinit` ловится через associated object.

- **Включение (изменено по запросу)**: в DEBUG эмулятор включён по умолчанию, `-DuoPreview` больше не нужен;
  выключение — `-DuoPreviewOff` / `DUO_PREVIEW=0`. Отклонение от исходной спецификации (там требовался аргумент).
- **Маленькое окно** (Stage Manager, ландшафт iPad): вместо отключения устройство масштабируется `transform`'ом
  (минимум 50%), контент сохраняет точные размеры в pt и трейты. Панель сверху резервирует место, устройство центрируется ниже.
- **Blur в 3D fold**: размытые копии снимков (`CIGaussianBlur`) cross-fade поверх створок; в конце размытый снимок
  нового состояния растворяется в живой контент. Параметры: `blurRadius`, `blurRampFraction`, `blurFadeOut`.
- **Панель**: простой вид и Advanced; высота панели пересчитывается через `preferredContentSize` хостинга SwiftUI
  (синхронный `sizeThatFits` сразу после смены состояния отдавал старую высоту).

- **Side toolbar** (по запросу): для пресетов с `"sideToolbar": true` (outer, inner.landscape) в плоском положении
  хост находит видимые `UINavigationController` контента, скрывает их navigation bar / toolbar и показывает кнопки
  иконками в капсуле `UIGlassEffect` (iOS 26+, до — blur) справа; `additionalSafeAreaInsets.right += sideToolbarWidth`.
  Нажатия: `UIAction.performWithSender`, `sendAction(target/action)`, `menu`, `UIControl.sendActions`; «назад» — `popViewController`;
  для split view — кнопка показа/скрытия сайдбара; для `searchController` — кнопка, временно показывающая бар.
  Сканирование каждые 0.3 с (без делегатов и swizzling), бары восстанавливаются при выходе из состояния.
  **Ограничения**: `UIBarButtonItem(systemItem:)` без action не отличить от разделителя публичными API — такие кнопки
  пропадают (в UIKit-примере «+» в Feed); у системных кнопок с action нет иконки — показывается буква/знак вопроса;
  приложение, само управляющее видимостью navigation bar, будет конфликтовать со скрытием.
- **50/50 в полураскрытом положении** — поведение примеров, не эмулятора: split view (UIKit) и NavigationSplitView
  (SwiftUI) ставят ширину сайдбара = `hingeRect.minX` при `.halfOpen` и вертикальном шарнире.

## Исследования

### Перенос SwiftUI-корня в child (`.duoPreviewHost()`)
**Работает, выбран основной вариант.** `UIHostingController` из `WindowGroup` становится child хоста.
Проверено в `DuoExampleSwiftUI`: NavigationSplitView, `.searchable`, `.sheet`, `@State`, environment из трейтов
(`UITraitBridgedEnvironmentKey`), `horizontalSizeClass` меняется при fold/unfold, состояние не сбрасывается.

Побочный эффект, найденный и исправленный: установка через один `DispatchQueue.main.async` давала
«Unbalanced calls to begin/end appearance transitions» у `UIHostingController`. Двойной `async` (после завершения
появления корня) убирает предупреждение. Первый кадр приложения при этом рисуется в полный размер iPad.
Для UIKit то же предупреждение возникало при `install` после `makeKeyAndVisible`; рекомендуемый порядок —
`install` **до** `makeKeyAndVisible` (так в примере).

Fallback `DuoPreviewHostView { content }` реализован (frame, size class, safe area, Duo environment), но без рамки,
HUD-хоста и `viewWillTransition`; оставлен на случай, если перенос корня сломается в будущих версиях SwiftUI.

**Координаты `hingeRect` в SwiftUI**: `.global` в `UIHostingController` не совпадает с координатами контента.
Нужно объявить `.coordinateSpace(.named(...))` на корневом view и конвертировать через него (так в примере).

### Живой контент на двух 3D-створках публичными API
**Не получилось, используются снимки.** Анализ:
- Один `CALayer` рендерится в дереве ровно один раз; показать живой слой в двух местах с разными трансформами
  можно только через `CAReplicatorLayer`.
- `CAReplicatorLayer` применяет **накопительный** `instanceTransform` (инстанс 0 всегда без трансформа)
  и **одну** маску на весь репликатор; маскировать половину для каждого инстанса отдельно нельзя.
  Вложенные репликаторы требуют, чтобы живой view был sublayer'ом двух разных родителей — невозможно.
- `_UIPortalView` / `CAPortalLayer` дали бы решение, но это приватные API.

Итог: 3D-вид = снимки `drawHierarchy(afterScreenUpdates: false)` по таймеру `halfOpen3DFPS` (15 fps), взаимодействие
выключено, плашка «3D preview only». Анализ теоретический: прототип на `CAReplicatorLayer` не собирался.

## Найденные баги (исправлены)

- `ImageDiff`: общий `CIContext` возвращал нулевую разницу при последовательных сравнениях CGImage из
  `UIGraphicsImageRenderer` (первое сравнение `a` vs `a`, затем `a` vs `b` → 0 пикселей). Отдельный скрипт на macOS
  и изолированный тест в симуляторе считали верно. Исправлено: новый `CIContext(options: [.cacheIntermediates: false])`
  на каждое сравнение; подсчёт через `CGContext` RGBA8 (известный порядок строк).
- HUD при первом показе оказывался слева поверх устройства (позиция считалась до получения bounds).
- Плашка «preview only» перекрывалась оверлеем створок.

## Известные ограничения

- **Модальные окна** (проверено скриншотами, `DuoExampleUIKit -screen modals -present <style>`, inner.landscape):
  - `.overCurrentContext` / `.currentContext` при `definesPresentationContext = true` на презентующем VC —
    **внутри** области Duo (в примере покрывают detail-колонку).
  - `.formSheet` / `.pageSheet` — центрируются по окну iPad и **выходят** за границы экрана Duo по высоте.
    `definesPresentationContext` на эти стили не влияет; перехватить без swizzling нельзя.
  - `UIAlertController(.alert)` — центр окна iPad (при центрированном устройстве визуально внутри, но не привязан к Duo).
  - sheet с detents (`.medium`) — позиционирует UIKit относительно окна; в ландшафте оказался у нижнего края области Duo,
    гарантий нет.
  - Размер модального контента и его size class берутся от окна iPad, а не от пресета Duo.
  - Юнит-тест на положение модалок не получился: `UIWindow(frame:)` без сцены в xctest не завершает `present`.
- **Клавиатура** показывается на весь iPad. `keyboardLayoutGuide` у контента считает пересечение с реальной клавиатурой
  iPad, а не с экраном Duo; эмулировать высоту клавиатуры Duo публичными API нельзя.
- **Алерты, action sheet, popover, activity view, системные шиты** позиционируются UIKit относительно окна iPad.
- **Status bar / home indicator** — от iPad; safe area Duo задаётся только через `safeAreaInsets` в JSON (пока нули).
- **Stage Manager / Split View iPad**: если окно становится меньше внутреннего экрана Duo, эмулятор не масштабирует контент.
  Проверка размера выполняется только при `install`.
- **Первый кадр** SwiftUI-приложения рисуется в размер iPad до установки хоста.
- **Darwin notifications, отправленные до установки хоста** (первые ~0.5–1 с после запуска), теряются.
- `.continuous` в промежуточных размерах показывает реальные артефакты UIKit (например, large title
  navigation bar перекрывает первую строку списка при быстром ресайзе). Это ожидаемо: режим для поиска таких багов.
- В `.realistic` на время анимации контент скрыт оверлеем, `DuoPreview.state` уже равен цели.

## Производительность `.continuous`

После каждой непрерывной анимации пишется лог `continuous: N frames in T s (X fps)`.
Замер: fold/unfold ×3, Debug-сборка (`-Onone`), iPad Pro 13" sim. Во время замеров на Mac шла сторонняя сборка Xcode,
поэтому разброс большой.

| Экран примера | fps |
|---|---|
| Posture Debug (split view + label) | 23–53 |
| Feed (split view + compositional grid 120 ячеек + search) | 11–48 |
| Article (split view + ~35 многострочных UILabel в stack view) | 10–21 |

**Критерий «60 fps для простого контента» не подтверждён.** Основная стоимость — перевёрстка контента в каждом кадре
(UISplitViewController + Auto Layout на каждый новый размер), это и есть живой ресайз. Сделано: трейт `DuoHingeTrait` во время
`.continuous` меняется только при смене posture/hingeRect, а не каждый кадр (перерасчёт трейтов по всей иерархии).
Однозначного выигрыша на шумных замерах не видно. Дальше: замер в Release на разгруженной машине и с пустым
`UIViewController` в качестве контента, профилирование в Instruments (Time Profiler).
Режим `continuous(steps:)` для поиска багов вёрстки от fps не зависит.

## Открытые вопросы

- Реальные размеры в pt, scale, safe areas Duo (сейчас расчёт @3x от 2034×1398 и 2670×1878 px).
- Угол переключения экранов (40°) и пороги posture (10° / 160°).
- Какие size class Apple назначит состояниям (особенно split и inner portrait).
- Положение шарнира: предполагается книжный сгиб (вертикальная линия во внутреннем ландшафте).
- Появится ли у Apple API позы/шарнира — тогда источник данных для `DuoPostureTrait` / `DuoHingeTrait` заменяется,
  код приложений не меняется.
