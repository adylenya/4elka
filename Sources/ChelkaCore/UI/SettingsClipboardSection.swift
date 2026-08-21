import SwiftUI

/// Буфер обмена: сколько хранить, потолок размера картинки и список
/// приложений, из которых не записывать.
struct ClipboardSettingsSection: View {
    @ObservedObject var controller: SettingsController

    var body: some View {
        Section("Буфер обмена") {
            NumberRow(title: "Хранить текстов",
                      hint: "Закреплённое не вытесняется никогда",
                      range: Config.Limits.historyQuota,
                      step: Config.SettingsWindow.quotaStep,
                      value: controller.binding(\.textLimit))
            NumberRow(title: "Хранить картинок",
                      range: Config.Limits.historyQuota,
                      step: Config.SettingsWindow.quotaStep,
                      value: controller.binding(\.imageLimit))
            NumberRow(title: "Хранить файлов",
                      range: Config.Limits.historyQuota,
                      step: Config.SettingsWindow.quotaStep,
                      value: controller.binding(\.fileLimit))
            NumberRow(title: "Потолок картинки, МБ",
                      hint: "Что больше — в историю не попадает",
                      range: Config.Limits.imageMegabytes,
                      value: controller.binding(\.maxImageMegabytes))
            BlockedAppsEditor(controller: controller)
        }
    }
}

/// Список приложений, из которых не записывать. Идентификатор бандла, а не
/// имя: имя приложения меняется с языком системы, идентификатор — нет.
///
/// Пустым список быть не может: `sanitized()` вернёт в него опорный набор
/// менеджеров паролей. Соглашение nspasteboard соблюдают не все, и остаться
/// совсем без списка означало бы складывать пароли в историю на диск.
private struct BlockedAppsEditor: View {
    @ObservedObject var controller: SettingsController
    @State private var newBundleID = ""

    /// Список прокручиваемым стеком, а не `List`: вложенный в `Form` список
    /// заводит вторую полосу прокрутки внутри первой, и выделение в нём
    /// пришлось бы хранить состоянием. Кнопка «убрать» на самой строке
    /// обходится без выделения вовсе.
    var body: some View {
        VStack(alignment: .leading, spacing: Config.SettingsWindow.rowSpacing) {
            RowLabel(title: "Не записывать из приложений",
                     hint: "Идентификатор бандла, например com.1password.1password")
            ScrollView {
                VStack(alignment: .leading, spacing: Config.SettingsWindow.listRowSpacing) {
                    ForEach(controller.settings.blockedBundleIDs, id: \.self) { id in
                        HStack {
                            Text(id)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Spacer()
                            Button {
                                remove(id)
                            } label: {
                                Image(systemName: "minus.circle")
                            }
                            .buttonStyle(.borderless)
                            .help("Убрать из списка")
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(height: Config.SettingsWindow.listHeight)
            HStack(spacing: Config.SettingsWindow.rowSpacing) {
                TextField("com.example.app", text: $newBundleID)
                    .onSubmit(add)
                Button("Добавить", action: add)
                    .disabled(trimmedNew.isEmpty)
            }
        }
    }

    private var trimmedNew: String {
        newBundleID.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func add() {
        let id = trimmedNew
        guard !id.isEmpty else { return }
        controller.update { current in
            guard !current.blockedBundleIDs.contains(id) else { return current }
            var next = current
            next.blockedBundleIDs = current.blockedBundleIDs + [id]
            return next
        }
        newBundleID = ""
    }

    /// Убрать последнюю строку не получится: проверка значений вернёт в
    /// опустевший список опорный набор менеджеров паролей. Это осознанно —
    /// история на диске без такой защиты собирала бы пароли.
    private func remove(_ id: String) {
        controller.update { current in
            var next = current
            next.blockedBundleIDs = current.blockedBundleIDs.filter { $0 != id }
            return next
        }
    }
}
