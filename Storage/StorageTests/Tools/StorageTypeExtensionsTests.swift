import XCTest

@testable import Storage

class StorageTypeExtensionsTests: XCTestCase {

    private var storageManager: StorageManagerType!

    private var storage: StorageType! {
        storageManager.viewStorage
    }

    override func setUp() {
        super.setUp()
        storageManager = CoreDataManager(name: "WooCommerce", crashLogger: MockCrashLogger())
    }

    override func tearDown() {
        storageManager.reset()
        storageManager = nil
        super.tearDown()
    }

    func test_loadAccount_by_ID() throws {
        // Given
        let account = storage.insertNewObject(ofType: Account.self)
        let userID: Int64 = 123
        account.userID = userID

        // When
        let storedAccount = try XCTUnwrap(storage.loadAccount(userID: userID))

        // Then
        XCTAssertEqual(account, storedAccount)

    }
}
