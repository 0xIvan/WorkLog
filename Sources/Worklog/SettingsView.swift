import AppKit
import SwiftUI
import WorklogCore

struct SettingsView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        DashboardView()
        .onAppear {
            appState.selectedSection = .rules
        }
    }
}

struct RulesSettingsView: View {
    @EnvironmentObject private var appState: AppState
    @State private var editingRule: Rule?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Rules")
                    .font(.title2.weight(.semibold))
                Spacer()
                Button {
                    editingRule = Rule(
                        name: "New Rule",
                        priority: 150,
                        enabled: true,
                        isBuiltIn: false,
                        action: RuleAction(kind: .work, categoryID: categoryID(for: .work), projectID: nil),
                        conditions: [
                            RuleCondition(field: .windowTitle, operation: .contains, value: "")
                        ]
                    )
                } label: {
                    Label("Add Rule", systemImage: "plus")
                }
            }

            List {
                ForEach(appState.rules) { rule in
                    HStack {
                        Button {
                            var updatedRule = rule
                            updatedRule.enabled.toggle()
                            appState.saveRule(updatedRule, reclassify: .today)
                        } label: {
                            Image(systemName: rule.enabled ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(rule.enabled ? .green : .secondary)
                        }
                        .buttonStyle(.plain)

                        VStack(alignment: .leading, spacing: 4) {
                            Text(rule.name)
                                .font(.headline)
                            Text(ruleSummary(rule))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }

                        Spacer()

                        Text(rule.action.kind.displayName)
                            .font(.caption)
                            .foregroundStyle(color(for: rule.action.kind))

                        Button {
                            editingRule = rule
                        } label: {
                            Label("Edit", systemImage: "pencil")
                        }
                        .labelStyle(.iconOnly)
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .sheet(item: $editingRule) { rule in
            RuleEditorView(
                rule: rule,
                projects: appState.projects,
                categories: appState.categories,
                onDelete: { deletedRule, scope in
                    appState.deleteRule(id: deletedRule.id, reclassify: scope)
                },
                onSave: { savedRule, scope in
                    appState.saveRule(savedRule, reclassify: scope)
                }
            )
        }
    }

    private func categoryID(for kind: ActivityKind) -> UUID? {
        appState.categories.first { $0.kind == kind }?.id
    }

    private func ruleSummary(_ rule: Rule) -> String {
        rule.conditions
            .map { "\($0.field.displayName) \($0.operation.displayName) \($0.value)" }
            .joined(separator: " and ")
    }

    private func color(for kind: ActivityKind) -> Color {
        switch kind {
        case .work:
            .blue
        case .personal:
            .green
        case .review:
            .orange
        case .ignored:
            .secondary
        }
    }
}

private struct RuleEditorView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var name: String
    @State private var priority: Int
    @State private var enabled: Bool
    @State private var kind: ActivityKind
    @State private var projectIDValue: String
    @State private var field: RuleField
    @State private var operation: RuleOperation
    @State private var value: String
    @State private var reclassificationScope: ReclassificationScope?

    var rule: Rule
    var projects: [Project]
    var categories: [WorklogCore.Category]
    var onDelete: (Rule, ReclassificationScope?) -> Void
    var onSave: (Rule, ReclassificationScope?) -> Void

    init(
        rule: Rule,
        projects: [Project],
        categories: [WorklogCore.Category],
        onDelete: @escaping (Rule, ReclassificationScope?) -> Void,
        onSave: @escaping (Rule, ReclassificationScope?) -> Void
    ) {
        self.rule = rule
        self.projects = projects
        self.categories = categories
        self.onDelete = onDelete
        self.onSave = onSave

        let condition = rule.conditions.first
            ?? RuleCondition(field: .windowTitle, operation: .contains, value: "")

        _name = State(initialValue: rule.name)
        _priority = State(initialValue: rule.priority)
        _enabled = State(initialValue: rule.enabled)
        _kind = State(initialValue: rule.action.kind)
        _projectIDValue = State(initialValue: rule.action.projectID?.uuidString ?? "")
        _field = State(initialValue: condition.field)
        _operation = State(initialValue: condition.operation)
        _value = State(initialValue: condition.value)
        _reclassificationScope = State(initialValue: .today)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(name.isEmpty ? "Rule" : name)
                .font(.title2.weight(.semibold))

            Form {
                TextField("Name", text: $name)

                Toggle("Enabled", isOn: $enabled)

                Stepper(value: $priority, in: 1...2_000) {
                    Text("Priority \(priority)")
                }

                Picker("Result", selection: $kind) {
                    ForEach(ActivityKind.allCases) { kind in
                        Text(kind.displayName).tag(kind)
                    }
                }

                Picker("Project", selection: $projectIDValue) {
                    Text("None").tag("")
                    ForEach(projects.filter { !$0.isArchived }) { project in
                        Text(project.name).tag(project.id.uuidString)
                    }
                }

                Picker("Field", selection: $field) {
                    ForEach(RuleField.allCases) { field in
                        Text(field.displayName).tag(field)
                    }
                }

                Picker("Operation", selection: $operation) {
                    ForEach(RuleOperation.allCases) { operation in
                        Text(operation.displayName).tag(operation)
                    }
                }

                TextField("Value", text: $value)

                Picker("Reclassify", selection: $reclassificationScope) {
                    Text("Future Only").tag(ReclassificationScope?.none)
                    ForEach(ReclassificationScope.allCases) { scope in
                        Text(scope.displayName).tag(ReclassificationScope?.some(scope))
                    }
                }
            }

            HStack {
                Button(role: .destructive) {
                    onDelete(rule, reclassificationScope)
                    dismiss()
                } label: {
                    Label("Delete", systemImage: "trash")
                }

                Spacer()

                Button("Cancel") {
                    dismiss()
                }

                Button {
                    onSave(updatedRule(), reclassificationScope)
                    dismiss()
                } label: {
                    Label("Save", systemImage: "checkmark")
                }
                .keyboardShortcut(.defaultAction)
                .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding()
        .frame(width: 520)
    }

    private func updatedRule() -> Rule {
        var updatedRule = rule
        updatedRule.name = name
        updatedRule.priority = priority
        updatedRule.enabled = enabled
        updatedRule.isBuiltIn = false
        updatedRule.action = RuleAction(
            kind: kind,
            categoryID: categories.first { $0.kind == kind }?.id,
            projectID: UUID(uuidString: projectIDValue)
        )
        updatedRule.conditions = [
            RuleCondition(
                id: rule.conditions.first?.id ?? UUID(),
                field: field,
                operation: operation,
                value: value
            )
        ]

        return updatedRule
    }
}

struct ProjectsSettingsView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Projects")
                    .font(.title2.weight(.semibold))
                Spacer()
                Button {
                    appState.saveProject(Project(name: "New Project", colorHex: "#2563EB", isArchived: false))
                } label: {
                    Label("Add Project", systemImage: "plus")
                }
            }

            List(appState.projects) { project in
                ProjectEditorRow(project: project)
                    .environmentObject(appState)
            }
        }
    }
}

private struct ProjectEditorRow: View {
    @EnvironmentObject private var appState: AppState
    @State private var project: Project
    @State private var autosaveTask: Task<Void, Never>?

    init(project: Project) {
        _project = State(initialValue: project)
    }

    var body: some View {
        HStack {
            TextField("Name", text: $project.name)
            ColorInputView(colorHex: $project.colorHex)
            Toggle("Archived", isOn: $project.isArchived)
                .frame(width: 120)
        }
        .padding(.vertical, 4)
        .onChange(of: project) { _, updatedProject in
            scheduleAutosave(updatedProject)
        }
        .onDisappear {
            autosaveTask?.cancel()
            appState.saveProject(project)
        }
    }

    private func scheduleAutosave(_ updatedProject: Project) {
        autosaveTask?.cancel()
        autosaveTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else {
                return
            }

            appState.saveProject(updatedProject)
        }
    }
}

struct CategoriesSettingsView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Categories")
                    .font(.title2.weight(.semibold))
                Spacer()
                Button {
                    appState.saveCategory(WorklogCore.Category(name: "New Category", kind: .work, colorHex: "#2563EB"))
                } label: {
                    Label("Add Category", systemImage: "plus")
                }
            }

            List(appState.categories) { category in
                CategoryEditorRow(category: category)
                    .environmentObject(appState)
            }
        }
    }
}

private struct CategoryEditorRow: View {
    @EnvironmentObject private var appState: AppState
    @State private var category: WorklogCore.Category
    @State private var autosaveTask: Task<Void, Never>?

    init(category: WorklogCore.Category) {
        _category = State(initialValue: category)
    }

    var body: some View {
        HStack {
            TextField("Name", text: $category.name)
            Picker("Kind", selection: $category.kind) {
                ForEach(ActivityKind.allCases.filter { $0 != .ignored }) { kind in
                    Text(kind.displayName).tag(kind)
                }
            }
            .frame(width: 180)
            ColorInputView(colorHex: $category.colorHex)
        }
        .padding(.vertical, 4)
        .onChange(of: category) { _, updatedCategory in
            scheduleAutosave(updatedCategory)
        }
        .onDisappear {
            autosaveTask?.cancel()
            appState.saveCategory(category)
        }
    }

    private func scheduleAutosave(_ updatedCategory: WorklogCore.Category) {
        autosaveTask?.cancel()
        autosaveTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else {
                return
            }

            appState.saveCategory(updatedCategory)
        }
    }
}

private struct ColorInputView: View {
    @Binding var colorHex: String

    private var color: Color {
        Color(hex: colorHex) ?? .accentColor
    }

    var body: some View {
        HStack(spacing: 12) {
            ColorPicker(
                "Color",
                selection: Binding(
                    get: { color },
                    set: { newColor in
                        if let hex = newColor.hexString {
                            colorHex = hex
                        }
                    }
                ),
                supportsOpacity: false
            )
            .labelsHidden()
            .fixedSize()

            TextField("Color", text: $colorHex)
                .font(.body.monospaced())
                .frame(width: 94)
        }
    }
}

private extension Color {
    init?(hex: String) {
        var trimmedHex = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedHex.hasPrefix("#") {
            trimmedHex.removeFirst()
        }

        guard trimmedHex.count == 6, let value = UInt64(trimmedHex, radix: 16) else {
            return nil
        }

        let red = Double((value >> 16) & 0xFF) / 255
        let green = Double((value >> 8) & 0xFF) / 255
        let blue = Double(value & 0xFF) / 255

        self.init(red: red, green: green, blue: blue)
    }

    var hexString: String? {
        guard let color = NSColor(self).usingColorSpace(.deviceRGB) else {
            return nil
        }

        let red = Int(round(color.redComponent * 255))
        let green = Int(round(color.greenComponent * 255))
        let blue = Int(round(color.blueComponent * 255))

        return String(format: "#%02X%02X%02X", red, green, blue)
    }
}

struct PrivacySettingsView: View {
    @EnvironmentObject private var appState: AppState
    @State private var editingRule: Rule?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Ignore Rules")
                    .font(.title2.weight(.semibold))
                Spacer()
                Button {
                    editingRule = Rule(
                        name: "New Ignore Rule",
                        priority: 20,
                        enabled: true,
                        isBuiltIn: false,
                        action: RuleAction(kind: .ignored, categoryID: nil, projectID: nil),
                        conditions: [
                            RuleCondition(field: .windowTitle, operation: .contains, value: "")
                        ]
                    )
                } label: {
                    Label("Add Ignore Rule", systemImage: "plus")
                }
            }

            List(appState.rules.filter { $0.action.kind == .ignored }) { rule in
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(rule.name)
                            .font(.headline)
                        Text(rule.conditions.map { "\($0.field.displayName) \($0.operation.displayName) \($0.value)" }.joined(separator: " and "))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button {
                        editingRule = rule
                    } label: {
                        Label("Edit", systemImage: "pencil")
                    }
                    .labelStyle(.iconOnly)
                }
                .padding(.vertical, 4)
            }
        }
        .sheet(item: $editingRule) { rule in
            RuleEditorView(
                rule: rule,
                projects: appState.projects,
                categories: appState.categories,
                onDelete: { deletedRule, scope in
                    appState.deleteRule(id: deletedRule.id, reclassify: scope)
                },
                onSave: { savedRule, scope in
                    var ignoreRule = savedRule
                    ignoreRule.action = RuleAction(kind: .ignored, categoryID: nil, projectID: nil)
                    appState.saveRule(ignoreRule, reclassify: scope)
                }
            )
        }
    }
}
