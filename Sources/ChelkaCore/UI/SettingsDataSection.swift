import SwiftUI

/// Данные: где лежит история, сколько занимает и как её стереть.
///
/// Раздел обязателен: при первом запуске приложение подхватывает то, что уже
/// лежало в буфере, и человек должен уметь это стереть, не лазая в терминал.
/// Очистка спрашивает подтверждение — отменить её нечем.
struct DataSettingsSection: View {
    let actions: SettingsActions
    @State private var usage = 0
    @State private var asksConfirmation = false

    var body: some View {
        Section("Данные") {
            LabeledContent("Где лежит") {
                // Путь выделяемый: его иногда надо скопировать, а не только
                // прочитать.
                Text(AppPaths.support.path)
                    .textSelection(.enabled)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .truncationMode(.middle)
            }
            LabeledContent("Занято") {
                Text(StorageUsage.formatted(usage))
                    .foregroundStyle(.secondary)
            }
            HStack {
                Button("Показать в Finder", action: actions.revealDataFolder)
                Spacer()
                Button("Очистить историю…") { asksConfirmation = true }
            }
            Text("Очистка убирает и записи, и файлы картинок на диске, включая " +
                 "закреплённое. Вернуть их будет нечем.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .onAppear(perform: refreshUsage)
        .confirmationDialog("Очистить историю буфера?", isPresented: $asksConfirmation) {
            Button("Очистить", role: .destructive) {
                actions.clearHistory()
                refreshUsage()
            }
            Button("Отмена", role: .cancel) {}
        } message: {
            Text("Будут удалены все записи и все файлы картинок — \(StorageUsage.formatted(usage)).")
        }
    }

    private func refreshUsage() {
        usage = StorageUsage.bytes(of: [AppPaths.index, AppPaths.blobs])
    }
}
