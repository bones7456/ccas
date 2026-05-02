import AppKit
import SwiftUI

struct MenuContentView: View {
    @ObservedObject var viewModel: AccountSwitcherViewModel
    @State private var languageRevision = 0

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

                Button {
                    viewModel.refresh()
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .frame(width: 18, height: 18)
                }
                .buttonStyle(.borderless)
                .help(L10n.string(.refresh))
                .disabled(viewModel.isBusy)
            }

            Divider()

            accountList

            if !viewModel.statusText.isEmpty {
                Text(viewModel.statusText)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
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
        .frame(width: 340)
        .onAppear {
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
                        AccountRow(account: account) {
                            viewModel.switchTo(account)
                        }
                        .disabled(viewModel.isBusy)
                    }
                }
            }
            .frame(maxHeight: 260)
        }
    }
}

private struct AccountRow: View {
    let account: ManagedAccount
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: account.isActive ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(account.isActive ? Color.accentColor : Color.secondary)
                    .frame(width: 20)

                VStack(alignment: .leading, spacing: 2) {
                    Text(account.record.email)
                        .font(.subheadline.weight(.medium))
                        .lineLimit(1)
                        .truncationMode(.middle)

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
            .padding(.vertical, 7)
            .contentShape(Rectangle())
            .background {
                RoundedRectangle(cornerRadius: 8)
                    .fill(account.isActive ? Color.accentColor.opacity(0.12) : Color.clear)
            }
        }
        .buttonStyle(.plain)
        .help(account.isActive ? L10n.string(.currentAccount) : L10n.string(.switchToAccount))
    }
}
