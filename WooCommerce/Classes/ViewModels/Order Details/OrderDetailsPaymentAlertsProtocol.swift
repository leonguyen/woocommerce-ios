import UIKit

/// Protocol for `OrderDetailsPaymentAlerts` to enable unit testing.
protocol OrderDetailsPaymentAlertsProtocol {
    func presentViewModel(viewModel: CardPresentPaymentsModalViewModel)

    func readerIsReady(title: String, amount: String, onCancel: @escaping () -> Void)

    func tapOrInsertCard(onCancel: @escaping () -> Void)

    func displayReaderMessage(message: String)

    func processingPayment()

    func success(printReceipt: @escaping () -> Void, emailReceipt: @escaping () -> Void, noReceiptTitle: String, noReceiptAction: @escaping () -> Void)

    func error(error: Error, tryAgain: @escaping () -> Void, dismissError: @escaping (_ viewController: UIViewController?) -> Void)

    func nonRetryableError(from: UIViewController?, error: Error)

    func retryableError(from: UIViewController?, tryAgain: @escaping () -> Void)
}
