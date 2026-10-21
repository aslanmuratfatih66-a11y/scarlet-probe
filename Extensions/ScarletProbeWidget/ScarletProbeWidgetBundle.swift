import SwiftUI
import WidgetKit

/// Точка входа виджет-расширения: обычный WidgetKit-виджет (тест 16)
/// и виджетная часть Live Activity (тест 17).
@main
struct ScarletProbeWidgetBundle: WidgetBundle {
    var body: some Widget {
        ScarletProbeWidget()
        ScarletProbeLiveActivity()
    }
}
