import Combine
import UIKit
import SwiftUI
import Yosemite
import protocol Storage.StorageManagerType

/// View model for `ShippingLabelPackageDetails`.
///
final class ShippingLabelPackageDetailsViewModel: ObservableObject {

    private let order: Order
    private let orderItems: [OrderItem]
    private let currency: String
    private let currencyFormatter: CurrencyFormatter
    private let stores: StoresManager
    private let storageManager: StorageManagerType
    private var resultsControllers: ShippingLabelPackageDetailsResultsControllers?

    /// Products contained inside the Order and fetched from Core Data
    ///
    @Published private var products: [Product] = []

    /// ProductVariations contained inside the Order and fetched from Core Data
    ///
    @Published private var productVariations: [ProductVariation] = []

    /// The packages  response fetched from API
    ///
    @Published private var packagesResponse: ShippingLabelPackagesResponse?

    var dimensionUnit: String {
        return packagesResponse?.storeOptions.dimensionUnit ?? ""
    }
    var customPackages: [ShippingLabelCustomPackage] {
        return packagesResponse?.customPackages ?? []
    }
    var predefinedOptions: [ShippingLabelPredefinedOption] {
        return packagesResponse?.predefinedOptions ?? []
    }

    /// The weight unit used in the Store
    ///
    let weightUnit: String?

    /// The items rows observed by the main view `ShippingLabelPackageDetails`
    ///
    @Published private(set) var itemsRows: [ItemToFulfillRow] = []

    /// The id of the selected package. Defaults to last selected package, if any.
    ///
    @Published var selectedPackageID: String?

    /// The title of the selected package, if any.
    ///
    var selectedPackageName: String {
        if let selectedCustomPackage = selectedCustomPackage {
            return selectedCustomPackage.title
        }
        else if let selectedPredefinedPackage = selectedPredefinedPackage {
            return selectedPredefinedPackage.title
        }
        else {
            return ""
        }
    }
    @Published private(set) var selectedCustomPackage: ShippingLabelCustomPackage?
    @Published private(set) var selectedPredefinedPackage: ShippingLabelPredefinedPackage?
    @Published var totalWeight: String = ""

    /// Whether the user has edited the total package weight. If true, we won't make any automatic changes to the total weight.
    ///
    var isPackageWeightEdited: Bool = false

    /// Returns if the custom packages header should be shown in Package List
    ///
    var showCustomPackagesHeader: Bool {
        return customPackages.count > 0
    }

    /// Initially input package weight if any
    ///
    private var initialTotalWeight: String?

    init(order: Order,
         packagesResponse: ShippingLabelPackagesResponse?,
         selectedPackageID: String?,
         totalWeight: String?,
         formatter: CurrencyFormatter = CurrencyFormatter(currencySettings: ServiceLocator.currencySettings),
         stores: StoresManager = ServiceLocator.stores,
         storageManager: StorageManagerType = ServiceLocator.storageManager,
         weightUnit: String? = ServiceLocator.shippingSettingsService.weightUnit) {
        self.order = order
        self.orderItems = order.items
        self.currency = order.currency
        self.currencyFormatter = formatter
        self.stores = stores
        self.storageManager = storageManager
        self.weightUnit = weightUnit
        self.packagesResponse = packagesResponse
        self.selectedPackageID = selectedPackageID
        self.initialTotalWeight = totalWeight

        configureItemRows()
        configureTotalWeights()
        configureResultsControllers()
        syncProducts()
        syncProductVariations()
        setDefaultPackage()
    }

    /// Observe changes in products and variations to update item rows.
    ///
    private func configureItemRows() {
        $products.combineLatest($productVariations) { [weak self] (products, variations) in
            guard let self = self else { return [] }
            return self.generateItemsRows(products: products, productVariations: variations)
        }
        .assign(to: &$itemsRows)
    }

    /// Observe changes in selected custom package, products and variations to update total package weight.
    ///
    private func configureTotalWeights() {
        $selectedCustomPackage.combineLatest($products, $productVariations)
            .filter { [weak self] _ in self?.isPackageWeightEdited == false }
            .map { [weak self] (customPackage, products, variations) -> Double in
                self?.calculateTotalWeight(products: products, productVariations: variations, customPackage: customPackage) ?? 0
            }
            .map { [weak self] in
                let calculatedWeight = String($0)
                // Set the total weight as the initial value if it was input manually; otherwise use the calculated weight.
                if let initialTotalWeight = self?.initialTotalWeight,
                   calculatedWeight != initialTotalWeight {
                    self?.initialTotalWeight = nil
                    self?.isPackageWeightEdited = true
                    return initialTotalWeight
                }
                return calculatedWeight
            }
            .assign(to: &$totalWeight)
    }

    private func configureResultsControllers() {
        resultsControllers = ShippingLabelPackageDetailsResultsControllers(siteID: order.siteID,
                                                                           orderItems: order.items,
                                                                           storageManager: storageManager,
           onProductReload: { [weak self] (products) in
            guard let self = self else { return }
            self.products = products
        }, onProductVariationsReload: { [weak self] (productVariations) in
            guard let self = self else { return }
            self.productVariations = productVariations
        })

        products = resultsControllers?.products ?? []
        productVariations = resultsControllers?.productVariations ?? []
    }
}

// MARK: - Helper methods
private extension ShippingLabelPackageDetailsViewModel {
    /// Generate the items rows, creating an element in the array for every item (eg. if there is an item with quantity 3,
    /// we will generate 3 different items), and we will remove virtual products.
    ///
    func generateItemsRows(products: [Product], productVariations: [ProductVariation]) -> [ItemToFulfillRow] {
        var itemsToFulfill: [ItemToFulfillRow] = []
        for item in orderItems {
            let isVariation = item.variationID > 0
            var product: Product?
            var productVariation: ProductVariation?

            if isVariation {
                productVariation = productVariations.first { $0.productVariationID == item.variationID }
            }
            else {
                product = products.first { $0.productID == item.productID }
            }
            if product?.virtual == false || productVariation?.virtual == false {
                var tempItemQuantity = Double(truncating: item.quantity as NSDecimalNumber)

                for _ in 0..<item.quantity.intValue {
                    let attributes = item.attributes.map { VariationAttributeViewModel(orderItemAttribute: $0) }
                    var weight = Double(productVariation?.weight ?? product?.weight ?? "0") ?? 0
                    if tempItemQuantity < 1 {
                        weight *= tempItemQuantity
                    } else {
                        tempItemQuantity -= 1
                    }
                    let unit: String = weightUnit ?? ""
                    let subtitle = Localization.subtitle(weight: weight.description,
                                                         weightUnit: unit,
                                                         attributes: attributes)
                    itemsToFulfill.append(ItemToFulfillRow(title: item.name, subtitle: subtitle))
                }
            }
        }
        return itemsToFulfill
    }

    /// Calculate total weight based on the weight of the selected package if it's a custom package;
    /// And the products and products variation inside the order items, only if they are not virtual products.
    ///
    /// Note: Only custom package is needed for input because only custom packages have weight to be included in the total weight.
    ///
    func calculateTotalWeight(products: [Product], productVariations: [ProductVariation], customPackage: ShippingLabelCustomPackage?) -> Double {
        var tempTotalWeight: Double = 0

        // Add each order item's weight to the total weight.
        for item in orderItems {
            let isVariation = item.variationID > 0
            var product: Product?
            var productVariation: ProductVariation?

            if isVariation {
                productVariation = productVariations.first { $0.productVariationID == item.variationID }
            }
            else {
                product = products.first { $0.productID == item.productID }
            }
            if product?.virtual == false || productVariation?.virtual == false {
                let itemWeight = Double(productVariation?.weight ?? product?.weight ?? "0") ?? 0
                tempTotalWeight += itemWeight * Double(truncating: item.quantity as NSDecimalNumber)
            }
        }

        // Add selected package weight to the total weight.
        // Only custom packages have a defined weight, so we only do this if a custom package is selected.
        if let selectedPackage = customPackage {
            tempTotalWeight += selectedPackage.boxWeight
        }
        return tempTotalWeight
    }
}

// MARK: - UI utils methods
extension ShippingLabelPackageDetailsViewModel {

    // Return true if the done button in the package details screen should be enabled
    func isPackageDetailsDoneButtonEnabled() -> Bool {
        return !selectedPackageID.isNilOrEmpty && totalWeight.isNotEmpty && Double(totalWeight) != 0 && Double(totalWeight) != nil
    }
}

// MARK: - Package Selection
extension ShippingLabelPackageDetailsViewModel {
    func didSelectPackage(_ id: String) {
        selectCustomPackage(id)
        selectPredefinedPackage(id)
    }

    private func selectCustomPackage(_ id: String) {
        guard let packagesResponse = packagesResponse else {
            return
        }

        for customPackage in packagesResponse.customPackages {
            if customPackage.title == id {
                selectedCustomPackage = customPackage
                selectedPredefinedPackage = nil
                return
            }
        }
    }

    private func selectPredefinedPackage(_ id: String) {
        guard let packagesResponse = packagesResponse else {
            return
        }

        for option in packagesResponse.predefinedOptions {
            for predefinedPackage in option.predefinedPackages {
                if predefinedPackage.id == id {
                    selectedCustomPackage = nil
                    selectedPredefinedPackage = predefinedPackage
                    return
                }
            }
        }
    }

    /// Writes into the binding variable the final package selection value when confirmed.
    /// Also sets the total weight for the package, including the selected package weight (if any).
    ///
    func confirmPackageSelection() {
        if let selectedCustomPackage = selectedCustomPackage {
            selectedPackageID = selectedCustomPackage.title
        }
        else if let selectedPredefinedPackage = selectedPredefinedPackage {
            selectedPackageID = selectedPredefinedPackage.id
        }
    }

    /// Sets the package passed through the init method, or set the last selected package, if any, as the default selected package
    ///
    func setDefaultPackage() {
        guard let selectedPackageID = selectedPackageID ?? resultsControllers?.accountSettings?.lastSelectedPackageID else {
            return
        }
        didSelectPackage(selectedPackageID)
        confirmPackageSelection()
    }
}

/// API Requests
///
private extension ShippingLabelPackageDetailsViewModel {
    func syncProducts(onCompletion: ((Error?) -> ())? = nil) {
        let action = ProductAction.requestMissingProducts(for: order) { (error) in
            if let error = error {
                DDLogError("⛔️ Error synchronizing Products: \(error)")
                onCompletion?(error)
                return
            }

            onCompletion?(nil)
        }

        stores.dispatch(action)
    }

    func syncProductVariations(onCompletion: ((Error?) -> ())? = nil) {
        let action = ProductVariationAction.requestMissingVariations(for: order) { error in
            if let error = error {
                DDLogError("⛔️ Error synchronizing missing variations in an Order: \(error)")
                onCompletion?(error)
                return
            }
            onCompletion?(nil)
        }
        stores.dispatch(action)
    }
}

private extension ShippingLabelPackageDetailsViewModel {
    enum Localization {
        static let subtitleFormat =
            NSLocalizedString("%1$@", comment: "In Shipping Labels Package Details,"
                                + " the pattern used to show the weight of a product. For example, “1lbs”.")
        static let subtitleWithAttributesFormat =
            NSLocalizedString("%1$@・%2$@", comment: "In Shipping Labels Package Details if the product has attributes,"
                                + " the pattern used to show the attributes and weight. For example, “purple, has logo・1lbs”."
                                + " The %1$@ is the list of attributes (e.g. from variation)."
                                + " The %2$@ is the weight with the unit.")
        static func subtitle(weight: String?, weightUnit: String, attributes: [VariationAttributeViewModel]) -> String {
            let attributesText = attributes.map { $0.nameOrValue }.joined(separator: ", ")
            let formatter = WeightFormatter(weightUnit: weightUnit)
            let weight = formatter.formatWeight(weight: weight)
            if attributes.isEmpty {
                return String.localizedStringWithFormat(subtitleFormat, weight, weightUnit)
            } else {
                return String.localizedStringWithFormat(subtitleWithAttributesFormat, attributesText, weight)
            }
        }
    }
}

// MARK: - Methods for rendering a SwiftUI Preview
//
extension ShippingLabelPackageDetailsViewModel {

    static func sampleOrder() -> Order {
        return Order(siteID: 1234,
                     orderID: 963,
                     parentID: 0,
                     customerID: 11,
                     number: "963",
                     status: .processing,
                     currency: "USD",
                     customerNote: "",
                     dateCreated: date(with: "2018-04-03T23:05:12"),
                     dateModified: date(with: "2018-04-03T23:05:14"),
                     datePaid: date(with: "2018-04-03T23:05:14"),
                     discountTotal: "30.00",
                     discountTax: "1.20",
                     shippingTotal: "0.00",
                     shippingTax: "0.00",
                     total: "31.20",
                     totalTax: "1.20",
                     paymentMethodID: "stripe",
                     paymentMethodTitle: "Credit Card (Stripe)",
                     items: sampleItems(),
                     billingAddress: sampleAddress(),
                     shippingAddress: sampleAddress(),
                     shippingLines: sampleShippingLines(),
                     coupons: sampleCoupons(),
                     refunds: [],
                     fees: [])
    }

    static func sampleAddress() -> Address {
        return Address(firstName: "Johnny",
                       lastName: "Appleseed",
                       company: "",
                       address1: "234 70th Street",
                       address2: "",
                       city: "Niagara Falls",
                       state: "NY",
                       postcode: "14304",
                       country: "US",
                       phone: "333-333-3333",
                       email: "scrambled@scrambled.com")
    }

    static func sampleShippingLines() -> [ShippingLine] {
        return [ShippingLine(shippingID: 123,
                             methodTitle: "International Priority Mail Express Flat Rate",
                             methodID: "usps",
                             total: "133.00",
                             totalTax: "0.00",
                             taxes: [.init(taxID: 1, subtotal: "", total: "0.62125")])]
    }

    static func sampleCoupons() -> [OrderCouponLine] {
        let coupon1 = OrderCouponLine(couponID: 894,
                                      code: "30$off",
                                      discount: "30",
                                      discountTax: "1.2")

        return [coupon1]
    }

    static func sampleItems() -> [OrderItem] {
        let item1 = OrderItem(itemID: 890,
                              name: "Fruits Basket (Mix & Match Product)",
                              productID: 52,
                              variationID: 0,
                              quantity: 2,
                              price: NSDecimalNumber(integerLiteral: 30),
                              sku: "",
                              subtotal: "50.00",
                              subtotalTax: "2.00",
                              taxClass: "",
                              taxes: [.init(taxID: 1, subtotal: "2", total: "1.2")],
                              total: "30.00",
                              totalTax: "1.20",
                              attributes: [])

        let item2 = OrderItem(itemID: 891,
                              name: "Fruits Bundle",
                              productID: 234,
                              variationID: 0,
                              quantity: 1.5,
                              price: NSDecimalNumber(integerLiteral: 0),
                              sku: "5555-A",
                              subtotal: "10.00",
                              subtotalTax: "0.40",
                              taxClass: "",
                              taxes: [.init(taxID: 1, subtotal: "0.4", total: "0")],
                              total: "0.00",
                              totalTax: "0.00",
                              attributes: [])

        return [item1, item2]
    }

    static func date(with dateString: String) -> Date {
        guard let date = DateFormatter.Defaults.dateTimeFormatter.date(from: dateString) else {
            return Date()
        }
        return date
    }

    static func taxes() -> [OrderItemTax] {
        return [OrderItemTax(taxID: 75, subtotal: "0.45", total: "0.45")]
    }

    static func samplePackageDetails() -> ShippingLabelPackagesResponse {
        return ShippingLabelPackagesResponse(storeOptions: sampleShippingLabelStoreOptions(),
                                             customPackages: sampleShippingLabelCustomPackages(),
                                             predefinedOptions: sampleShippingLabelPredefinedOptions())
    }

    static func sampleShippingLabelStoreOptions() -> ShippingLabelStoreOptions {
        return ShippingLabelStoreOptions(currencySymbol: "$", dimensionUnit: "cm", weightUnit: "kg", originCountry: "US")
    }

    static func sampleShippingLabelCustomPackages() -> [ShippingLabelCustomPackage] {
        let customPackage1 = ShippingLabelCustomPackage(isUserDefined: true,
                                                        title: "Krabica",
                                                        isLetter: false,
                                                        dimensions: "1 x 2 x 3",
                                                        boxWeight: 1,
                                                        maxWeight: 0)
        let customPackage2 = ShippingLabelCustomPackage(isUserDefined: true,
                                                        title: "Obalka",
                                                        isLetter: true,
                                                        dimensions: "2 x 3 x 4",
                                                        boxWeight: 5,
                                                        maxWeight: 0)

        return [customPackage1, customPackage2]
    }

    static func sampleShippingLabelPredefinedOptions() -> [ShippingLabelPredefinedOption] {
        let predefinedPackages1 = [ShippingLabelPredefinedPackage(id: "small_flat_box",
                                                                  title: "Small Flat Rate Box",
                                                                  isLetter: false,
                                                                  dimensions: "21.91 x 13.65 x 4.13"),
                                  ShippingLabelPredefinedPackage(id: "medium_flat_box_top",
                                                                 title: "Medium Flat Rate Box 1, Top Loading",
                                                                 isLetter: false,
                                                                 dimensions: "28.57 x 22.22 x 15.24")]
        let predefinedOption1 = ShippingLabelPredefinedOption(title: "USPS Priority Mail Flat Rate Boxes",
                                                              predefinedPackages: predefinedPackages1)

        let predefinedPackages2 = [ShippingLabelPredefinedPackage(id: "LargePaddedPouch",
                                                                  title: "Large Padded Pouch",
                                                                  isLetter: true,
                                                                  dimensions: "30.22 x 35.56 x 2.54")]
        let predefinedOption2 = ShippingLabelPredefinedOption(title: "DHL Express",
                                                              predefinedPackages: predefinedPackages2)

        return [predefinedOption1, predefinedOption2]
    }
}
