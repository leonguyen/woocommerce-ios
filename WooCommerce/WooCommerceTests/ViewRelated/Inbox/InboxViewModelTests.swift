import Combine
import protocol Storage.StorageManagerType
import protocol Storage.StorageType
import XCTest
import Yosemite
@testable import WooCommerce

final class InboxViewModelTests: XCTestCase {
    private let sampleSiteID: Int64 = 322
    private var subscriptions: [AnyCancellable] = []

    /// Mock Storage: InMemory
    private var storageManager: StorageManagerType!

    /// View storage for tests
    private var storage: StorageType {
        storageManager.viewStorage
    }

    override func setUp() {
        super.setUp()
        storageManager = MockStorageManager()
        subscriptions = []
    }

    // MARK: - State transitions

    func test_state_is_empty_without_any_actions() {
        // Given
        let stores = MockStoresManager(sessionManager: .testingInstance)
        var invocationCountOfLoadInboxNotes = 0
        stores.whenReceivingAction(ofType: InboxNotesAction.self) { action in
            guard case .loadAllInboxNotes = action else {
                return
            }
            invocationCountOfLoadInboxNotes += 1
        }
        let viewModel = InboxViewModel(siteID: sampleSiteID, stores: stores)

        // Then
        XCTAssertEqual(viewModel.syncState, .empty)
        XCTAssertEqual(invocationCountOfLoadInboxNotes, 0)
    }

    func test_state_is_syncingFirstPage_and_loadAllInboxNotes_is_dispatched_after_the_first_onLoadTrigger() {
        // Given
        let stores = MockStoresManager(sessionManager: .testingInstance)
        var invocationCountOfLoadInboxNotes = 0
        stores.whenReceivingAction(ofType: InboxNotesAction.self) { action in
            guard case .loadAllInboxNotes = action else {
                return
            }
            invocationCountOfLoadInboxNotes += 1
        }
        let viewModel = InboxViewModel(siteID: sampleSiteID, stores: stores)

        // When
        viewModel.onLoadTrigger.send()
        let stateAfterTheFirstOnLoadTrigger = viewModel.syncState

        viewModel.onLoadTrigger.send()
        let stateAfterTheSecondOnLoadTrigger = viewModel.syncState

        // Then
        XCTAssertEqual(stateAfterTheFirstOnLoadTrigger, .syncingFirstPage)
        XCTAssertEqual(stateAfterTheSecondOnLoadTrigger, .syncingFirstPage)
        XCTAssertEqual(invocationCountOfLoadInboxNotes, 1)
    }

    func test_state_is_results_after_onLoadTrigger_with_nonempty_results() {
        // Given
        let stores = MockStoresManager(sessionManager: .testingInstance)
        var invocationCountOfLoadInboxNotes = 0
        var syncPageNumber: Int?
        let note = InboxNote.fake().copy(siteID: sampleSiteID)
        stores.whenReceivingAction(ofType: InboxNotesAction.self) { action in
            guard case let .loadAllInboxNotes(_, pageNumber, _, _, _, _, completion) = action else {
                return
            }
            invocationCountOfLoadInboxNotes += 1
            syncPageNumber = pageNumber
            self.insertInboxNotes([note])
            completion(.success([note]))
        }
        let viewModel = InboxViewModel(siteID: sampleSiteID, stores: stores, storageManager: storageManager)

        var states = [InboxViewModel.SyncState]()
        viewModel.$syncState.sink { state in
            states.append(state)
        }.store(in: &subscriptions)

        // When
        viewModel.onLoadTrigger.send()

        // Then
        XCTAssertEqual(invocationCountOfLoadInboxNotes, 1)
        XCTAssertEqual(syncPageNumber, 1)
        XCTAssertEqual(states, [.empty, .syncingFirstPage, .results])
    }

    func test_state_is_back_to_empty_after_onLoadTrigger_with_empty_results() {
        // Given
        let stores = MockStoresManager(sessionManager: .testingInstance)
        var invocationCountOfLoadInboxNotes = 0
        var syncPageNumber: Int?
        stores.whenReceivingAction(ofType: InboxNotesAction.self) { action in
            guard case let .loadAllInboxNotes(_, pageNumber, _, _, _, _, completion) = action else {
                return
            }
            invocationCountOfLoadInboxNotes += 1
            syncPageNumber = pageNumber
            completion(.success([]))
        }
        let viewModel = InboxViewModel(siteID: sampleSiteID, stores: stores)

        var states = [InboxViewModel.SyncState]()
        viewModel.$syncState.sink { state in
            states.append(state)
        }.store(in: &subscriptions)

        // When
        viewModel.onLoadTrigger.send()

        // Then
        XCTAssertEqual(invocationCountOfLoadInboxNotes, 1)
        XCTAssertEqual(syncPageNumber, 1)
        XCTAssertEqual(states, [.empty, .syncingFirstPage, .empty])
    }

    func test_it_loads_next_page_after_onLoadTrigger_and_onLoadNextPageAction_until_the_data_size_is_smaller_than_page_size() {
        // Given
        let pageSize: Int = 2

        let stores = MockStoresManager(sessionManager: .testingInstance)
        var invocationCountOfLoadInboxNotes = 0
        var syncPageNumber: Int?
        let firstPageNotes = [InboxNote](repeating: .fake().copy(siteID: sampleSiteID), count: pageSize)
        let secondPageNotes = [InboxNote](repeating: .fake().copy(siteID: sampleSiteID), count: pageSize - 1)
        stores.whenReceivingAction(ofType: InboxNotesAction.self) { action in
            guard case let .loadAllInboxNotes(_, pageNumber, _, _, _, _, completion) = action else {
                return
            }
            invocationCountOfLoadInboxNotes += 1
            syncPageNumber = pageNumber
            let notes = pageNumber == 1 ? firstPageNotes: secondPageNotes
            self.insertInboxNotes(notes)
            completion(.success(notes))
        }

        let viewModel = InboxViewModel(siteID: sampleSiteID, pageSize: pageSize, stores: stores, storageManager: storageManager)

        var states = [InboxViewModel.SyncState]()
        viewModel.$syncState.sink { state in
            states.append(state)
        }.store(in: &subscriptions)

        // When
        viewModel.onLoadTrigger.send() // Syncs `firstPageNotes` with size as page size.
        viewModel.onLoadNextPageAction() // Syncs `secondPageNotes` with size smaller than page size.
        viewModel.onLoadNextPageAction() // No more data to be synced.

        // Then
        XCTAssertEqual(states, [.empty, .syncingFirstPage, .results, .results])
        XCTAssertEqual(invocationCountOfLoadInboxNotes, 2)
        XCTAssertEqual(syncPageNumber, 2)
    }

    // MARK: - Row view models

    func test_noteRowViewModels_match_loaded_notes() {
        // Given
        let stores = MockStoresManager(sessionManager: .testingInstance)
        let note = InboxNote.fake().copy(siteID: sampleSiteID)
        stores.whenReceivingAction(ofType: InboxNotesAction.self) { action in
            guard case let .loadAllInboxNotes(_, _, _, _, _, _, completion) = action else {
                return
            }
            self.insertInboxNotes([note])
            completion(.success([note]))
        }
        let viewModel = InboxViewModel(siteID: sampleSiteID, stores: stores, storageManager: storageManager)

        // When
        viewModel.onLoadTrigger.send()

        // Then
        XCTAssertEqual(viewModel.noteRowViewModels.first, .init(note: note))
    }

    func test_noteRowViewModels_are_empty_when_loaded_notes_are_empty() {
        // Given
        let stores = MockStoresManager(sessionManager: .testingInstance)
        stores.whenReceivingAction(ofType: InboxNotesAction.self) { action in
            guard case let .loadAllInboxNotes(_, _, _, _, _, _, completion) = action else {
                return
            }
            completion(.success([]))
        }
        let viewModel = InboxViewModel(siteID: sampleSiteID, stores: stores)

        // When
        viewModel.onLoadTrigger.send()

        // Then
        XCTAssertEqual(viewModel.noteRowViewModels, [])
    }

    // MARK: - `onRefreshAction`

    func test_onRefreshAction_resyncs_the_first_page() {
        // Given
        let stores = MockStoresManager(sessionManager: .testingInstance)
        var invocationCountOfLoadInboxNotes = 0
        var syncPageNumber: Int?
        stores.whenReceivingAction(ofType: InboxNotesAction.self) { action in
            guard case let .loadAllInboxNotes(_, pageNumber, _, _, _, _, completion) = action else {
                return
            }
            invocationCountOfLoadInboxNotes += 1
            syncPageNumber = pageNumber

            completion(.success([]))
        }
        let viewModel = InboxViewModel(siteID: sampleSiteID, stores: stores)

        // When
        waitFor { promise in
            viewModel.onRefreshAction {
                promise(())
            }
        }

        // Then
        XCTAssertEqual(syncPageNumber, 1)
        XCTAssertEqual(invocationCountOfLoadInboxNotes, 1)
    }
}

extension InboxViewModelTests {
    func insertInboxNotes(_ readOnlyInboxNotes: [InboxNote]) {
        readOnlyInboxNotes.forEach { inboxNote in
            let newInboxNote = storage.insertNewObject(ofType: StorageInboxNote.self)
            newInboxNote.update(with: inboxNote)
        }
        storage.saveIfNeeded()
    }
}
