import Storage
import UIKit
import Yosemite

/// Contains UI for Beta features that can be turned on and off.
///
class BetaFeaturesViewController: UIViewController {

    /// Main TableView
    ///
    private lazy var tableView: UITableView = {
        let tableView = UITableView(frame: .zero, style: .grouped)
        return tableView
    }()

    /// Table Sections to be rendered
    ///
    private var sections = [Section]()

    init() {
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Overridden Methods
    //
    override func viewDidLoad() {
        super.viewDidLoad()

        configureNavigationBar()
        configureMainView()
        configureSections()
        configureTableView()
        registerTableViewCells()
    }
}

// MARK: - View Configuration
//
private extension BetaFeaturesViewController {

    /// Set the title.
    ///
    func configureNavigationBar() {
        title = NSLocalizedString("Experimental Features", comment: "Experimental features navigation title")
    }

    /// Apply Woo styles.
    ///
    func configureMainView() {
        view.backgroundColor = .listBackground
    }

    /// Configure common table properties.
    ///
    func configureTableView() {
        view.addSubview(tableView)
        tableView.translatesAutoresizingMaskIntoConstraints = false
        view.pinSubviewToAllEdges(tableView)

        tableView.dataSource = self

        tableView.cellLayoutMarginsFollowReadableWidth = true
        tableView.estimatedRowHeight = Constants.rowHeight
        tableView.rowHeight = UITableView.automaticDimension
        tableView.backgroundColor = .listBackground
    }

    /// Configure sections for table view.
    ///
    func configureSections() {
        self.sections = [
            productsSection()
        ]
    }

    func productsSection() -> Section {
        return Section(rows: [.orderAddOns,
                              .orderAddOnsDescription])
    }

    /// Register table cells.
    ///
    func registerTableViewCells() {
        for row in Row.allCases {
            tableView.registerNib(for: row.type)
        }
    }

    /// Cells currently configured in the order they appear on screen
    ///
    func configure(_ cell: UITableViewCell, for row: Row, at indexPath: IndexPath) {
        guard type(of: cell) == row.type else {
            assertionFailure("The type of cell (\(type(of: cell)) does not match the type (\(row.type)) for row: \(row)")
            return
        }

        switch cell {
        // Product list
        case let cell as SwitchTableViewCell where row == .orderAddOns:
            configureOrderAddOnsSwitch(cell: cell)
        case let cell as BasicTableViewCell where row == .orderAddOnsDescription:
            configureOrderAddOnsDescription(cell: cell)
        default:
            fatalError()
        }
    }

    // MARK: - Product List feature

    func configureOrderAddOnsSwitch(cell: SwitchTableViewCell) {
        configureCommonStylesForSwitchCell(cell)
        cell.title = Localization.orderAddOnsTitle

        let action = AppSettingsAction.loadProductsFeatureSwitch() { isVisible in
            cell.isOn = isVisible
        }
        ServiceLocator.stores.dispatch(action)

        cell.onChange = { isSwitchOn in
            ServiceLocator.analytics.track(.settingsBetaFeaturesProductsToggled)

            let action = AppSettingsAction.setProductsFeatureSwitch(isEnabled: isSwitchOn) {
                //NotificationCenter.default.post(name: .ProductsFeatureSwitchDidChange, object: self)
            }
            ServiceLocator.stores.dispatch(action)
        }
        cell.accessibilityIdentifier = "beta-features-order-add-ons-cell"
    }

    func configureOrderAddOnsDescription(cell: BasicTableViewCell) {
        configureCommonStylesForDescriptionCell(cell)
        cell.textLabel?.text = Localization.orderAddOnsDescription
    }
}

// MARK: - Shared Configurations
//
private extension BetaFeaturesViewController {
    func configureCommonStylesForSwitchCell(_ cell: SwitchTableViewCell) {
        cell.accessoryType = .none
        cell.selectionStyle = .none
    }

    func configureCommonStylesForDescriptionCell(_ cell: BasicTableViewCell) {
        cell.accessoryType = .none
        cell.selectionStyle = .none
        cell.textLabel?.numberOfLines = 0
    }
}


// MARK: - Convenience Methods
//
private extension BetaFeaturesViewController {

    func rowAtIndexPath(_ indexPath: IndexPath) -> Row {
        return sections[indexPath.section].rows[indexPath.row]
    }
}


// MARK: - UITableViewDataSource Conformance
//
extension BetaFeaturesViewController: UITableViewDataSource {

    func numberOfSections(in tableView: UITableView) -> Int {
        return sections.count
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return sections[section].rows.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let row = rowAtIndexPath(indexPath)
        let cell = tableView.dequeueReusableCell(withIdentifier: row.reuseIdentifier, for: indexPath)
        configure(cell, for: row, at: indexPath)

        return cell
    }
}

// MARK: - Private Types
//
private struct Constants {
    static let rowHeight = CGFloat(44)
}

private struct Section {
    let rows: [Row]
}

private enum Row: CaseIterable {
    // Products.
    case orderAddOns
    case orderAddOnsDescription

    var type: UITableViewCell.Type {
        switch self {
        case .orderAddOns:
            return SwitchTableViewCell.self
        case .orderAddOnsDescription:
            return BasicTableViewCell.self
        }
    }

    var reuseIdentifier: String {
        return type.reuseIdentifier
    }
}

private extension BetaFeaturesViewController {
    enum Localization {
        static let orderAddOnsTitle = NSLocalizedString("View Add-Ons", comment: "Cell title on the beta features screen to enable the order add-ons feature")
        static let orderAddOnsDescription = NSLocalizedString("Test out viewing Order Add-Ons as we get ready to launch",
                                                              comment: "Cell description on the beta features screen to enable the order add-ons feature")
    }
}
