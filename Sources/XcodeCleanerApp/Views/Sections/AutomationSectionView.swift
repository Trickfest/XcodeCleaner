import SwiftUI
import XcodeInventoryCore

struct AutomationSectionView: View {
    @ObservedObject var viewModel: InventoryViewModel
    let openReportsSection: () -> Void

    @State private var formState = AutomationPolicyFormState()

    var body: some View {
        let duePolicyCount = AutomationPolicies.duePolicies(
            from: viewModel.automationPolicies,
            now: Date()
        ).count

        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("Automation Center")
                    .font(.headline)
                Text("Manage policy lifecycle, execution, and reporting in one workflow-focused section.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                automationOperationsPanel(duePolicyCount: duePolicyCount)

                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: 12) {
                        automationPolicyListPanel()
                            .frame(maxWidth: .infinity, alignment: .leading)
                        automationPolicyCreatePanel()
                            .frame(width: 360, alignment: .topLeading)
                    }
                    VStack(alignment: .leading, spacing: 12) {
                        automationPolicyListPanel()
                        automationPolicyCreatePanel()
                    }
                }

                automationReportingShortcutPanel
            }
        }
    }

    private func automationOperationsPanel(duePolicyCount: Int) -> some View {
        let statusMessage = viewModel.automationStatusMessage
        let statusTone = AppPresentation.automationStatusTone(for: statusMessage, isExecuting: viewModel.isExecuting)

        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Operations")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                if viewModel.isExecuting {
                    HStack(spacing: 6) {
                        ProgressView()
                            .controlSize(.small)
                        Text("Running...")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            HStack(spacing: 8) {
                Text("Policies: \(viewModel.automationPolicies.count)")
                    .font(.caption.monospacedDigit())
                Text("Due now: \(duePolicyCount)")
                    .font(.caption.monospacedDigit())
                Text("History loaded: \(viewModel.automationRunHistory.count)")
                    .font(.caption.monospacedDigit())
            }
            .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Image(systemName: AppPresentation.automationStatusSymbol(for: statusTone))
                        .foregroundStyle(AppPresentation.color(for: statusTone))
                    Text("Status")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(AppPresentation.color(for: statusTone))
                    Spacer()
                }
                Text(statusMessage)
                    .font(.caption)
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(8)
            .background(AppPresentation.color(for: statusTone).opacity(0.12), in: RoundedRectangle(cornerRadius: 8))

            Text("Scheduling note: missed intervals do not queue. If a policy is overdue, \"Run Due Policies Now\" evaluates it once and then schedules from the latest evaluation run.")
                .font(.caption2)
                .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                Button("Run Due Policies Now") {
                    viewModel.runDueAutomationPoliciesNow()
                }
                .disabled(viewModel.isExecuting || viewModel.isLoading)

                Button("Refresh Automation Data") {
                    viewModel.loadAutomationState()
                }
                .disabled(viewModel.isExecuting || viewModel.isLoading)
            }
        }
        .padding(10)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8))
    }

    private func automationPolicyListPanel() -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Configured Policies (\(viewModel.automationPolicies.count))")
                .font(.subheadline.weight(.semibold))

            if viewModel.automationPolicies.isEmpty {
                Text("No automation policies yet.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(viewModel.automationPolicies) { policy in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(policy.name)
                                .font(.callout.weight(.medium))
                            Spacer()
                            if AppPresentation.isAutomationPolicyDueNow(policy) {
                                Text("DUE")
                                    .font(.caption2.weight(.bold))
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 3)
                                    .background(Color.orange.opacity(0.2))
                                    .clipShape(RoundedRectangle(cornerRadius: 4))
                            }
                            Text(policy.isEnabled ? "ENABLED" : "DISABLED")
                                .font(.caption2.weight(.bold))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 3)
                                .background(policy.isEnabled ? Color.green.opacity(0.2) : Color.gray.opacity(0.2))
                                .clipShape(RoundedRectangle(cornerRadius: 4))
                        }

                        Text("Schedule: \(AppPresentation.formattedSchedule(for: policy))")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Text("Categories: \(policy.selection.selectedCategoryKinds.map(AppPresentation.title(for:)).joined(separator: ", "))")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Text("Skip if tools running: \(policy.skipIfToolsRunning ? "Yes" : "No"), Direct delete fallback: \(policy.allowDirectDelete ? "Yes" : "No")")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        if let minAgeDays = policy.minAgeDays {
                            Text("Minimum age: \(minAgeDays) day(s)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        if let minBytes = policy.minTotalReclaimBytes {
                            Text("Minimum reclaim: \(AppPresentation.formatBytes(minBytes))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Text("Last evaluation: \(AppPresentation.formatDateTime(policy.lastEvaluatedRunAt))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("Last successful cleanup: \(AppPresentation.formatDateTime(policy.lastSuccessfulRunAt))")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        HStack(spacing: 8) {
                            Toggle(
                                isOn: Binding(
                                    get: { policy.isEnabled },
                                    set: { newValue in
                                        viewModel.setAutomationPolicyEnabled(
                                            policyID: policy.id,
                                            isEnabled: newValue
                                        )
                                    }
                                )
                            ) {
                                Text("Enabled")
                            }
                            .toggleStyle(.switch)

                            Button("Run Now") {
                                viewModel.runAutomationPolicyNow(policyID: policy.id)
                            }
                            .disabled(viewModel.isExecuting || viewModel.isLoading)

                            Button(role: .destructive) {
                                viewModel.deleteAutomationPolicy(policyID: policy.id)
                            } label: {
                                Text("Delete")
                            }
                            .disabled(viewModel.isExecuting || viewModel.isLoading)
                        }
                    }
                    .padding(10)
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8))
                }
            }
        }
        .padding(10)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8))
    }

    private func automationPolicyCreatePanel() -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Create Policy")
                .font(.subheadline.weight(.semibold))

            TextField("Policy name", text: $formState.name)
                .textFieldStyle(.roundedBorder)

            TextField("Every hours (blank = manual only)", text: $formState.everyHours)
                .textFieldStyle(.roundedBorder)
            TextField("Min age days", text: $formState.minAgeDays)
                .textFieldStyle(.roundedBorder)
            TextField("Min reclaim bytes", text: $formState.minTotalBytes)
                .textFieldStyle(.roundedBorder)

            Text("Categories")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text("Aggregate Xcode Applications and device support cleanup are CLI-only; GUI policies use explicit cleanup scope selection.")
                .font(.caption2)
                .foregroundStyle(.secondary)
            ForEach(
                StorageCategoryKind.allCases.filter { $0 != .deviceSupport && $0 != .xcodeApplications },
                id: \.rawValue
            ) { kind in
                Toggle(isOn: categoryBinding(for: kind)) {
                    Text(AppPresentation.title(for: kind))
                }
            }

            Toggle("Skip if Xcode or the Simulator app is running", isOn: $formState.skipIfToolsRunning)
            Toggle("Allow direct delete fallback", isOn: $formState.allowDirectDelete)

            if let validationError = formState.validationError {
                Text(validationError)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            Button("Create Automation Policy") {
                createPolicyFromForm()
            }
            .disabled(viewModel.isExecuting || viewModel.isLoading)
        }
        .padding(10)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8))
    }

    private var automationReportingShortcutPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Reporting and Exports")
                .font(.subheadline.weight(.semibold))
            Text("Run history, trend summaries, and export actions are now centralized in the Reports section.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Button("Open Reports Section") {
                openReportsSection()
            }
        }
        .padding(10)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8))
    }

    private func categoryBinding(for kind: StorageCategoryKind) -> Binding<Bool> {
        Binding(
            get: { formState.categoryKinds.contains(kind) },
            set: { isSelected in
                if isSelected {
                    formState.categoryKinds.insert(kind)
                } else {
                    formState.categoryKinds.remove(kind)
                }
            }
        )
    }

    private func createPolicyFromForm() {
        guard let request = formState.makeCreationRequest() else {
            return
        }
        viewModel.createAutomationPolicy(
            name: request.name,
            categoryKinds: request.categoryKinds,
            everyHours: request.everyHours,
            minAgeDays: request.minAgeDays,
            minTotalReclaimBytes: request.minTotalReclaimBytes,
            skipIfToolsRunning: request.skipIfToolsRunning,
            allowDirectDelete: request.allowDirectDelete
        )
        formState.resetAfterSubmit()
    }
}
