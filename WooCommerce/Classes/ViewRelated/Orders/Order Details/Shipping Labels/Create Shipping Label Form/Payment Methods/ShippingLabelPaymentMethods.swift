import SwiftUI
import Yosemite

struct ShippingLabelPaymentMethods: View {
    @ObservedObject private var viewModel: ShippingLabelPaymentMethodsViewModel
    @Environment(\.presentationMode) var presentation

    /// Completion callback
    ///
    typealias Completion = (_ newAccountSettings: ShippingLabelAccountSettings) -> Void
    private let onCompletion: Completion

    init(viewModel: ShippingLabelPaymentMethodsViewModel, completion: @escaping Completion) {
        self.viewModel = viewModel
        onCompletion = completion
    }

    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(spacing: 0) {
                    // Banner displayed when user can't edit payment methods
                    ShippingLabelPaymentMethodsTopBanner(width: geometry.size.width,
                                                         storeOwnerDisplayName: viewModel.storeOwnerDisplayName,
                                                         storeOwnerUsername:
                                                            viewModel.storeOwnerUsername)
                        .renderedIf(!viewModel.canEditPaymentMethod)

                    // Payment Methods list
                    ListHeaderView(text: Localization.paymentMethodsHeader, alignment: .left)
                        .textCase(.uppercase)

                    ForEach(viewModel.paymentMethods, id: \.paymentMethodID) { method in
                        let selected = method.paymentMethodID == viewModel.selectedPaymentMethodID
                        SelectableItemRow(title: "\(method.cardType.rawValue.capitalized) ****\(method.cardDigits)",
                                          subtitle: method.name,
                                          selected: selected)
                            .onTapGesture {
                                viewModel.didSelectPaymentMethod(withID: method.paymentMethodID)
                            }
                            .background(Color(.systemBackground))
                        Divider().padding(.leading, Constants.dividerPadding)
                    }
                    .disabled(!viewModel.canEditPaymentMethod)

                    ListHeaderView(text: String.localizedStringWithFormat(Localization.paymentMethodsFooter,
                                                                          viewModel.storeOwnerWPcomUsername,
                                                                          viewModel.storeOwnerWPcomEmail),
                                   alignment: .left)

                    Spacer()
                        .frame(height: Constants.spacerHeight)

                    // Email Receipts setting toggle
                    TitleAndToggleRow(title: String.localizedStringWithFormat(Localization.emailReceipt,
                                                                              viewModel.storeOwnerDisplayName,
                                                                              viewModel.storeOwnerUsername,
                                                                              viewModel.storeOwnerWPcomEmail),
                                      isOn: $viewModel.isEmailReceiptsEnabled)
                        .background(Color(.systemBackground))
                        .disabled(!viewModel.canEditNonpaymentSettings)
                }
            }
            .background(Color(.listBackground))
            .navigationBarTitle(Localization.navigationBarTitle)
            .navigationBarItems(trailing: Button(action: {
                viewModel.updateShippingLabelAccountSettings { newSettings in
                    onCompletion(newSettings)
                    presentation.wrappedValue.dismiss()
                }
            }, label: {
                if viewModel.isUpdating {
                    ProgressView()
                } else {
                    Text(Localization.doneButton)
                }
            })
        .disabled(!viewModel.isDoneButtonEnabled()))
        }
    }
}

private extension ShippingLabelPaymentMethods {
    enum Localization {
        static let navigationBarTitle = NSLocalizedString("Payment Method", comment: "Navigation bar title in the Shipping Label Payment Method screen")
        static let doneButton = NSLocalizedString("Done", comment: "Done navigation button in the Shipping Label Payment Method screen")
        static let paymentMethodsHeader = NSLocalizedString("Payment Method Selected", comment: "Header for list of payment methods in Payment Method screen")
        static let paymentMethodsFooter =
            NSLocalizedString("Credits cards are retrieved from the following WordPress.com account: %1$@ <%2$@>",
                              comment: "Footer for list of payment methods in Payment Method screen."
                                + " %1$@ is a placeholder for the WordPress.com username."
                                + " %2$@ is a placeholder for the WordPress.com email address.")
        static let emailReceipt =
            NSLocalizedString("Email the label purchase receipts to %1$@ (%2$@) at %3$@",
                              comment: "Label for the email receipts toggle in Payment Method screen."
                                + " %1$@ is a placeholder for the account display name."
                                + " %2$@ is a placeholder for the username."
                                + " %3$@ is a placeholder for the WordPress.com email address.")
    }

    enum Constants {
        static let dividerPadding: CGFloat = 48
        static let spacerHeight: CGFloat = 24
    }
}

struct ShippingLabelPaymentMethods_Previews: PreviewProvider {
    static var previews: some View {

        let viewModel = ShippingLabelPaymentMethodsViewModel(accountSettings: ShippingLabelPaymentMethodsViewModel.sampleAccountSettings())

        let accountSettingsWithoutEditPermissions = ShippingLabelPaymentMethodsViewModel.sampleAccountSettings(withPermissions: false)
        let disabledViewModel = ShippingLabelPaymentMethodsViewModel(accountSettings: accountSettingsWithoutEditPermissions)

        ShippingLabelPaymentMethods(viewModel: viewModel, completion: { (newAccountSettings) in
        })
            .colorScheme(.light)
            .previewDisplayName("Light mode")

        ShippingLabelPaymentMethods(viewModel: viewModel, completion: { (newAccountSettings) in
        })
            .colorScheme(.dark)
            .previewDisplayName("Dark Mode")

        ShippingLabelPaymentMethods(viewModel: disabledViewModel, completion: { (newAccountSettings) in
        })
            .previewDisplayName("Disabled state")

        ShippingLabelPaymentMethods(viewModel: viewModel, completion: { (newAccountSettings) in
        })
            .environment(\.sizeCategory, .accessibilityExtraExtraExtraLarge)
            .previewDisplayName("Accessibility: Large Font Size")

        ShippingLabelPaymentMethods(viewModel: viewModel, completion: { (newAccountSettings) in
        })
            .environment(\.layoutDirection, .rightToLeft)
            .previewDisplayName("Localization: Right-to-Left Layout")
    }
}