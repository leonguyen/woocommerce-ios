import XCTest
import TestKit

@testable import WooCommerce
@testable import Yosemite

class EditCustomerNoteViewModelTests: XCTestCase {

    private let order = Order.fake().copy(siteID: 123, orderID: 1234, customerNote: "Original")

    func test_done_button_is_disabled_when_note_content_is_the_same() {
        // Given
        let viewModel = EditCustomerNoteViewModel(order: order)

        // When
        let navigationItem = viewModel.navigationTrailingItem

        // Then
        assertEqual(navigationItem, .done(enabled: false))
    }

    func test_done_button_is_enabled_when_note_content_is_the_different() {
        // Given
        let viewModel = EditCustomerNoteViewModel(order: order)

        // When
        viewModel.newNote = "Edited"

        // Then
        assertEqual(viewModel.navigationTrailingItem, .done(enabled: true))
    }

    func test_view_model_only_updates_customer_note_field() {
        // Given
        let stores = MockStoresManager(sessionManager: .testingInstance)
        let viewModel = EditCustomerNoteViewModel(order: order, stores: stores)
        viewModel.newNote = "Edited"

        // When
        let update: (order: Order, fields: [OrderUpdateField]) = waitFor { promise in
            stores.whenReceivingAction(ofType: OrderAction.self) { action in
                switch action {
                case let .updateOrderOptimistically(_, order, fields, _):
                    promise((order, fields))
                default:
                    XCTFail("Unsupported Action")
                }
            }
            viewModel.updateNote { _ in }
        }

        // Then
        assertEqual(update.order.customerNote, "Edited")
        assertEqual(update.fields, [.customerNote])
    }

    func test_view_model_returns_success_after_updating_order_successfully() {
        // Given
        let stores = MockStoresManager(sessionManager: .testingInstance)
        let viewModel = EditCustomerNoteViewModel(order: order, stores: stores)
        stores.whenReceivingAction(ofType: OrderAction.self) { action in
            switch action {
            case let .updateOrderOptimistically(_, order, _, onCompletion):
                onCompletion(.success(order))
            default:
                XCTFail("Unsupported Action")
            }
        }

        // When
        let obtainedResult = waitFor { promise in
            viewModel.updateNote(onFinish: { success in
                promise(success)
            })
        }

        // Then
        XCTAssertTrue(obtainedResult)
    }

    func test_view_model_returns_no_success_after_order_update_fails() {
        // Given
        let stores = MockStoresManager(sessionManager: .testingInstance)
        let viewModel = EditCustomerNoteViewModel(order: order, stores: stores)
        stores.whenReceivingAction(ofType: OrderAction.self) { action in
            switch action {
            case let .updateOrderOptimistically(_, _, _, onCompletion):
                onCompletion(.failure(NSError(domain: "Error", code: 0, userInfo: nil)))
            default:
                XCTFail("Unsupported Action")
            }
        }

        // When
        let obtainedResult = waitFor { promise in
            viewModel.updateNote(onFinish: { success in
                promise(success)
            })
        }

        // Then
        XCTAssertFalse(obtainedResult)
    }

    func test_view_model_tracks_success_after_updating_note() {
        // Given
        let stores = MockStoresManager(sessionManager: .testingInstance)
        let analyticsProvider = MockAnalyticsProvider()
        let viewModel = EditCustomerNoteViewModel(order: order, stores: stores, analytics: WooAnalytics(analyticsProvider: analyticsProvider))
        stores.whenReceivingAction(ofType: OrderAction.self) { action in
            switch action {
            case let .updateOrderOptimistically(_, order, _, onCompletion):
                onCompletion(.success(order))
            default:
                XCTFail("Unsupported Action")
            }
        }

        // When
        _ = waitFor { promise in
            viewModel.updateNote(onFinish: { _ in
                promise(true)
            })
        }

        // Then
        assertEqual(analyticsProvider.receivedEvents, [WooAnalyticsStat.orderDetailEditFlowCompleted.rawValue])
        assertEqual(analyticsProvider.receivedProperties.first?["subject"] as? String, "customer_note")
    }

    func test_view_model_tracks_failure_after_failing_to_update_note() {
        // Given
        let stores = MockStoresManager(sessionManager: .testingInstance)
        let analyticsProvider = MockAnalyticsProvider()
        let viewModel = EditCustomerNoteViewModel(order: order, stores: stores, analytics: WooAnalytics(analyticsProvider: analyticsProvider))
        stores.whenReceivingAction(ofType: OrderAction.self) { action in
            switch action {
            case let .updateOrderOptimistically(_, _, _, onCompletion):
                onCompletion(.failure(NSError(domain: "Error", code: 0, userInfo: nil)))
            default:
                XCTFail("Unsupported Action")
            }
        }

        // When
        _ = waitFor { promise in
            viewModel.updateNote(onFinish: { _ in
                promise(true)
            })
        }

        // Then
        assertEqual(analyticsProvider.receivedEvents, [WooAnalyticsStat.orderDetailEditFlowFailed.rawValue])
        assertEqual(analyticsProvider.receivedProperties.first?["subject"] as? String, "customer_note")
    }

    func test_view_model_tracks_cancel_flow() {
        // Given
        let stores = MockStoresManager(sessionManager: .testingInstance)
        let analyticsProvider = MockAnalyticsProvider()
        let viewModel = EditCustomerNoteViewModel(order: order, stores: stores, analytics: WooAnalytics(analyticsProvider: analyticsProvider))

        // When
        viewModel.userDidCancelFlow()

        // Then
        assertEqual(analyticsProvider.receivedEvents, [WooAnalyticsStat.orderDetailEditFlowCanceled.rawValue])
        assertEqual(analyticsProvider.receivedProperties.first?["subject"] as? String, "customer_note")
    }
}
