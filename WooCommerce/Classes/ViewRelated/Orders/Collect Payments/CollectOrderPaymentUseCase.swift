import Foundation
import Combine
import Yosemite
import MessageUI
import protocol Storage.StorageManagerType

/// Protocol to abstract the `CollectOrderPaymentUseCase`.
/// Currently only used to facilitate unit tests.
///
protocol CollectOrderPaymentProtocol {
    /// Starts the collect payment flow.
    ///
    ///
    /// - Parameter backButtonTitle: Title for the back button after a payment is successful.
    /// - Parameter onCollect: Closure Invoked after the collect process has finished.
    /// - Parameter onCompleted: Closure Invoked after the flow has been totally completed.
    func collectPayment(backButtonTitle: String, onCollect: @escaping (Result<Void, Error>) -> (), onCompleted: @escaping () -> ())
}

/// Use case to collect payments from an order.
/// Orchestrates reader connection, payment, UI alerts, receipt handling and analytics.
///
final class CollectOrderPaymentUseCase: NSObject, CollectOrderPaymentProtocol {
    /// Currency Formatter
    ///
    private let currencyFormatter = CurrencyFormatter(currencySettings: ServiceLocator.currencySettings)

    /// Store's ID.
    ///
    private let siteID: Int64

    /// Order to collect.
    ///
    private let order: Order

    /// Order total in decimal number. It is lazy so we avoid multiple conversions.
    /// It can be lazy because the order is a constant and never changes (this class is intended to be
    /// fired and disposed, not reused for multiple payment flows).
    ///
    private lazy var orderTotal: NSDecimalNumber? = {
        currencyFormatter.convertToDecimal(from: order.total)
    }()

    /// Formatted amount to collect.
    ///
    private let formattedAmount: String

    /// Payment Gateway Account to use.
    ///
    private let paymentGatewayAccount: PaymentGatewayAccount

    /// Stores manager.
    ///
    private let stores: StoresManager

    /// Analytics manager,
    ///
    private let analytics: Analytics

    /// View Controller used to present alerts.
    ///
    private var rootViewController: UIViewController

    /// Stores the card reader listener subscription while trying to connect to one.
    ///
    private var readerSubscription: AnyCancellable?

    /// Stores the connected card reader for analytics.
    private var connectedReader: CardReader?

    /// Closure to inform when the full flow has been completed, after receipt management.
    /// Needed to be saved as an instance variable because it needs to be referenced from the `MailComposer` delegate.
    ///
    private var onCompleted: (() -> ())?

    /// Alert manager to inform merchants about reader & card actions.
    ///
    private let alerts: OrderDetailsPaymentAlertsProtocol

    /// IPP Configuration.
    ///
    private let configuration: CardPresentPaymentsConfiguration

    /// IPP payments collector.
    ///
    private lazy var paymentOrchestrator = PaymentCaptureOrchestrator(stores: stores)

    /// Controller to connect a card reader.
    ///
    private lazy var connectionController = {
        CardReaderConnectionController(forSiteID: siteID,
                                       knownReaderProvider: CardReaderSettingsKnownReaderStorage(),
                                       alertsProvider: CardReaderSettingsAlerts(),
                                       configuration: configuration,
                                       analyticsTracker: CardReaderConnectionAnalyticsTracker(configuration: configuration,
                                                                                              stores: stores,
                                                                                              analytics: analytics))
    }()

    init(siteID: Int64,
         order: Order,
         formattedAmount: String,
         paymentGatewayAccount: PaymentGatewayAccount,
         rootViewController: UIViewController,
         alerts: OrderDetailsPaymentAlertsProtocol,
         configuration: CardPresentPaymentsConfiguration,
         stores: StoresManager = ServiceLocator.stores,
         analytics: Analytics = ServiceLocator.analytics) {
        self.siteID = siteID
        self.order = order
        self.formattedAmount = formattedAmount
        self.paymentGatewayAccount = paymentGatewayAccount
        self.rootViewController = rootViewController
        self.alerts = alerts
        self.configuration = configuration
        self.stores = stores
        self.analytics = analytics
    }

    /// Starts the collect payment flow.
    /// 1. Connects to a reader
    /// 2. Collect payment from order
    /// 3. If successful: prints or emails receipt
    /// 4. If failure: Allows retry
    ///
    ///
    /// - Parameter backButtonTitle: Title for the back button after a payment is successful.
    /// - Parameter onCollect: Closure Invoked after the collect process has finished.
    /// - Parameter onCompleted: Closure Invoked after the flow has been totally completed, Currently after merchant has handled the receipt.
    func collectPayment(backButtonTitle: String, onCollect: @escaping (Result<Void, Error>) -> (), onCompleted: @escaping () -> ()) {
        guard isTotalAmountValid() else {
            let error = totalAmountInvalidError()
            onCollect(.failure(error))
            return handleTotalAmountInvalidError(totalAmountInvalidError(), onCompleted: onCompleted)
        }

        configureBackend()
        observeConnectedReadersForAnalytics()
        connectReader { [weak self] result in
            guard let self = self else { return }
            switch result {
            case .success:
                self.attemptPayment(onCompletion: { [weak self] result in
                    // Inform about the collect payment state
                    onCollect(result.map { _ in () }) // Transforms Result<CardPresentReceiptParameters, Error> to Result<Void, Error>

                    // Handle payment receipt
                    guard let paymentData = try? result.get() else {
                        return onCompleted()
                    }
                    self?.presentReceiptAlert(receiptParameters: paymentData.receiptParameters, backButtonTitle: backButtonTitle, onCompleted: onCompleted)
                })
            case .failure:
                onCompleted()
            }
        }
    }
}

// MARK: Private functions
private extension CollectOrderPaymentUseCase {
    /// Checks whether the amount to be collected is valid: (not nil, convertible to decimal, higher than minimum amount ...)
    ///
    func isTotalAmountValid() -> Bool {
        guard let orderTotal = orderTotal else {
            return false
        }

        /// Bail out if the order amount is below the minimum allowed:
        /// https://stripe.com/docs/currencies#minimum-and-maximum-charge-amounts
        return orderTotal as Decimal >= configuration.minimumAllowedChargeAmount as Decimal
    }

    /// Determines and returns the error that provoked the amount being invalid
    ///
    func totalAmountInvalidError() -> Error {
        let orderTotalAmountCanBeConverted = orderTotal != nil

        guard orderTotalAmountCanBeConverted,
              let minimum = currencyFormatter.formatAmount(configuration.minimumAllowedChargeAmount, with: order.currency) else {
            return NotValidAmountError.other
        }

        return NotValidAmountError.belowMinimumAmount(amount: minimum)
    }

    func handleTotalAmountInvalidError(_ error: Error, onCompleted: @escaping () -> ()) {
        trackPaymentFailure(with: error)
        DDLogError("💳 Error: failed to capture payment for order. Order amount is below minimum or not valid")
        self.alerts.nonRetryableError(from: self.rootViewController, error: totalAmountInvalidError(), dismissCompletion: onCompleted)
    }

    /// Configure the CardPresentPaymentStore to use the appropriate backend
    ///
    func configureBackend() {
        let setAccount = CardPresentPaymentAction.use(paymentGatewayAccount: paymentGatewayAccount)
        stores.dispatch(setAccount)
    }

    /// Attempts to connect to a reader.
    /// Finishes with success immediately if a reader is already connected.
    ///
    func connectReader(onCompletion: @escaping (Result<Void, Error>) -> ()) {
        // `checkCardReaderConnected` action will return a publisher that:
        // - Sends one value if there is no reader connected.
        // - Completes when a reader is connected.
        let readerConnected = CardPresentPaymentAction.checkCardReaderConnected { [weak self] connectPublisher in
            guard let self = self else { return }
            self.readerSubscription = connectPublisher
                .sink(receiveCompletion: { [weak self] _ in
                    guard let self = self else { return }

                    // Dismiss the current connection alert before notifying the completion.
                    // If no presented controller is found(because the reader was already connected), just notify the completion.
                    if let connectionController = self.rootViewController.presentedViewController {
                        connectionController.dismiss(animated: true) {
                            onCompletion(.success(()))
                        }
                    } else {
                        onCompletion(.success(()))
                    }

                    // Nil the subscription since we are done with the connection.
                    self.readerSubscription = nil

                }, receiveValue: { [weak self] _ in
                    guard let self = self else { return }

                    // Attempt reader connection
                    self.connectionController.searchAndConnect(from: self.rootViewController) { [weak self] result in
                        guard let self = self else { return }
                        switch result {
                        case let .success(connectionResult):
                            switch connectionResult {
                            case .canceled:
                                self.readerSubscription = nil
                                onCompletion(.failure(CollectOrderPaymentUseCaseError.cardReaderDisconnected))
                            case .connected:
                                // Connected case will be handled in `receiveCompletion`.
                                break
                            }
                        case .failure(let error):
                            self.readerSubscription = nil
                            onCompletion(.failure(error))
                        }
                    }
                })
        }
        stores.dispatch(readerConnected)
    }

    /// Attempts to collect payment for an order.
    ///
    func attemptPayment(onCompletion: @escaping (Result<CardPresentCapturedPaymentData, Error>) -> ()) {
        guard let orderTotal = orderTotal else {
            onCompletion(.failure(NotValidAmountError.other))

            return
        }

        // Track tapped event
        analytics.track(event: WooAnalyticsEvent.InPersonPayments.collectPaymentTapped(forGatewayID: paymentGatewayAccount.gatewayID,
                                                                                       countryCode: configuration.countryCode,
                                                                                       cardReaderModel: connectedReader?.readerType.model ?? ""))

        // Show reader ready alert
        alerts.readerIsReady(title: Localization.collectPaymentTitle(username: order.billingAddress?.firstName),
                             amount: formattedAmount,
                             onCancel: { [weak self] in
            self?.cancelPayment {
                onCompletion(.failure(CollectOrderPaymentUseCaseError.cancelled))
            }
        })

        // Start collect payment process
        paymentOrchestrator.collectPayment(
            for: order,
            orderTotal: orderTotal,
            paymentGatewayAccount: paymentGatewayAccount,
            paymentMethodTypes: configuration.paymentMethods.map(\.rawValue),
            onWaitingForInput: { [weak self] in
                   // Request card input
                   self?.alerts.tapOrInsertCard(onCancel: { [weak self] in
                       self?.cancelPayment {
                           onCompletion(.failure(CollectOrderPaymentUseCaseError.cancelled))
                       }
                   })

            }, onProcessingMessage: { [weak self] in
                // Waiting message
                self?.alerts.processingPayment()
            }, onDisplayMessage: { [weak self] message in
                // Reader messages. EG: Remove Card
                self?.alerts.displayReaderMessage(message: message)
            }, onProcessingCompletion: { [weak self] intent in
                self?.trackProcessingCompletion(intent: intent)
            }, onCompletion: { [weak self] result in
                switch result {
                case .success(let capturedPaymentData):
                    self?.handleSuccessfulPayment(capturedPaymentData: capturedPaymentData, onCompletion: onCompletion)
                case .failure(let error):
                    self?.handlePaymentFailureAndRetryPayment(error, onCompletion: onCompletion)
                }
            }
        )
    }

    /// Tracks the successful payments
    ///
    func handleSuccessfulPayment(capturedPaymentData: CardPresentCapturedPaymentData,
                                 onCompletion: @escaping (Result<CardPresentCapturedPaymentData, Error>) -> ()) {
        // Record success
        analytics.track(event: WooAnalyticsEvent.InPersonPayments
                            .collectPaymentSuccess(forGatewayID: paymentGatewayAccount.gatewayID,
                                                   countryCode: configuration.countryCode,
                                                   paymentMethod: capturedPaymentData.paymentMethod,
                                                   cardReaderModel: connectedReader?.readerType.model ?? ""))

        // Success Callback
        onCompletion(.success(capturedPaymentData))
    }

    /// Log the failure reason, cancel the current payment and retry it if possible.
    ///
    func handlePaymentFailureAndRetryPayment(_ error: Error, onCompletion: @escaping (Result<CardPresentCapturedPaymentData, Error>) -> ()) {
        DDLogError("Failed to collect payment: \(error.localizedDescription)")

        trackPaymentFailure(with: error)

        // Inform about the error
        alerts.error(error: error,
                     tryAgain: { [weak self] in

            // Cancel current payment
            self?.paymentOrchestrator.cancelPayment { [weak self] result in
                guard let self = self else { return }

                switch result {
                case .success:
                    // Retry payment
                    self.attemptPayment(onCompletion: onCompletion)

                case .failure(let cancelError):
                    // Inform that payment can't be retried.
                    self.alerts.nonRetryableError(from: self.rootViewController, error: cancelError) {
                        onCompletion(.failure(error))
                    }
                }
            }
        }, dismissCompletion: {
            onCompletion(.failure(error))
        })
    }

    private func trackPaymentFailure(with error: Error) {
        // Record error
        analytics.track(event: WooAnalyticsEvent.InPersonPayments.collectPaymentFailed(forGatewayID: paymentGatewayAccount.gatewayID,
                                                                                       error: error,
                                                                                       countryCode: configuration.countryCode,
                                                                                       cardReaderModel: connectedReader?.readerType.model))
    }

    /// Cancels payment and record analytics.
    ///
    func cancelPayment(onCompleted: @escaping () -> ()) {
        paymentOrchestrator.cancelPayment { [weak self, analytics] _ in
            guard let self = self else { return }
            analytics.track(event: WooAnalyticsEvent.InPersonPayments.collectPaymentCanceled(forGatewayID: self.paymentGatewayAccount.gatewayID,
                                                                                             countryCode: self.configuration.countryCode,
                                                                                             cardReaderModel: self.connectedReader?.readerType.model ?? ""))
            onCompleted()
        }
    }

    /// Allow merchants to print or email the payment receipt.
    ///
    func presentReceiptAlert(receiptParameters: CardPresentReceiptParameters, backButtonTitle: String, onCompleted: @escaping () -> ()) {
        // Present receipt alert
        alerts.success(printReceipt: { [order, configuration] in
            // Inform about flow completion.
            onCompleted()

            // Delegate print action
            ReceiptActionCoordinator.printReceipt(for: order, params: receiptParameters, countryCode: configuration.countryCode)

        }, emailReceipt: { [order, analytics, paymentOrchestrator, configuration] in
            // Record button tapped
            analytics.track(event: .InPersonPayments.receiptEmailTapped(countryCode: configuration.countryCode))

            // Request & present email
            paymentOrchestrator.emailReceipt(for: order, params: receiptParameters) { [weak self] emailContent in
                self?.onCompleted = onCompleted // Saved to be able to reference from the `MailComposer` delegate.
                self?.presentEmailForm(content: emailContent)
            }
        }, noReceiptTitle: backButtonTitle,
           noReceiptAction: {
            // Inform about flow completion.
            onCompleted()
        })
    }

    /// Presents the native email client with the provided content.
    ///
    func presentEmailForm(content: String) {
        guard MFMailComposeViewController.canSendMail() else {
            return DDLogError("⛔️ Failed to submit email receipt for order: \(order.orderID). Email is not configured.")
        }

        let mail = MFMailComposeViewController()
        mail.mailComposeDelegate = self

        mail.setSubject(Localization.emailSubject(storeName: stores.sessionManager.defaultSite?.name))
        mail.setMessageBody(content, isHTML: true)

        if let customerEmail = order.billingAddress?.email {
            mail.setToRecipients([customerEmail])
        }

        rootViewController.present(mail, animated: true)
    }
}

// MARK: Analytics
private extension CollectOrderPaymentUseCase {
    func observeConnectedReadersForAnalytics() {
        let action = CardPresentPaymentAction.observeConnectedReaders() { [weak self] readers in
            self?.connectedReader = readers.first
        }
        stores.dispatch(action)
    }

    func trackProcessingCompletion(intent: PaymentIntent) {
        guard let paymentMethod = intent.paymentMethod() else {
            return
        }
        switch paymentMethod {
        case .interacPresent:
            analytics.track(event: .InPersonPayments
                .collectInteracPaymentSuccess(gatewayID: paymentGatewayAccount.gatewayID,
                                              countryCode: configuration.countryCode,
                                              cardReaderModel: connectedReader?.readerType.model ?? ""))
        default:
            return
        }
    }
}

// MARK: MailComposer Delegate
extension CollectOrderPaymentUseCase: MFMailComposeViewControllerDelegate {
    func mailComposeController(_ controller: MFMailComposeViewController, didFinishWith result: MFMailComposeResult, error: Error?) {
        switch result {
        case .cancelled:
            analytics.track(event: .InPersonPayments.receiptEmailCanceled(countryCode: configuration.countryCode))
        case .sent, .saved:
            analytics.track(event: .InPersonPayments.receiptEmailSuccess(countryCode: configuration.countryCode))
        case .failed:
            analytics.track(event: .InPersonPayments
                .receiptEmailFailed(error: error ?? UnknownEmailError(),
                                    countryCode: configuration.countryCode))
        @unknown default:
            assertionFailure("MFMailComposeViewController finished with an unknown result type")
        }

        // Dismiss email controller & inform flow completion.
        controller.dismiss(animated: true) { [weak self] in
            self?.onCompleted?()
            self?.onCompleted = nil
        }
    }
}

// MARK: Definitions
private extension CollectOrderPaymentUseCase {
    /// Mailing a receipt failed but the SDK didn't return a more specific error
    ///
    struct UnknownEmailError: Error {}
    enum CollectOrderPaymentUseCaseError: Error {
        case cardReaderDisconnected
        case cancelled
    }

    enum Localization {
        private static let emailSubjectWithStoreName = NSLocalizedString("Your receipt from %1$@",
                                                                 comment: "Subject of email sent with a card present payment receipt")
        private static let emailSubjectWithoutStoreName = NSLocalizedString("Your receipt",
                                                                    comment: "Subject of email sent with a card present payment receipt")
        static func emailSubject(storeName: String?) -> String {
            guard let storeName = storeName, storeName.isNotEmpty else {
                return emailSubjectWithoutStoreName
            }
            return .localizedStringWithFormat(emailSubjectWithStoreName, storeName)
        }

        private static let collectPaymentWithoutName = NSLocalizedString("Collect payment",
                                                                 comment: "Alert title when starting the collect payment flow without a user name.")
        private static let collectPaymentWithName = NSLocalizedString("Collect payment from %1$@",
                                                                 comment: "Alert title when starting the collect payment flow with a user name.")
        static func collectPaymentTitle(username: String?) -> String {
            guard let username = username, username.isNotEmpty else {
                return collectPaymentWithoutName
            }
            return .localizedStringWithFormat(collectPaymentWithName, username)
        }
    }
}

extension CollectOrderPaymentUseCase {
    enum NotValidAmountError: Error, LocalizedError {
        case belowMinimumAmount(amount: String)
        case other

        var errorDescription: String? {
            switch self {
            case .belowMinimumAmount(let amount):
                return String.localizedStringWithFormat(Localization.belowMinimumAmount, amount)
            case .other:
                return Localization.defaultMessage
            }
        }

        private enum Localization {
            static let defaultMessage = NSLocalizedString(
                "Unable to process payment. Order total amount is not valid.",
                comment: "Error message when the order amount is not valid."
            )

            static let belowMinimumAmount = NSLocalizedString(
                "Unable to process payment. Order total amount is below the minimum amount you can charge, which is %1$@",
                comment: "Error message when the order amount is below the minimum amount allowed."
            )
        }
    }
}
