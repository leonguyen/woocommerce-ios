import Foundation
import Storage

// MARK: - Storage.OrderTaxLine: ReadOnlyConvertible
//
extension Storage.OrderTaxLine: ReadOnlyConvertible {

    /// Updates the Storage.OrderTaxLine with the ReadOnly.
    ///
    public func update(with taxLine: Yosemite.OrderTaxLine) {
        taxID = taxLine.taxID
        rateCode = taxLine.rateCode
        rateID = taxLine.rateID
        label = taxLine.label
        isCompoundTaxRate = taxLine.isCompoundTaxRate
        totalTax = taxLine.totalTax
        totalShippingTax = taxLine.totalShippingTax
        ratePercent = taxLine.ratePercent
    }

    /// Returns a ReadOnly version of the receiver.
    ///
    public func toReadOnly() -> Yosemite.OrderTaxLine {
        let taxAttributes = attributes?.map { $0.toReadOnly() } ?? [Yosemite.OrderItemAttribute]()

        return OrderTaxLine(taxID: taxID,
                            rateCode: rateCode ?? "",
                            rateID: rateID,
                            label: label ?? "",
                            isCompoundTaxRate: isCompoundTaxRate,
                            totalTax: totalTax ?? "",
                            totalShippingTax: totalShippingTax ?? "",
                            ratePercent: ratePercent,
                            attributes: taxAttributes)
    }
}
