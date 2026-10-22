import SwiftUI
import LSwitcherCore

private let brand = Color(red: 0.40, green: 0.33, blue: 0.85)

enum SettingsPage: String, CaseIterable {
    case general = "Переключение", exclusions = "Исключения", access = "Доступ и диагностика", about = "О программе"
    var icon: String {
        switch self {
        case .general: return "arrow.left.arrow.right"
        case .exclusions: return "app.badge.checkmark"
        case .access: return "checkmark.shield"
        case .about: return "info.circle"
        }
    }
}

struct SettingsView: View {
    @ObservedObject var model: AppModel
    @StateObject private var updates = Updates()
    private var page: SettingsPage { model.page }
    @Environment(\.colorScheme) private var scheme
    private var canvas: Color { scheme == .dark ? Color(red: 0.08, green: 0.09, blue: 0.13) : Color(red: 0.965, green: 0.969, blue: 0.985) }
    private var surface: Color { scheme == .dark ? Color(red: 0.13, green: 0.14, blue: 0.19) : .white }

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    header
                    switch page {
                    case .general: general
                    case .exclusions: exclusions
                    case .access: access
                    case .about: about
                    }
                }
                .padding(.horizontal, 32).padding(.top, 46).padding(.bottom, 28)
                .frame(maxWidth: 840, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
            .background(canvas)
        }
        .font(.system(size: 13))
        .tint(brand)
        .frame(minWidth: 880, minHeight: 630)
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                appIcon.frame(width: 42, height: 42)
                VStack(alignment: .leading, spacing: 3) {
                    Text("LSwitcher").font(.system(size: 19, weight: .bold, design: .rounded))
                    Text("В ритме ваших мыслей").font(.system(size: 10)).foregroundStyle(.secondary)
                }
            }.padding(.bottom, 34)
            Text("НАСТРОЙКИ").font(.system(size: 9, weight: .semibold)).tracking(1.6)
                .foregroundStyle(.secondary).padding(.leading, 12).padding(.bottom, 10)
            ForEach(SettingsPage.allCases, id: \.self) { item in
                Button { model.page = item } label: {
                    HStack(spacing: 10) {
                        Image(systemName: item.icon).font(.system(size: 14, weight: .medium)).frame(width: 18)
                        Text(item.rawValue).font(.system(size: 12, weight: page == item ? .semibold : .medium))
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 12).padding(.vertical, 12)
                    .foregroundStyle(page == item ? brand : .primary)
                    .background(page == item ? brand.opacity(0.11) : .clear, in: RoundedRectangle(cornerRadius: 11))
                    .contentShape(Rectangle())
                }.buttonStyle(.plain).padding(.bottom, 4)
            }
            Spacer()
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 7) {
                    Circle().fill(model.ready ? Color.green : Color.orange).frame(width: 6, height: 6)
                    Text(model.secureInput ? "Защищённый ввод" : model.sessionSuspended ? "Сессия приостановлена" : model.ready ? (model.enabled ? "Готов к работе" : "На паузе") : "Нужен доступ")
                        .font(.system(size: 12, weight: .medium))
                }
                Text("Русский ⇄ English").font(.system(size: 11)).foregroundStyle(.secondary)
                Text("Версия \(Updates.version) · Сделано для Mac").font(.system(size: 10)).foregroundStyle(.tertiary)
            }.padding(13)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(brand.opacity(0.045), in: RoundedRectangle(cornerRadius: 12))
        }
        .padding(.horizontal, 16).padding(.top, 54).padding(.bottom, 22)
        .frame(width: 222)
        .background(scheme == .dark ? Color(red: 0.105, green: 0.11, blue: 0.155) : Color(red: 0.945, green: 0.941, blue: 0.973))
        .overlay(alignment: .trailing) { Rectangle().fill(brand.opacity(0.08)).frame(width: 1) }
    }

    @ViewBuilder private var appIcon: some View {
        if let path = Bundle.main.path(forResource: "AppIcon", ofType: "icns"), let image = NSImage(contentsOfFile: path) {
            Image(nsImage: image).resizable().scaledToFit()
        } else {
            Image(systemName: "arrow.left.arrow.right").font(.system(size: 22, weight: .bold))
                .foregroundStyle(.white).frame(width: 42, height: 42).background(brand, in: RoundedRectangle(cornerRadius: 12))
        }
    }
    private var header: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(page.rawValue).font(.system(size: 27, weight: .bold, design: .rounded))
            Text(page == .general ? "Пишите свободно. Раскладку поправит LSwitcher." :
                 page == .exclusions ? "Вы решаете, где нужна автоматическая помощь." :
                 page == .about ? "LSwitcher · Русский ⇄ English" : "Всё необходимое для стабильной работы.")
                .font(.system(size: 12)).foregroundStyle(.secondary)
        }
    }
    private func card<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 16, content: content)
            .padding(22).frame(maxWidth: .infinity, alignment: .leading)
            .background(surface, in: RoundedRectangle(cornerRadius: 18))
            .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(.primary.opacity(0.045)))
            .shadow(color: .black.opacity(scheme == .dark ? 0 : 0.018), radius: 10, y: 4)
    }
    private var general: some View {
        VStack(spacing: 18) {
            HStack(alignment: .center, spacing: 20) {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Нужные буквы.\nС первого раза.")
                        .font(.system(size: 25, weight: .semibold, design: .rounded)).lineSpacing(2)
                    Text("ghbdtn").foregroundColor(.white.opacity(0.65))
                    + Text("  →  ").foregroundColor(.white.opacity(0.45))
                    + Text("привет").bold().foregroundColor(.white)
                }
                Spacer(minLength: 6)
                HStack(spacing: -8) {
                    heroKey("A", angle: -9, opacity: 0.19).offset(y: -12)
                    heroKey("Я", angle: 9, opacity: 0.3).offset(y: 14)
                }.padding(.trailing, 10)
            }
            .foregroundStyle(.white).padding(26).frame(maxWidth: .infinity, alignment: .leading)
            .background(LinearGradient(colors: [brand, Color(red: 0.32, green: 0.29, blue: 0.66)], startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 20))
            card {
                HStack {
                    rowTitle("LSwitcher включён", subtitle: "Ручное исправление и помощь с раскладкой", symbol: "power")
                    Spacer()
                    Toggle("LSwitcher включён", isOn: Binding(get: { model.enabled }, set: model.setEnabled)).labelsHidden().toggleStyle(.switch)
                }
                Divider()
                HStack {
                    rowTitle("Исправлять автоматически", subtitle: "После пробела, Enter или Tab", symbol: "wand.and.stars")
                    Spacer()
                    Toggle("Исправлять автоматически", isOn: Binding(get: { model.automatic }, set: model.setAutomatic)).labelsHidden().toggleStyle(.switch).disabled(!model.enabled)
                }
                Text(LayoutConverter.lexiconEntryCount > 0
                     ? "Расширенный словарь RU/EN. Корректные и неоднозначные слова остаются без изменений."
                     : "Словарь недоступен. Автоисправление отключено; ручное переключение работает.")
                    .font(.system(size: 11)).foregroundStyle(.secondary).padding(.leading, 38)
            }
            card {
                HStack(alignment: .top) {
                    rowTitle("Исправить вручную", subtitle: "Слово перед курсором или выделенный текст", symbol: "keyboard")
                    Spacer(minLength: 4)
                    Text("⇧ × 2").font(.system(size: 12, weight: .semibold, design: .monospaced))
                        .padding(.horizontal, 12).padding(.vertical, 9).background(brand.opacity(0.09), in: RoundedRectangle(cornerRadius: 8))
                }
                Picker("Клавиша исправления", selection: Binding(get: { model.shiftMode }, set: model.setShiftMode)) {
                    Text("Любой Shift").tag("both")
                    Text("Только правый").tag("right")
                    Text("Только левый").tag("left")
                }.pickerStyle(.segmented)
                Text("Backspace сразу после автозамены отменяет её (в течение 5 секунд, если поле позволяет проверить положение курсора). Два коротких нажатия одной и той же клавиши Shift. Работает и после пробела. Набор заглавных букв не запускает исправление.")
                    .font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            card {
                rowTitle("Значок в строке меню", subtitle: "Стрелки, код текущей раскладки или флаг. Обновляется при переключении языка.", symbol: "menubar.rectangle")
                Picker("Значок в строке меню", selection: Binding(get: { model.statusIconStyle }, set: model.setStatusIconStyle)) {
                    Text("По умолчанию · ⇄").tag(StatusIconStyle.arrows)
                    Text("Код · RU / EN").tag(StatusIconStyle.code)
                    Text("Флаг · 🇷🇺 / 🇺🇸").tag(StatusIconStyle.flag)
                }.pickerStyle(.segmented)
            }
            card {
                HStack {
                    rowTitle("Флаг раскладки у поля", subtitle: "Маленькая подсказка при получении фокуса. Исчезает с началом ввода и не перехватывает нажатия.", symbol: "flag")
                    Spacer()
                    Toggle("Флаг раскладки у поля", isOn: Binding(get: { model.showLayoutHint }, set: model.setShowLayoutHint))
                        .labelsHidden().toggleStyle(.switch)
                }
                Text("Защищённые и недоступные через Accessibility поля пропускаются.")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            }
            if !model.ready {
                Button { model.page = .access } label: {
                    HStack { Image(systemName: "exclamationmark.shield"); Text("Проверьте разрешения macOS"); Spacer(); Image(systemName: "arrow.right") }
                        .padding(15).foregroundStyle(Color.orange).background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
                }.buttonStyle(.plain)
            }
        }
    }
    private func heroKey(_ text: String, angle: Double, opacity: Double) -> some View {
        Text(text).font(.system(size: 38, weight: .medium, design: .rounded))
            .frame(width: 82, height: 88)
            .background(.white.opacity(opacity), in: RoundedRectangle(cornerRadius: 19))
            .overlay(RoundedRectangle(cornerRadius: 19).strokeBorder(.white.opacity(0.3)))
            .rotationEffect(.degrees(angle))
    }
    private func rowTitle(_ title: String, subtitle: String, symbol: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol).font(.system(size: 16)).foregroundStyle(brand).frame(width: 25, height: 24)
            VStack(alignment: .leading, spacing: 5) {
                Text(title).font(.system(size: 13, weight: .semibold))
                Text(subtitle).font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
    }
    private var exclusions: some View {
        VStack(alignment: .leading, spacing: 18) {
            card {
                HStack {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Без автоисправления").font(.system(size: 15, weight: .semibold))
                        Text("Двойной Shift продолжает работать.").font(.system(size: 12)).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button(action: model.addExclusion) { Label("Добавить", systemImage: "plus") }.buttonStyle(.borderedProminent)
                }
                if model.excludedIDs.isEmpty {
                    Text("Пока нет исключений. Добавьте приложение, в котором предпочитаете исправлять текст вручную.")
                        .foregroundStyle(.secondary).padding(.vertical, 30)
                }
                ForEach(model.excludedIDs, id: \.self) { id in
                    Divider()
                    HStack(spacing: 12) {
                        Image(nsImage: model.appInfo(id).1).resizable().scaledToFit().frame(width: 32, height: 32)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(model.appInfo(id).0).fontWeight(.medium)
                            Text(id).font(.system(size: 10, design: .monospaced)).foregroundStyle(.secondary).textSelection(.enabled)
                        }
                        Spacer()
                        Button { model.removeExclusion(id) } label: { Image(systemName: "minus.circle").font(.system(size: 17)).foregroundStyle(.secondary) }
                            .buttonStyle(.plain).help("Убрать из исключений").accessibilityLabel("Убрать \(model.appInfo(id).0) из исключений")
                    }.padding(.vertical, 3)
                }
            }
            card {
                rowTitle("Никогда не исправлять", subtitle: "Одно слово в строке, до 5 000 слов. Только явно добавленные вами записи; регистр не учитывается. Двойной Shift продолжает работать.", symbol: "text.badge.checkmark")
                TextEditor(text: Binding(get: { model.neverCorrect }, set: model.setNeverCorrect))
                    .font(.system(size: 12, design: .monospaced)).frame(height: 110)
                    .accessibilityLabel("Слова без автоисправления")
            }
            Label("Изменения сохраняются сразу", systemImage: "checkmark.circle").font(.system(size: 11)).foregroundStyle(.secondary)
            card {
                rowTitle("Пароли остаются паролями", subtitle: "Защищённые поля и режим Secure Input пропускаются. В 1Password переключение полностью отключено.", symbol: "lock")
            }
        }
    }
    private var access: some View {
        VStack(alignment: .leading, spacing: 18) {
            card {
                permissionRow("Универсальный доступ", detail: "Чтение выделения и замена текста", allowed: model.accessibility) { model.openAccess() }
                Divider()
                permissionRow("Мониторинг ввода", detail: "Распознавание двойного Shift и набора слов", allowed: model.listening) { model.openAccess(true) }
                Divider()
                permissionRow("Отправка исправлений", detail: "Право отправлять события клавиатуры", allowed: model.posting) { model.openAccess() }
                HStack {
                    Label(model.running ? "Клавиатурный обработчик активен" : "Клавиатурный обработчик не запущен", systemImage: model.running ? "checkmark.circle.fill" : "exclamationmark.circle")
                        .font(.system(size: 11)).foregroundStyle(model.running ? Color.green : Color.orange)
                    Spacer()
                    Button("Проверить снова", action: model.retry).buttonStyle(.bordered)
                }
            }
            Text("После изменения доступа нажмите «Проверить снова». Если macOS запросит перезапуск, завершите LSwitcher через значок в строке меню и откройте заново.")
                .font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            card {
                Text("Диагностика ввода").font(.system(size: 15, weight: .semibold))
                HStack(spacing: 12) {
                    metric("События", value: model.events)
                    metric("События Shift", value: model.shiftEvents)
                    metric("Вручную", value: model.manualCount)
                    metric("Автоматически", value: model.autoCount)
                }
                Text(model.diagnostic).font(.system(size: 11)).foregroundStyle(.secondary)
                Text("Последняя цель: \(model.inputTarget)").font(.system(size: 10)).foregroundStyle(.tertiary)
                Text("Только счётчики за текущий запуск. Набранный текст не записывается и никуда не отправляется.")
                    .font(.system(size: 10)).foregroundStyle(.tertiary).fixedSize(horizontal: false, vertical: true)
                Divider()
                Picker("Тестовый редактор", selection: $model.testEditorID) {
                    Text("TextEdit").tag("com.apple.TextEdit")
                    Text("Safari").tag("com.apple.Safari")
                    Text("Chrome").tag("com.google.Chrome")
                    Text("Spotlight · пустой поиск").tag("com.apple.Spotlight")
                }.disabled(model.testing)
                HStack {
                    Button(model.testing ? "Идёт проверка…" : "Проверить ввод", action: model.runSmokeTest)
                        .buttonStyle(.bordered).disabled(model.testing || !model.ready)
                    Text("Откроется отдельный временный документ или локальная тестовая страница.").font(.system(size: 10)).foregroundStyle(.secondary)
                }
                if !model.testResults.isEmpty {
                    Text(model.testResults).font(.system(size: 11, design: .monospaced))
                        .fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
                }
            }
            Text("Поколение обработчика: \(model.handlerGeneration). После сна обработчик создаётся заново; состояние автоматически проверяется раз в секунду.")
                .font(.system(size: 11)).foregroundStyle(.secondary)
            if model.secureInput {
                Label("macOS включила Secure Input. Переключение временно недоступно; после выхода из защищённого ввода работа возобновится.", systemImage: "lock.shield")
                    .font(.system(size: 11)).foregroundStyle(.orange)
            }
            Label("Все настройки и обработка — на вашем Mac", systemImage: "internaldrive").font(.system(size: 11)).foregroundStyle(.secondary)
        }
    }
    private var about: some View {
        VStack(alignment: .leading, spacing: 18) {
            card {
                HStack(spacing: 18) {
                    appIcon.frame(width: 72, height: 72)
                    VStack(alignment: .leading, spacing: 7) {
                        Text("LSwitcher").font(.system(size: 24, weight: .bold, design: .rounded))
                        Text("Версия \(Updates.version)").foregroundStyle(.secondary)
                        Text("В ритме ваших мыслей").font(.system(size: 12))
                    }
                }
                Text("Лёгкий помощник для исправления раскладки. Обработка текста происходит на вашем Mac; история набора не сохраняется.")
                    .foregroundStyle(.secondary)
                Link("Репозиторий на GitHub ↗", destination: Updates.repository)
                Link("Сообщить об ошибке ↗", destination: Updates.repository.appendingPathComponent("issues"))
            }
            card {
                rowTitle("Обновления", subtitle: updates.message, symbol: "arrow.down.circle")
                HStack {
                    Button(updates.checking ? "Проверяем…" : "Проверить обновления", action: updates.check)
                        .buttonStyle(.borderedProminent).disabled(updates.checking || updates.downloading || updates.readyToInstall)
                    Link(updates.available ? "Скачать новую версию ↗" : "Все релизы ↗", destination: Updates.releases)
                }
                if updates.canDownload && !updates.readyToInstall {
                    Button(updates.downloading ? "Скачиваем…" : "Скачать обновление", action: updates.download)
                        .buttonStyle(.bordered).disabled(updates.downloading)
                }
                if updates.readyToInstall {
                    Button("Установить и перезапустить", action: updates.install).buttonStyle(.borderedProminent)
                }
                Text("Проверка выполняется только по нажатию кнопки: приложение обращается к GitHub без передачи набранного текста. Пакет проверяется по закреплённому ключу Ed25519 и SHA256, затем устанавливается с вашим подтверждением. DMG остаётся доступен для ручной установки. После обновления локальной сборки может потребоваться повторная выдача разрешений macOS.")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            }
        }
    }
    private func permissionRow(_ title: String, detail: String, allowed: Bool, action: @escaping () -> Void) -> some View {
        HStack(spacing: 12) {
            Image(systemName: allowed ? "checkmark.circle.fill" : "circle.dashed").font(.system(size: 19)).foregroundStyle(allowed ? Color.green : .orange)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).fontWeight(.semibold)
                Text(detail).font(.system(size: 11)).foregroundStyle(.secondary)
            }
            Spacer()
            if allowed { Text("Разрешено").font(.system(size: 11, weight: .medium)).foregroundStyle(.green) }
            else { Button("Разрешить", action: action).buttonStyle(.bordered) }
        }
    }
    private func metric(_ title: String, value: Int) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(value.formatted()).font(.system(size: 23, weight: .semibold, design: .rounded)).monospacedDigit()
            Text(title).font(.system(size: 9)).foregroundStyle(.secondary)
        }.frame(maxWidth: .infinity, alignment: .leading).padding(12).background(brand.opacity(0.055), in: RoundedRectangle(cornerRadius: 10))
    }
}
