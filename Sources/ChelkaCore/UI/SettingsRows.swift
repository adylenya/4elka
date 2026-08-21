import SwiftUI

/// Строки настроек, которые повторяются в разделах. Отдельным файлом, потому
/// что таких строк больше десятка: набирать их по месту — плодить расхождения
/// в ширине полей и подписях.
///
/// Тема системная: ни одного своего цвета, только семантические (`.secondary`
/// у пояснений) и системные элементы управления.

/// Целое число: поле ввода и стрелки. Границы приходят снаружи — те же, что и
/// в проверке значений, чтобы стрелками нельзя было выйти за допустимое.
struct NumberRow: View {
    let title: String
    var hint: String?
    let range: ClosedRange<Int>
    var step = 1
    @Binding var value: Int

    var body: some View {
        LabeledContent {
            HStack(spacing: Config.SettingsWindow.rowSpacing) {
                // Поле ввода принимает значение по Enter или по уходу фокуса,
                // а не на каждое нажатие: иначе проверка значений правила бы
                // недописанное число прямо под руками.
                TextField("", value: $value, format: .number)
                    .multilineTextAlignment(.trailing)
                    .frame(width: Config.SettingsWindow.numberFieldWidth)
                Stepper("", value: $value, in: range, step: step)
                    .labelsHidden()
            }
        } label: {
            RowLabel(title: title, hint: hint)
        }
    }
}

/// Время в секундах: то же поле со стрелками, но с дробным шагом и подписью
/// «с», чтобы не путалось с процентами и штуками.
struct SecondsRow: View {
    let title: String
    var hint: String?
    let range: ClosedRange<TimeInterval>
    @Binding var value: TimeInterval

    var body: some View {
        LabeledContent {
            HStack(spacing: Config.SettingsWindow.rowSpacing) {
                TextField("", value: $value, format: .number)
                    .multilineTextAlignment(.trailing)
                    .frame(width: Config.SettingsWindow.numberFieldWidth)
                Text("с")
                    .foregroundStyle(.secondary)
                Stepper("", value: $value, in: range,
                        step: Config.SettingsWindow.durationStep)
                    .labelsHidden()
            }
        } label: {
            RowLabel(title: title, hint: hint)
        }
    }
}

/// Координата: то же, но шире полем и с дробным шагом. Города выбираются
/// списком выше, а это — для места, которого в списке нет.
struct CoordinateRow: View {
    let title: String
    let range: ClosedRange<Double>
    @Binding var value: Double

    var body: some View {
        LabeledContent {
            HStack(spacing: Config.SettingsWindow.rowSpacing) {
                TextField("", value: $value, format: .number)
                    .multilineTextAlignment(.trailing)
                    .frame(width: Config.SettingsWindow.coordinateFieldWidth)
                Stepper("", value: $value, in: range,
                        step: Config.SettingsWindow.coordinateStep)
                    .labelsHidden()
            }
        } label: {
            RowLabel(title: title, hint: nil)
        }
    }
}

/// Подпись строки с пояснением под ней. Пояснение — там, где без него
/// непонятно, что именно случится.
struct RowLabel: View {
    let title: String
    let hint: String?

    var body: some View {
        VStack(alignment: .leading, spacing: Config.SettingsWindow.hintSpacing) {
            Text(title)
            if let hint {
                Text(hint)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
