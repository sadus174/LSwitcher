/// Metadata-only availability. Unknown never promises a supported text field.
public enum FieldAvailability: Equatable, Sendable {
    case unknown, editable, unsupported, protected
}

public enum OperationStatus: Equatable, Sendable {
    case disabled, suspended, permissionsRequired, secureInput, handlerUnavailable
    case protectedTarget, excludedApplication(String), fieldUnknown, fieldUnsupported
    case manualOnly, automatic

    public static func resolve(enabled: Bool, suspended: Bool, permissions: Bool, secureInput: Bool,
                               running: Bool, protectedApplication: Bool = false, excluded: Bool = false,
                               applicationName: String = "приложение", field: FieldAvailability = .unknown,
                               automatic: Bool) -> Self {
        if !enabled { return .disabled }
        if suspended { return .suspended }
        if !permissions { return .permissionsRequired }
        if secureInput { return .secureInput }
        if !running { return .handlerUnavailable }
        if protectedApplication || field == .protected { return .protectedTarget }
        if excluded { return .excludedApplication(applicationName) }
        if field == .unknown { return .fieldUnknown }
        if field == .unsupported { return .fieldUnsupported }
        return automatic ? .automatic : .manualOnly
    }

    public var message: String {
        switch self {
        case .disabled: "LSwitcher выключен"
        case .suspended: "Обработка приостановлена до возвращения в сеанс"
        case .permissionsRequired: "Нужны разрешения macOS"
        case .secureInput: "Защищённый ввод macOS — исправления недоступны"
        case .handlerUnavailable: "Обработчик ввода недоступен — выполняется восстановление"
        case .protectedTarget: "Защищённое приложение или поле — исправления недоступны"
        case .excludedApplication(let name): "Автоисправление отключено в «\(name)»"
        case .fieldUnknown: "Доступность текущего поля не определена"
        case .fieldUnsupported: "Текущее поле не поддерживает исправление"
        case .manualOnly: "Автоисправление выключено · ручное исправление по Shift × 2"
        case .automatic: "Автоисправление включено · ручное исправление по Shift × 2"
        }
    }
}

public enum InputProtection {
    public static func protectsApplication(_ identifier: String) -> Bool {
        identifier.hasPrefix("com.1password.") || identifier == "com.agilebits.onepassword7"
    }
}
