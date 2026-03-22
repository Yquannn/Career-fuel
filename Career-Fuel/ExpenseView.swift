import SwiftUI

struct ExpenseView: View {
    @EnvironmentObject private var expenseStore: ExpenseStore
    @EnvironmentObject private var aiService: AIInsightService

    @State private var selectedFilter: ExpenseTimeFilter = .weekly
    @State private var showingEditor = false
    @State private var editingExpense: Expense?
    @State private var pendingDeleteExpense: Expense?

    var body: some View {
        let filteredContent = ExpenseFilterContent(
            expenses: expenseStore.expenses,
            filter: selectedFilter
        )
        let recurringPlansByID = Dictionary(uniqueKeysWithValues: expenseStore.recurringPlans.map { ($0.id, $0) })

        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(
                    title: "Expense tracker",
                    subtitle: "Log each expense as an individual transaction, review on-device AI category suggestions, and inspect daily, weekly, or monthly activity without changing your runway math."
                )

                HStack {
                    Button {
                        editingExpense = nil
                        showingEditor = true
                    } label: {
                        Label("Add Expense", systemImage: "plus")
                            .font(.headline.weight(.semibold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.horizontal, 18)
                            .padding(.vertical, 12)
                            .background(
                                RoundedRectangle(cornerRadius: 18, style: .continuous)
                                    .fill(AppPalette.primary)
                            )
                    }
                    .buttonStyle(.plain)
                }

                Picker("Time range", selection: $selectedFilter) {
                    ForEach(ExpenseTimeFilter.allCases) { filter in
                        Text(filter.title).tag(filter)
                    }
                }
                .pickerStyle(.segmented)
            }

            if !expenseStore.activeRecurringPlans.isEmpty {
                SurfaceCard {
                    VStack(alignment: .leading, spacing: 14) {
                        Text("Recurring expenses")
                            .font(.headline.weight(.semibold))
                            .foregroundStyle(AppPalette.textPrimary)

                        Text("Recurring plans still create individual transactions on their scheduled dates, so burn rate and runway stay based on real entries.")
                            .font(.subheadline)
                            .foregroundStyle(AppPalette.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)

                        ForEach(expenseStore.activeRecurringPlans.prefix(3)) { plan in
                            HStack(alignment: .top, spacing: 12) {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(plan.label)
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(AppPalette.textPrimary)

                                    Text("\(plan.frequency.scheduleLabel) · Next \(nextOccurrenceText(for: plan))")
                                        .font(.caption)
                                        .foregroundStyle(AppPalette.textSecondary)
                                }

                                Spacer()

                                Button("Stop") {
                                    expenseStore.deactivateRecurringPlan(id: plan.id)
                                }
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(AppPalette.danger)
                            }
                            .padding(12)
                            .background(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .fill(AppPalette.surfaceSecondary)
                            )
                        }

                        if expenseStore.activeRecurringPlans.count > 3 {
                            Text("+\(expenseStore.activeRecurringPlans.count - 3) more active recurring plans")
                                .font(.caption)
                                .foregroundStyle(AppPalette.textSecondary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            if let topBudget = aiService.budgetRecommendations.first {
                SurfaceCard {
                    VStack(alignment: .leading, spacing: 12) {
                        if aiService.isRefreshingExpenseInsights {
                            ActivityPill(title: "Refreshing AI budget target")
                        }

                        HStack(spacing: 14) {
                            Image(systemName: topBudget.category.symbol)
                                .font(.headline.weight(.semibold))
                                .foregroundStyle(AppPalette.accent)
                                .frame(width: 42, height: 42)
                                .background(
                                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                                        .fill(AppPalette.accent.opacity(0.14))
                                )

                            VStack(alignment: .leading, spacing: 4) {
                                Text("\(topBudget.category.title) budget target")
                                    .font(.headline.weight(.semibold))
                                    .foregroundStyle(AppPalette.textPrimary)

                                Text("Aim for about \(topBudget.weeklyLimit.currencyString) per week. \(topBudget.rationale)")
                                    .font(.subheadline)
                                    .foregroundStyle(AppPalette.textSecondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .animation(.easeInOut(duration: 0.18), value: aiService.isRefreshingExpenseInsights)
                }
            } else if aiService.isRefreshingExpenseInsights {
                LoadingStateCard(
                    title: "Refreshing AI budget target",
                    message: "Updating spending guidance from your latest expense pattern."
                )
            }

            SurfaceCard {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(alignment: .top, spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(filteredContent.filter.summaryTitle)
                                .font(.headline.weight(.semibold))
                                .foregroundStyle(AppPalette.textPrimary)

                            Text(filteredContent.filter.summarySubtitle)
                                .font(.subheadline)
                                .foregroundStyle(AppPalette.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        Spacer()

                        Text(filteredContent.totalSpent.currencyString)
                            .font(.title3.weight(.bold))
                            .foregroundStyle(AppPalette.textPrimary)
                            .monospacedDigit()
                    }

                    if selectedFilter == .weekly {
                        MiniStatCard(
                            title: "Average per day",
                            value: filteredContent.averageDailySpend.currencyString
                        )
                    }

                    if selectedFilter == .monthly, !filteredContent.categoryBreakdown.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Category breakdown")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(AppPalette.textPrimary)

                            ForEach(filteredContent.categoryBreakdown) { item in
                                HStack(spacing: 12) {
                                    Image(systemName: item.category.symbol)
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(AppPalette.accent)
                                        .frame(width: 18)

                                    Text(item.category.title)
                                        .font(.subheadline)
                                        .foregroundStyle(AppPalette.textPrimary)

                                    Spacer()

                                    Text(item.amount.currencyString)
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(AppPalette.textPrimary)
                                        .monospacedDigit()
                                }
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            SurfaceCard {
                if filteredContent.expenses.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(filteredContent.emptyStateTitle)
                            .font(.headline.weight(.semibold))
                            .foregroundStyle(AppPalette.textPrimary)

                        Text(filteredContent.emptyStateMessage)
                            .font(.subheadline)
                            .foregroundStyle(AppPalette.textSecondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 4)
                } else {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(filteredContent.expenses) { expense in
                            ExpenseRow(
                                expense: expense,
                                recurringFrequency: expense.recurringPlanID.flatMap { recurringPlansByID[$0]?.frequency },
                                onEdit: {
                                    editingExpense = expense
                                    showingEditor = true
                                },
                                onDelete: {
                                    pendingDeleteExpense = expense
                                },
                                onStopRecurring: expense.recurringPlanID.map { planID in
                                    { expenseStore.deactivateRecurringPlan(id: planID) }
                                }
                            )
                        }
                    }
                }
            }
        }
        .sheet(isPresented: $showingEditor, onDismiss: { editingExpense = nil }) {
            ExpenseEditorSheet(expense: editingExpense) { draft, recurringFrequency in
                if let editingExpense {
                    return expenseStore.edit(id: editingExpense.id, with: draft)
                } else {
                    return expenseStore.add(draft, recurringFrequency: recurringFrequency)
                }
            }
            .environmentObject(expenseStore)
            .environmentObject(aiService)
        }
        .confirmationDialog(
            "Delete expense?",
            isPresented: Binding(
                get: { pendingDeleteExpense != nil },
                set: { if !$0 { pendingDeleteExpense = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                if let pendingDeleteExpense {
                    expenseStore.delete(id: pendingDeleteExpense.id)
                }
                pendingDeleteExpense = nil
            }
        } message: {
            Text("This will immediately change weekly spend, burn rate, and runway.")
        }
    }

    private func nextOccurrenceText(for plan: RecurringExpensePlan) -> String {
        guard let nextDate = expenseStore.nextOccurrenceDate(for: plan) else {
            return "paused"
        }

        return nextDate.formatted(.dateTime.month(.abbreviated).day())
    }
}

private enum ExpenseTimeFilter: String, CaseIterable, Identifiable {
    case daily
    case weekly
    case monthly

    var id: String { rawValue }

    var title: String {
        switch self {
        case .daily:
            return "Daily"
        case .weekly:
            return "Weekly"
        case .monthly:
            return "Monthly"
        }
    }

    var summaryTitle: String {
        switch self {
        case .daily:
            return "Today’s spending"
        case .weekly:
            return "Last 7 days"
        case .monthly:
            return "This month"
        }
    }

    var summarySubtitle: String {
        switch self {
        case .daily:
            return "Expenses recorded today."
        case .weekly:
            return "Expenses from the most recent seven days. Burn rate still uses the rolling 7-day average."
        case .monthly:
            return "Expenses recorded in the current calendar month."
        }
    }
}

private struct ExpenseFilterContent {
    let filter: ExpenseTimeFilter
    let expenses: [Expense]
    let totalSpent: Double
    let averageDailySpend: Double
    let categoryBreakdown: [CategoryBreakdownItem]

    init(expenses: [Expense], filter: ExpenseTimeFilter, referenceDate: Date = Date()) {
        self.filter = filter

        let calendar = Calendar.current
        let filteredExpenses = expenses
            .filter { expense in
                switch filter {
                case .daily:
                    return calendar.isDate(expense.date, inSameDayAs: referenceDate)
                case .weekly:
                    guard let sevenDaysAgo = calendar.date(byAdding: .day, value: -6, to: calendar.startOfDay(for: referenceDate)) else {
                        return false
                    }
                    return expense.date >= sevenDaysAgo && expense.date <= referenceDate
                case .monthly:
                    return calendar.isDate(expense.date, equalTo: referenceDate, toGranularity: .month)
                }
            }
            .sorted {
                if $0.date == $1.date {
                    return $0.createdAt > $1.createdAt
                }
                return $0.date > $1.date
            }

        self.expenses = filteredExpenses
        self.totalSpent = filteredExpenses.reduce(0) { $0 + $1.amount }
        self.averageDailySpend = filter == .weekly ? totalSpent / 7 : 0

        if filter == .monthly {
            let grouped = Dictionary(grouping: filteredExpenses, by: \.category)
                .map { category, items in
                    CategoryBreakdownItem(
                        category: category,
                        amount: items.reduce(0) { $0 + $1.amount }
                    )
                }
                .sorted { lhs, rhs in
                    if lhs.amount == rhs.amount {
                        return lhs.category.title < rhs.category.title
                    }
                    return lhs.amount > rhs.amount
                }
            self.categoryBreakdown = grouped
        } else {
            self.categoryBreakdown = []
        }
    }

    var emptyStateTitle: String {
        switch filter {
        case .daily:
            return "No expenses today"
        case .weekly:
            return "No expenses in the last 7 days"
        case .monthly:
            return "No expenses this month"
        }
    }

    var emptyStateMessage: String {
        switch filter {
        case .daily:
            return "Log an expense today to keep your daily record current."
        case .weekly:
            return "Add expenses as they happen to keep the 7-day view and runway forecast honest."
        case .monthly:
            return "Once you log expenses this month, the category breakdown will appear here."
        }
    }
}

private struct CategoryBreakdownItem: Identifiable, Hashable {
    let category: ExpenseCategory
    let amount: Double

    var id: ExpenseCategory { category }
}

private struct ExpenseRow: View {
    let expense: Expense
    let recurringFrequency: RecurringExpenseFrequency?
    let onEdit: () -> Void
    let onDelete: () -> Void
    let onStopRecurring: (() -> Void)?

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: expense.category.symbol)
                .font(.headline.weight(.semibold))
                .foregroundStyle(AppPalette.accent)
                .frame(width: 42, height: 42)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(AppPalette.accent.opacity(0.14))
                )

            VStack(alignment: .leading, spacing: 6) {
                Text(expense.label)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppPalette.textPrimary)

                Text("\(expense.category.title) · \(expense.date.formatted(.dateTime.month(.abbreviated).day()))")
                    .font(.caption)
                    .foregroundStyle(AppPalette.textSecondary)

                if !expense.tags.isEmpty || recurringFrequency != nil {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            if let recurringFrequency {
                                SmallChip(title: recurringFrequency.scheduleLabel)
                            }

                            ForEach(expense.tags, id: \.self) { tag in
                                SmallChip(title: tag)
                            }
                        }
                    }
                }
            }

            Spacer()

            Text(expense.amount.currencyString)
                .font(.headline.weight(.semibold))
                .foregroundStyle(AppPalette.textPrimary)
                .monospacedDigit()

            Menu {
                Button("Edit") {
                    onEdit()
                }

                Button("Delete", role: .destructive) {
                    onDelete()
                }

                if let onStopRecurring {
                    Button("Stop recurring series", role: .destructive) {
                        onStopRecurring()
                    }
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.title3)
                    .foregroundStyle(AppPalette.textSecondary)
            }
            .buttonStyle(.plain)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(AppPalette.surfaceSecondary)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(AppPalette.border, lineWidth: 1)
        )
    }
}

private struct ExpenseEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var expenseStore: ExpenseStore
    @EnvironmentObject private var aiService: AIInsightService

    private let expense: Expense?
    private let onSave: (ExpenseDraft, RecurringExpenseFrequency?) -> Bool

    @State private var category: ExpenseCategory
    @State private var label: String
    @State private var amountText: String
    @State private var date: Date
    @State private var notes: String
    @State private var shouldRepeat: Bool
    @State private var recurringFrequency: RecurringExpenseFrequency
    @State private var userSelectedCategory: Bool
    @State private var liveSuggestion: AIExpenseSuggestion?
    @State private var isRefreshingSuggestion = false
    @State private var suggestionTask: Task<Void, Never>?

    init(expense: Expense?, onSave: @escaping (ExpenseDraft, RecurringExpenseFrequency?) -> Bool) {
        self.expense = expense
        self.onSave = onSave
        _category = State(initialValue: expense?.category ?? .food)
        _label = State(initialValue: expense?.label ?? "")
        _amountText = State(initialValue: expense.map { String(Int($0.amount)) } ?? "")
        _date = State(initialValue: expense?.date ?? Date())
        _notes = State(initialValue: expense?.notes ?? "")
        _shouldRepeat = State(initialValue: false)
        _recurringFrequency = State(initialValue: .monthly)
        _userSelectedCategory = State(initialValue: expense != nil)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Expense") {
                    Picker("Category", selection: categoryBinding) {
                        ForEach(ExpenseCategory.allCases) { category in
                            Label(category.title, systemImage: category.symbol)
                                .tag(category)
                        }
                    }

                    TextField("Label", text: $label)
                    TextField("Amount", text: $amountText)
                        .keyboardType(.decimalPad)
                    DatePicker("Date", selection: $date, displayedComponents: .date)
                    TextField("Notes", text: $notes, axis: .vertical)
                        .lineLimit(3...6)
                }

                if expense == nil {
                    Section("Repeat") {
                        Toggle("Repeat this expense", isOn: $shouldRepeat)

                        if shouldRepeat {
                            Picker("Frequency", selection: $recurringFrequency) {
                                ForEach(RecurringExpenseFrequency.allCases) { frequency in
                                    Text(frequency.title).tag(frequency)
                                }
                            }

                            Text("CareerFuel will generate individual \(recurringFrequency.title.lowercased()) transactions from the selected date onward.")
                                .font(.footnote)
                                .foregroundStyle(AppPalette.textSecondary)
                        }
                    }
                } else if expense?.recurringPlanID != nil {
                    Section("Recurring series") {
                        Text("This entry belongs to a recurring expense series. Editing here only changes this individual transaction.")
                            .font(.footnote)
                            .foregroundStyle(AppPalette.textSecondary)
                    }
                }

                if let validationIssue {
                    Section("Input check") {
                        Label(validationIssue.message, systemImage: "exclamationmark.triangle.fill")
                            .font(.subheadline)
                            .foregroundStyle(AppPalette.danger)
                    }
                }

                if isRefreshingSuggestion || liveSuggestion != nil {
                    Section("AI Suggestion") {
                        if isRefreshingSuggestion {
                            HStack(spacing: 10) {
                                ProgressView()
                                    .tint(AppPalette.primary)
                                Text("Updating category suggestion…")
                                    .font(.subheadline)
                                    .foregroundStyle(AppPalette.textSecondary)
                            }
                        }

                        if let suggestion = liveSuggestion {
                            HStack {
                                Label(suggestion.suggestedCategory.title, systemImage: suggestion.suggestedCategory.symbol)
                                Spacer()
                                Text("\(Int((suggestion.confidence * 100).rounded()))% confidence")
                                    .foregroundStyle(AppPalette.textSecondary)
                            }

                            if suggestion.suggestedCategory != category {
                                Button("Apply AI category") {
                                    category = suggestion.suggestedCategory
                                    userSelectedCategory = false
                                }
                            }

                            if !suggestion.tags.isEmpty {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("Suggested tags")
                                        .font(.subheadline.weight(.semibold))

                                    ScrollView(.horizontal, showsIndicators: false) {
                                        HStack(spacing: 8) {
                                            ForEach(suggestion.tags, id: \.self) { tag in
                                                SmallChip(title: tag)
                                            }
                                        }
                                        .padding(.vertical, 2)
                                    }
                                }
                            }

                            VStack(alignment: .leading, spacing: 8) {
                                Text("Saving actions")
                                    .font(.subheadline.weight(.semibold))

                                ForEach(suggestion.savingActions, id: \.self) { action in
                                    Label(action, systemImage: "sparkles")
                                        .font(.subheadline)
                                        .foregroundStyle(AppPalette.textPrimary)
                                }
                            }
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(AppPalette.background)
            .navigationTitle(expense == nil ? "Add Expense" : "Edit Expense")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button(expense == nil ? "Save" : "Update") {
                        guard let amount = Double(amountText), amount > 0 else { return }
                        let didSave = onSaveAction(
                            amount: amount,
                            recurringFrequency: shouldRepeat ? recurringFrequency : nil
                        )
                        if didSave {
                            dismiss()
                        }
                    }
                    .disabled(
                        (Double(amountText) ?? 0) <= 0 ||
                        label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                        validationIssue != nil
                    )
                }
            }
            .onChange(of: label) { _, _ in
                scheduleSuggestionRefresh()
            }
            .onChange(of: notes) { _, _ in
                scheduleSuggestionRefresh()
            }
            .onChange(of: amountText) { _, _ in
                scheduleSuggestionRefresh()
            }
            .onAppear {
                scheduleSuggestionRefresh()
            }
            .onDisappear {
                suggestionTask?.cancel()
            }
        }
        .presentationDetents([.medium, .large])
    }

    private var categoryBinding: Binding<ExpenseCategory> {
        Binding(
            get: { category },
            set: {
                userSelectedCategory = true
                category = $0
            }
        )
    }

    private var suggestion: AIExpenseSuggestion? {
        liveSuggestion
    }

    private var resolvedCategory: ExpenseCategory {
        userSelectedCategory ? category : (suggestion?.suggestedCategory ?? category)
    }

    private var resolvedTags: [String] {
        let base = expense?.tags ?? []
        let aiTags = suggestion?.tags ?? []
        return Array(Set(base + aiTags)).sorted()
    }

    private var validationIssue: ExpenseInputIntegrityIssue? {
        expenseStore.validationIssue(
            for: ExpenseDraft(
                category: resolvedCategory,
                label: label,
                amount: Double(amountText) ?? 0,
                date: date,
                notes: notes,
                tags: resolvedTags
            )
        )
    }

    private func applySuggestionIfNeeded() {
        guard !userSelectedCategory, let suggestion else { return }
        category = suggestion.suggestedCategory
    }

    private func onSaveAction(amount: Double, recurringFrequency: RecurringExpenseFrequency?) -> Bool {
        let draft = ExpenseDraft(
            category: resolvedCategory,
            label: label,
            amount: amount,
            date: date,
            notes: notes,
            tags: resolvedTags
        )

        guard validationIssue == nil else { return false }
        return onSave(draft, recurringFrequency)
    }

    private func scheduleSuggestionRefresh() {
        suggestionTask?.cancel()

        let currentLabel = label
        let currentNotes = notes
        let currentAmount = Double(amountText) ?? 0
        let currentCategory = category

        guard !(currentLabel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
                currentNotes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
                currentAmount <= 0) else {
            liveSuggestion = nil
            isRefreshingSuggestion = false
            return
        }

        isRefreshingSuggestion = true

        suggestionTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(180))
            guard !Task.isCancelled else {
                isRefreshingSuggestion = false
                return
            }

            let suggestion = aiService.expenseSuggestion(
                label: currentLabel,
                amount: currentAmount,
                notes: currentNotes,
                currentCategory: currentCategory
            )

            guard !Task.isCancelled else {
                isRefreshingSuggestion = false
                return
            }
            liveSuggestion = suggestion
            applySuggestionIfNeeded()
            isRefreshingSuggestion = false
        }
    }
}
