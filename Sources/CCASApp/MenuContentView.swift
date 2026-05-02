import AppKit
import SwiftUI

struct MenuContentView: View {
    @ObservedObject var viewModel: AccountSwitcherViewModel
    @State private var languageRevision = 0
    @State private var quotaClock = Date()

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header

            HStack(spacing: 8) {
                Button {
                    viewModel.addCurrentAccount()
                } label: {
                    Label(L10n.string(.addAccount), systemImage: "plus.circle.fill")
                }
                .keyboardShortcut("n")
                .disabled(viewModel.isBusy)

                Spacer()

                if let quotaAgeText = viewModel.quotaAgeText(now: quotaClock) {
                    Text(quotaAgeText)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .fixedSize()
                }

                Button {
                    viewModel.refresh()
                } label: {
                    if viewModel.isFetchingQuota {
                        ProgressView()
                            .controlSize(.small)
                            .scaleEffect(0.7)
                            .frame(width: 18, height: 18)
                    } else {
                        Image(systemName: "arrow.clockwise")
                            .frame(width: 18, height: 18)
                    }
                }
                .frame(width: 22, height: 22)
                .buttonStyle(.borderless)
                .help(viewModel.isFetchingQuota ? L10n.string(.quotaLoading) : L10n.string(.refresh))
                .disabled(viewModel.isBusy || viewModel.isFetchingQuota)
            }
            .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { date in
                quotaClock = date
            }

            Divider()

            accountList

            if !viewModel.statusText.isEmpty {
                Text(viewModel.statusText)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(4)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Divider()

            HStack {
                Text("~/.ccas")
                    .font(.caption)
                    .foregroundStyle(.tertiary)

                Spacer()

                Button(L10n.string(.quit)) {
                    NSApplication.shared.terminate(nil)
                }
                .buttonStyle(.borderless)
            }
        }
        .id(languageRevision)
        .padding(14)
        .frame(width: 380)
        .onAppear {
            quotaClock = Date()
            viewModel.refresh()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSLocale.currentLocaleDidChangeNotification)) { _ in
            languageRevision += 1
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(nsColor: .controlBackgroundColor))
                Image(nsImage: AppAssets.appIcon(size: 34))
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .padding(2)
            }
            .frame(width: 38, height: 38)

            VStack(alignment: .leading, spacing: 2) {
                Text(viewModel.currentTitle)
                    .font(.headline)
                    .lineLimit(1)
                    .truncationMode(.middle)

                Text(viewModel.currentSubtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            if viewModel.isBusy {
                ProgressView()
                    .controlSize(.small)
            }
        }
    }

    @ViewBuilder
    private var accountList: some View {
        if viewModel.accounts.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text(L10n.string(.noAccountsTitle))
                    .font(.subheadline.weight(.medium))
                Text(L10n.string(.noAccountsBody))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 8)
        } else {
            ScrollView {
                LazyVStack(spacing: 6) {
                    ForEach(viewModel.accounts) { account in
                        AccountRow(account: account, quotaState: viewModel.quotaState(for: account), isBusy: viewModel.isBusy) {
                            viewModel.switchTo(account)
                        }
                    }
                }
            }
            .frame(maxHeight: 420)
        }
    }
}

private struct AccountRow: View {
    let account: ManagedAccount
    let quotaState: AccountQuotaLoadState?
    let isBusy: Bool
    let action: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button(action: action) {
                HStack(spacing: 10) {
                    Image(systemName: account.isActive ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(account.isActive ? Color.accentColor : Color.secondary)
                        .frame(width: 20)

                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 0) {
                            Text(account.record.email)
                                .lineLimit(1)
                                .truncationMode(.middle)

                            if let planText {
                                Text(" (\(planText))")
                                    .foregroundStyle(.secondary)
                                    .fixedSize()
                            }
                        }
                        .font(.subheadline.weight(.medium))

                        Text(L10n.string(.accountDisplay, account.number, account.displayTag))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    Spacer()

                    Image(systemName: "arrow.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                        .opacity(account.isActive ? 0 : 1)
                }
                .padding(.horizontal, 8)
                .padding(.top, 7)
                .padding(.bottom, quotaState == nil ? 7 : 0)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(isBusy)
            .help(account.isActive ? L10n.string(.currentAccount) : L10n.string(.switchToAccount))

            if let quotaState {
                AccountQuotaView(state: quotaState)
                    .padding(.leading, 38)
                    .padding(.trailing, 8)
                    .padding(.bottom, 8)
            }
        }
        .background {
            RoundedRectangle(cornerRadius: 8)
                .fill(account.isActive ? Color.accentColor.opacity(0.12) : Color.clear)
        }
    }

    private var planText: String? {
        guard let quotaState, case .loaded(let info) = quotaState else {
            return nil
        }

        switch info {
        case .personal(let plan, _, _), .monetary(let plan, _):
            guard plan != .unknown else {
                return nil
            }
            return plan.displayName.lowercased()
        case .unavailable:
            return nil
        }
    }
}

private struct AccountQuotaView: View {
    let state: AccountQuotaLoadState

    var body: some View {
        switch state {
        case .loading:
            HStack(spacing: 6) {
                ProgressView()
                    .controlSize(.mini)
                    .scaleEffect(0.7)
                Text(L10n.string(.quotaLoading))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        case .loaded(let info):
            quotaInfo(info)
        case .failed(let message):
            Text(L10n.string(.quotaFailed, message))
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private func quotaInfo(_ info: AccountQuotaInfo) -> some View {
        switch info {
        case .personal(_, let fiveHour, let sevenDay):
            VStack(alignment: .leading, spacing: 5) {
                if let fiveHour {
                    QuotaProgressLine(title: L10n.string(.quotaFiveHour), window: fiveHour)
                }
                if let sevenDay {
                    QuotaProgressLine(title: L10n.string(.quotaWeek), window: sevenDay)
                }
                if fiveHour == nil && sevenDay == nil {
                    Text(L10n.string(.quotaNoData))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        case .monetary(_, let quota):
            VStack(alignment: .leading, spacing: 5) {
                MonetaryQuotaLine(quota: quota)
            }
        case .unavailable(let message):
            Text(message)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct QuotaProgressLine: View {
    let title: String
    let window: QuotaWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Text(title)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .frame(width: 38, alignment: .leading)

                ProgressView(value: progressValue)
                    .progressViewStyle(.linear)

                Text(percentText)
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(width: 38, alignment: .trailing)
            }

            if let resetsAt = window.resetsAt {
                Text(L10n.string(.quotaReset, Self.resetFormatter.string(from: resetsAt)))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private var progressValue: Double {
        min(max(window.usedPercentage / 100, 0), 1)
    }

    private var percentText: String {
        "\(Int(window.usedPercentage.rounded()))%"
    }

    private static let resetFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter
    }()
}

private struct MonetaryQuotaLine: View {
    let quota: MonetaryQuota

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Text(spentText)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)

                Spacer()

                if let percentage = quota.usedPercentage {
                    Text("\(Int(percentage.rounded()))%")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }

            if let percentage = quota.usedPercentage {
                ProgressView(value: min(max(percentage / 100, 0), 1))
                    .progressViewStyle(.linear)
            }

            if let resetsAt = quota.resetsAt {
                Text(L10n.string(.quotaReset, Self.resetFormatter.string(from: resetsAt)))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private var spentText: String {
        let used = moneyText(quota.usedMinorUnits) ?? moneyText(0) ?? "0"
        guard let limit = moneyText(quota.limitMinorUnits) else {
            return L10n.string(.quotaSpent, used, L10n.string(.quotaUnlimited))
        }
        return L10n.string(.quotaSpent, used, limit)
    }

    private func moneyText(_ minorUnits: Double?) -> String? {
        guard let minorUnits else {
            return nil
        }

        let currency = quota.currency.uppercased()
        let zeroMinorCurrencies: Set<String> = ["JPY", "KRW", "VND"]
        let amount = zeroMinorCurrencies.contains(currency) ? minorUnits : minorUnits / 100

        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = currency
        formatter.maximumFractionDigits = zeroMinorCurrencies.contains(currency) ? 0 : 2

        if let formatted = formatter.string(from: NSNumber(value: amount)) {
            return formatted
        }

        return "\(currency) \(amount)"
    }

    private static let resetFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter
    }()
}
