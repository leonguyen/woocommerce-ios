import Combine
import Yosemite
import protocol Storage.StorageManagerType

final class CreateOrderAddressFormViewModel: AddressFormViewModel, AddressFormViewModelProtocol {

    /// Address update callback
    ///
    private let onAddressUpdate: ((Address) -> Void)?

    init(siteID: Int64,
         onAddressUpdate: ((Address) -> Void)?,
         address1: Address?,
         address2: Address?,
         storageManager: StorageManagerType = ServiceLocator.storageManager,
         stores: StoresManager = ServiceLocator.stores,
         analytics: Analytics = ServiceLocator.analytics) {
        self.onAddressUpdate = onAddressUpdate

        super.init(siteID: siteID,
                   address: address1 ?? .empty,
                   storageManager: storageManager,
                   stores: stores,
                   analytics: analytics)
    }

    // MARK: - Protocol conformance

    var showEmailField: Bool {
        true
    }

    var viewTitle: String {
        Localization.newCustomerTitle
    }

    var sectionTitle: String {
        if showDifferentAddressForm {
            return Localization.billingAddressSection
        } else {
            return Localization.addressSection
        }
    }

    var showAlternativeUsageToggle: Bool {
        false
    }

    var alternativeUsageToggleTitle: String? {
        nil
    }

    var showDifferentAddressToggle: Bool {
        true
    }

    var differentAddressToggleTitle: String? {
        Localization.differentAddressToggleTitle
    }

    func saveAddress(onFinish: @escaping (Bool) -> Void) {
        onAddressUpdate?(updatedAddress)
        onFinish(true)
    }

    override func trackOnLoad() { }

    func userDidCancelFlow() { }
}

private extension CreateOrderAddressFormViewModel {

    // MARK: Constants
    enum Localization {
        static let newCustomerTitle = NSLocalizedString("New Customer", comment: "Title for the Shipping Address Form for New Customer")

        static let shippingTitle = NSLocalizedString("Shipping Address", comment: "Title for the Edit Shipping Address Form")
        static let billingTitle = NSLocalizedString("Billing Address", comment: "Title for the Edit Billing Address Form")

        static let addressSection = NSLocalizedString("ADDRESS", comment: "Details section title in the Edit Address Form")

        static let shippingAddressSection = NSLocalizedString("SHIPPING ADDRESS", comment: "Details section title in the Edit Address Form")
        static let billingAddressSection = NSLocalizedString("BILLING ADDRESS", comment: "Details section title in the Edit Address Form")

        static let differentAddressToggleTitle = NSLocalizedString("Add a different shipping address",
                                                                   comment: "Title for the Add a Different Address switch in the Address form")
    }
}
