import SwiftUI

/// Плеер: что показывать в раскрытой панели.
struct PlayerSettingsSection: View {
    @ObservedObject var controller: SettingsController

    var body: some View {
        Section("Плеер") {
            Toggle("Показывать обложку", isOn: controller.binding(\.showsArtwork))
            Toggle("Показывать полосу позиции", isOn: controller.binding(\.showsPositionBar))
        }
    }
}

/// Поведение: хоткей, реакция на наведение, автозапуск при входе.
struct BehaviorSettingsSection: View {
    @ObservedObject var controller: SettingsController
    let actions: SettingsActions
    /// Автозапуск живёт не в файле настроек, а в системной службе — она и есть
    /// источник истины. Здесь только снятое с неё значение, которое надо
    /// обновлять после каждого переключения.
    @State private var launchesAtLogin = false

    var body: some View {
        Section("Поведение") {
            Picker("Раскрывать панель", selection: hotkeySelection) {
                ForEach(HotkeyChoice.all) { choice in
                    Text(choice.displayName).tag(choice.id)
                }
            }
            // Отказ регистрации — рядом с выбором, а не в системном журнале:
            // человек, у которого сочетание занято Alfred или Raycast, иначе
            // просто жмёт и не понимает, почему тихо.
            if let failure = actions.hotkeyFailure() {
                Label(failure.message, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
            Toggle("Открывать по наведению", isOn: controller.binding(\.opensOnHover))
            Text("Выключено — панель открывается только по клику по челке или " +
                 "комбинацией клавиш.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Toggle("Запускать при входе", isOn: launchToggle)
        }
        .onAppear { launchesAtLogin = actions.isLaunchAtLoginEnabled() }
    }

    /// Выбор идёт по строковому признаку комбинации, а не по самой комбинации:
    /// `Picker` требует от значения `Hashable`, а хранимые поля — два числа.
    private var hotkeySelection: Binding<String> {
        Binding(get: { controller.settings.hotkeyChoice.id },
                set: { id in
                    guard let choice = HotkeyChoice.all.first(where: { $0.id == id }) else { return }
                    controller.update { $0.choosing(choice) }
                })
    }

    /// Переключатель дёргает системную службу и перечитывает её состояние:
    /// регистрация может не пройти (например, приложение запущено из дерева
    /// сборки), и врать про включённый автозапуск нельзя.
    private var launchToggle: Binding<Bool> {
        Binding(get: { launchesAtLogin },
                set: { _ in
                    actions.toggleLaunchAtLogin()
                    launchesAtLogin = actions.isLaunchAtLoginEnabled()
                })
    }
}
