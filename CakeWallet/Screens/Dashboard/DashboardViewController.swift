import UIKit
import CakeWalletLib
import CakeWalletCore
import CWMonero
import FlexLayout
import SwiftDate



fileprivate let averageBlocktimeMinutes = 2 as UInt64  //how many minutes per block?
fileprivate let pendingBlocks = 3 as UInt64  //how many blocks will pass (roughly) before a pending transaction is accepted in the blockchain?
fileprivate let blockDelay = 10 as UInt64   //how many blocks are funds locked?
fileprivate let progressBarSyncUpdateTimeThreshold = 900000.nanoseconds.timeInterval

final class DashboardController: BaseViewController<DashboardView>, StoreSubscriber, UITableViewDataSource, UITableViewDelegate, UIScrollViewDelegate, Themed {
    let walletNameView = WalletNameView()
    weak var dashboardFlow: DashboardFlow?
    private var sortedTransactions:  [DateComponents : [TransactionDescription]] = [:] {
        didSet {
            transactionsKeys = sort(dateComponents: Array(sortedTransactions.keys))
        }
    }
    private var transactionsKeys: [DateComponents] = []
    private var initialHeight: UInt64
    private let calendar: Calendar
    private var scrollViewOffset: CGFloat = 0
    let store: Store<ApplicationState>
    private var fingerDown:Bool = false
    private var live_bc_height:UInt64 = 0
    private var lastRefreshedProgressBar:Date? = nil
    
    typealias PartiallyAvailableBalance = (unlocked:Amount, full:Amount)
    typealias CryptoFiatBalance = (crypto:PartiallyAvailableBalance, fiat:PartiallyAvailableBalance)
    private var balances:CryptoFiatBalance {
        return (crypto:(unlocked:store.state.balanceState.unlockedBalance, full:store.state.balanceState.balance), fiat:(unlocked:store.state.balanceState.unlockedFiatBalance, full:store.state.balanceState.fullFiatBalance))
    }
    
    private var configuredBalanceDisplay:BalanceDisplay {
        return store.state.settingsState.displayBalance
    }
    
    private var pendingTransactionSumValues:UInt64 = 0
    private var areTransactionsPending = false
    private var lastTransactionHeight:UInt64? = nil
    private var showingBlockUnlock:Bool = false
    
    init(store: Store<ApplicationState>, dashboardFlow: DashboardFlow?, calendar: Calendar = Calendar.current) {
        self.store = store
        self.dashboardFlow = dashboardFlow
        self.calendar = calendar
        initialHeight = 0
        super.init()
        tabBarItem = UITabBarItem(
            title: title,
            image: UIImage(named: "wallet_icon")?.withRenderingMode(.alwaysTemplate),
            selectedImage: UIImage(named: "wallet_icon")?.withRenderingMode(.alwaysTemplate).withRenderingMode(.alwaysTemplate)
        )
    }
    
    override func configureBinds() {
        super.configureBinds()
        
        let backButton = UIBarButtonItem(title: "", style: .plain, target: self, action: nil)
        navigationItem.backBarButtonItem = backButton  
        
        contentView.transactionsTableView.register(items: [TransactionDescription.self])
        contentView.transactionsTableView.delegate = self
        contentView.transactionsTableView.dataSource = self
        
        let sendButtonTap = UITapGestureRecognizer(target: self, action: #selector(presentSend))
        contentView.sendButton.isUserInteractionEnabled = true
        contentView.sendButton.addGestureRecognizer(sendButtonTap)
        
        let receiveButtonTap = UITapGestureRecognizer(target: self, action: #selector(presentReceive))
        contentView.receiveButton.isUserInteractionEnabled = true
        contentView.receiveButton.addGestureRecognizer(receiveButtonTap)
        
        let progressTap = UITapGestureRecognizer(target:self, action: #selector(refresh(_:)))
        contentView.progressBar.isUserInteractionEnabled = true
        contentView.progressBar.addGestureRecognizer(progressTap)
        contentView.fixedHeader.isUserInteractionEnabled = true
        
        insertNavigationItems()
    }

    private func areTouchesValid(_ touches:Set<UITouch>, forEvent thisEvent:UIEvent?) -> Bool {
        let touchPointsRec = touches.map { return $0.location(in:contentView.receiveButton) }
        let touchPointsSnd = touches.map { return $0.location(in:contentView.sendButton) }
        let touchPointsProg = touches.map { return $0.location(in:contentView.progressBar.progressView) }
        let insideRec = touchPointsRec.map { return contentView.receiveButton.point(inside: $0, with: thisEvent) }
        let insideSnd = touchPointsSnd.map { return contentView.sendButton.point(inside: $0, with: thisEvent) }
        let insideProg = touchPointsProg.map { return contentView.progressBar.progressView.point(inside: $0, with: thisEvent) }
        if (insideRec.contains(true) || insideSnd.contains(true) || insideProg.contains(true)) {
            return false
        } else {
            return true
        }
    }
    
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        if (fingerDown == false && areTouchesValid(touches, forEvent:event) == true) {
            Vibration.heavy.vibrate()
            fingerDown = true
            updateBalances()
        }
    }
    
    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        if (fingerDown == true) {
            Vibration.light.vibrate()
            fingerDown = false
            updateBalances()
        }
    }
    
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        if (fingerDown == true) {
            Vibration.light.vibrate()
            fingerDown = false
            updateBalances()
        }
    }
    
    private func insertNavigationItems() {
        navigationItem.leftBarButtonItem = UIBarButtonItem(image: UIImage(named: "more")?.resized(to: CGSize(width: 28, height: 28)), style: .plain, target: self, action: #selector(presentWalletActions))
        navigationItem.leftBarButtonItem?.tintColor = UserInterfaceTheme.current.text
        navigationItem.titleView = walletNameView
        navigationItem.titleView?.tintColor = UserInterfaceTheme.current.text
        
        walletNameView.titleLabel.textColor = UserInterfaceTheme.current.text
        walletNameView.subtitleLabel.textColor = UserInterfaceTheme.current.textVariants.highlight
    }
    
    func themeChanged() {
        walletNameView.titleLabel.textColor = UserInterfaceTheme.current.text
        walletNameView.subtitleLabel.textColor = UserInterfaceTheme.current.textVariants.highlight
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        store.subscribe(self)
        updateBalances()
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        store.unsubscribe(self)
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        contentView.scrollView.delegate = self
    }
    
    override func setTitle() {
        title = NSLocalizedString("wallet", comment: "")
    }
    
    func onStateChange(_ state: ApplicationState) {
        updateStatus(state.blockchainState.connectionStatus)
        updateBalances()
        onWalletChange(state.walletState, state.blockchainState)
        updateTransactions(state.transactionsState.transactions)
        updateInitialHeight(state.blockchainState)
        if (state.blockchainState.blockchainHeight > live_bc_height) {
            live_bc_height = state.blockchainState.blockchainHeight
            contentView.progressBar.lastBlockDate = Date()
        } else if (state.blockchainState.currentHeight > live_bc_height) {
            live_bc_height = state.blockchainState.currentHeight
        }
        updateBlocksToUnlock()
        walletNameView.title = state.walletState.name
        walletNameView.subtitle = state.walletState.account.label
    }
    
    func numberOfSections(in tableView: UITableView) -> Int {
        return sortedTransactions.count
    }
    
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        let key = transactionsKeys[section]
        return sortedTransactions[key]?.count ?? 0
    }
    
    func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
        return DashboardView.tableSectionHeaderHeight
    }
    
    func tableView(_ tableView: UITableView, viewForFooterInSection section: Int) -> UIView? {
        return nil
    }
    
    func tableView(_ tableView: UITableView, heightForFooterInSection section: Int) -> CGFloat {
        return CGFloat.leastNormalMagnitude
    }
    
    func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
        let key = transactionsKeys[section]
        let dateFormatter = DateFormatter()
        let label = UILabel(frame: CGRect(origin: .zero, size: CGSize(width: tableView.frame.size.width, height: DashboardView.tableSectionHeaderHeight)))
        let date = NSCalendar.current.date(from: key)!
        label.textColor = UserInterfaceTheme.current.textVariants.main
        label.font = applyFont(ofSize: 14, weight: .semibold)
        label.textAlignment = .center
        
        if Calendar.current.isDateInToday(date) {
            label.text = "Today"
        } else if Calendar.current.isDateInYesterday(date) {
            label.text = "Yesterday"
        } else {
            let now = Date()
            let currentYear = Calendar.current.component(.year, from: now)
            dateFormatter.dateFormat = key.year == currentYear ? "dd MMMM" : "dd MMMM yyyy"
            label.text = dateFormatter.string(from: date)
        }
        
        return label
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        guard let transaction = getTransaction(by: indexPath) else {
            return UITableViewCell()
        }
        
        let cell = tableView.dequeueReusableCell(withItem: transaction, for: indexPath)
        
        if let transactionUITableViewCell = cell as? TransactionUITableViewCell {
            transactionUITableViewCell.addSeparator()
        }
        
        return cell
    }
    
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: false)
        
        if let transaction = getTransaction(by: indexPath) {
            presentTransactionDetails(for: transaction)
        }
    }
    
    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        return TransactionUITableViewCell.height
    }
    
    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        animateFixedHeader(for: scrollView)
        updateBalances()
    }
    
    private func animateFixedHeader(for scrollView: UIScrollView) {
        let currentOffset = scrollView.contentOffset.y
        
        if currentOffset > 60 {
            hideContentAnimation(toValue: 0.0)
        } else {
            hideContentAnimation(toValue: 1.0)
        }

        scrollViewOffset = currentOffset
        let estimatedDashboardHeightToSet = DashboardView.fixedHeaderHeight - currentOffset + 25
        let dashboardHeightToSet = estimatedDashboardHeightToSet >= DashboardView.headerMinHeight ? estimatedDashboardHeightToSet : DashboardView.headerMinHeight
        let estimatedButtonsHeight =  80 - currentOffset * 0.15
        let estimatedOffsetTop = 70 - currentOffset
        let offsetTop: CGFloat
        let buttonsHeight: CGFloat
        
        if estimatedButtonsHeight > DashboardView.headerButtonsHeight {
            buttonsHeight = DashboardView.headerButtonsHeight
        } else if estimatedButtonsHeight < DashboardView.minHeaderButtonsHeight {
            buttonsHeight = DashboardView.minHeaderButtonsHeight
        } else {
            buttonsHeight = estimatedButtonsHeight
        }
        
        if estimatedOffsetTop > DashboardView.fixedHeaderTopOffset {
            offsetTop = DashboardView.fixedHeaderTopOffset
        } else if estimatedOffsetTop < 0 {
            offsetTop = 0
        } else {
            offsetTop = estimatedOffsetTop
        }

        if contentView.buttonsRow.frame.size.height != buttonsHeight {
            contentView.buttonsRow.flex.height(buttonsHeight).markDirty()
            let buttonHeight = contentView.sendButton.buttonImageView.frame.size.height
            
            if buttonHeight != 0 {
                let imageTop: CGFloat = (buttonsHeight / 2) - (buttonHeight / 2)
                contentView.sendButton.buttonImageView.flex.top(imageTop).markDirty()
                contentView.receiveButton.buttonImageView.flex.top(imageTop).markDirty()
            }
        }
        
        if contentView.fixedHeader.frame.size.height != dashboardHeightToSet {
            contentView.fixedHeader.flex.height(dashboardHeightToSet).markDirty()
        }
        
        if contentView.cardViewCoreDataWrapper.frame.origin.y != offsetTop {
            contentView.cardViewCoreDataWrapper.flex.marginTop(offsetTop).markDirty()
        }
        
        contentView.fixedHeader.flex.layout()
        
        guard scrollView.contentOffset.y > contentView.fixedHeader.frame.height else {
            updateBalances()
            return
        }
    }
    
    private func hideContentAnimation(toValue value: CGFloat) {
        UIViewPropertyAnimator(duration: 0.15, curve: .easeOut, animations: { [weak self] in
            self?.contentView.progressBar.alpha = value
            self?.contentView.cryptoTitleLabel.alpha = value
        }).startAnimation()
    }
    
    @objc
    private func presentWalletActions() {
        let alertViewController = UIAlertController(title: nil, message: nil, preferredStyle: .actionSheet)
        let cancelAction = UIAlertAction(title: NSLocalizedString("cancel", comment: ""), style: .cancel)
        
        let presentReconnectAction = UIAlertAction(title: NSLocalizedString("reconnect", comment: ""), style: .default) { [weak self] _ in
            self?.reconnectAction()
        }
        
        let showSeedAction = UIAlertAction(title: NSLocalizedString("show_seed", comment: ""), style: .default) { [weak self] _ in
            guard
                let walletName = self?.store.state.walletState.name,
                let walletType = self?.store.state.walletState.walletType else {
                    return
            }
            
            let index = WalletIndex(name: walletName, type: walletType)
            self?.showSeedAction(for: index)
        }
        
        let showKeysAction = UIAlertAction(title: NSLocalizedString("show_keys", comment: ""), style: .default) { [weak self] _ in
            self?.showKeysAction()
        }
        
        let presentAccountsAction = UIAlertAction(title: NSLocalizedString("accounts", comment: ""), style: .default) { [weak self] _ in
            self?.dashboardFlow?.change(route: .accounts)
        }
        
        let presentWalletsListAction = UIAlertAction(title: NSLocalizedString("wallets", comment: ""), style: .default) { [weak self] _ in
            self?.presentWalletsList()
        }
        
        let presentAddressBookAction = UIAlertAction(title: NSLocalizedString("address_book", comment: ""), style: .default) { [weak self] _ in
            self?.dashboardFlow?.change(route: .addressBook)
        }
    
        alertViewController.addAction(presentReconnectAction)
        alertViewController.addAction(presentAccountsAction)
        alertViewController.addAction(presentWalletsListAction)
        alertViewController.addAction(showSeedAction)
        alertViewController.addAction(showKeysAction)
        alertViewController.addAction(presentAddressBookAction)
        alertViewController.addAction(cancelAction)
        DispatchQueue.main.async {
            self.present(alertViewController, animated: true)
        }
    }
    
    private func getTransaction(by indexPath: IndexPath) -> TransactionDescription? {
        let key = transactionsKeys[indexPath.section]
        return sortedTransactions[key]?[indexPath.row]
    }

    private func onWalletChange(_ walletState: WalletState, _ blockchainState: BlockchainState) {
        initialHeight = 0
        updateTitle(walletState.name)
    }
    
    private func showSeedAction(for wallet: WalletIndex) {
        let authController = AuthenticationViewController(store: store, authentication: AuthenticationImpl())
        let navController = UINavigationController(rootViewController: authController)
        
        authController.onDismissHandler = onDismissHandler
        authController.handler = { [weak authController, weak self] in
            do {
                let gateway = MoneroWalletGateway()
                let walletURL = gateway.makeConfigURL(for: wallet.name)
                let walletConfig = try WalletConfig.load(from: walletURL)
                let seed = try gateway.fetchSeed(for: wallet)
                
                authController?.dismiss(animated: true) {
                    self?.dashboardFlow?.change(route: .showSeed(wallet: wallet.name, date: walletConfig.date, seed: seed))
                }
                
            } catch {
                print(error)
                self?.showErrorAlert(error: error)
            }
        }
        
        present(navController, animated: true)
    }
    
    
    private func showKeysAction() {
        let authController = AuthenticationViewController(store: store, authentication: AuthenticationImpl())
        let navController = UINavigationController(rootViewController: authController)
        authController.onDismissHandler = onDismissHandler
        authController.handler = { [weak authController, weak self] in
            authController?.dismiss(animated: true) {
                self?.dashboardFlow?.change(route: .showKeys)
            }
        }
        
        present(navController, animated: true)
    }
    
    private func reconnectAction() {
        let alertController = UIAlertController(
            title: NSLocalizedString("reconnection", comment: ""),
            message: NSLocalizedString("reconnect_alert_text", comment: ""),
            preferredStyle: .alert
        )
        
        alertController.addAction(UIAlertAction(
            title: NSLocalizedString("reconnect", comment: ""),
            style: .default,
            handler: { [weak self, weak alertController] _ in
                self?.store.dispatch(WalletActions.reconnect)
                alertController?.dismiss(animated: true)
            }
        ))
        
        alertController.addAction(UIAlertAction(
            title: NSLocalizedString("cancel", comment: ""),
            style: .cancel,
            handler: nil
        ))
        
        present(alertController, animated: true, completion: nil)
    }
    
    private func observePullAction(for offset: CGFloat) {
        guard offset < -40 else {
            return
        }
        
        store.dispatch(TransactionsActions.askToUpdate)
    }
    
    private func updateInitialHeight(_ blockchainState: BlockchainState) {
        guard initialHeight == 0 else {
            return
        }
        
        if case let .syncing(height) = blockchainState.connectionStatus {
            initialHeight = height
        }
    }
    
    @objc
    private func presentWalletsList() {
        dashboardFlow?.change(route: .wallets)
    }
    
    @objc
    private func presentReceive() {
        dashboardFlow?.change(route: .receive)
    }
    
    @objc
    private func presentSend() {
        dashboardFlow?.change(route: .send)
    }
    
    private func presentTransactionDetails(for tx: TransactionDescription) {
        let transactionDetailsViewController = TransactionDetailsViewController(transactionDescription: tx)
        let nav = UINavigationController(rootViewController: transactionDetailsViewController)
        
        let exchangeFlow = ExchangeFlow(navigationController: nav)
        transactionDetailsViewController.exchangeFlow = exchangeFlow
        
        tabBarController?.present(nav, animated: true)
    }
    
    private func updateSyncing(_ currentHeight: UInt64, blockchainHeight: UInt64) {
        if blockchainHeight < currentHeight || blockchainHeight == 0 {
            store.dispatch(BlockchainActions.fetchBlockchainHeight)
        } else {
            let track = blockchainHeight - initialHeight
            let _currentHeight = currentHeight > initialHeight ? currentHeight - initialHeight : 0
            let remaining = blockchainHeight - currentHeight
            guard currentHeight != 0 && track != 0 else { return }

            //this basic time-based logic will ensure the blocks remaining are only redrawn a certain number per second. this reduces cpu load and actually results in faster visual refresh of the progress bar
            if (lastRefreshedProgressBar == nil || lastRefreshedProgressBar!.compareCloseTo(Date(), precision: progressBarSyncUpdateTimeThreshold) == false) {
                lastRefreshedProgressBar = Date()
                contentView.progressBar.configuration = .inProgress(NSLocalizedString("syncronizing", comment: ""), NSLocalizedString("blocks_remaining", comment: ""), (remaining:remaining, track:blockchainHeight))
            }
        }
    }
    
    private func updateStatus(_ connectionStatus: ConnectionStatus) {
        switch connectionStatus {
        case let .syncing(currentHeight):
            updateSyncing(currentHeight, blockchainHeight: store.state.blockchainState.blockchainHeight)
        case .connection:
            updateStatusConnection()
        case .notConnected:
            updateStatusNotConnected()
        case .startingSync:
            updateStatusstartingSync()
        case .synced:
            updateStatusSynced()
        case .failed:
            updateStatusFailed()
        }
    }
    
    private func updateStatusConnection() {
        contentView.progressBar.configuration = .indeterminantMessage(NSLocalizedString("connecting", comment: ""))
    }
    
    private func updateStatusNotConnected() {
        contentView.progressBar.configuration = .error(NSLocalizedString("not_connected", comment: ""))
    }
    
    private func updateStatusstartingSync() {
        contentView.progressBar.configuration = .indeterminantSync(NSLocalizedString("starting_sync", comment: ""))
    }
    
    private func updateStatusSynced() {
        contentView.progressBar.configuration = .syncronized(NSLocalizedString("synchronized", comment: ""), NSLocalizedString("last_block_received", comment:""))
    }
    
    private func updateStatusFailed() {
        contentView.progressBar.configuration = .error(NSLocalizedString("failed_connection_to_node", comment: ""))
    }
    
    private func updateBalances() {
        self.render(balances:balances, displaySettings: (fingerDown == true) ? ((configuredBalanceDisplay == .full) ? BalanceDisplay.unlocked : BalanceDisplay.full) : configuredBalanceDisplay)
    }
    
    private func updateBlocksToUnlock() {
        func hideIt() {
            contentView.blockUnlockLabel.isHidden = true
            showingBlockUnlock = false
            print("hideit")
        }
        func showIt() {
            contentView.blockUnlockLabel.isHidden = false
            showingBlockUnlock = true
            print("showit")
        }

        print("updating blocks to unlock")
        guard balances.crypto.full.value > 0 else {
            hideIt()
            print("hidden due to no balance")
            return
        }
        
        if (balances.crypto.full.value != balances.crypto.unlocked.value || areTransactionsPending == true) {
            guard
                live_bc_height != 0,
                let lastTxHeight = lastTransactionHeight else {
                print("no valid data pertaining to last unlocked block.")
                hideIt()
                    return
            }
            
            if (areTransactionsPending == true) {
                print("pending mode")
                contentView.blockUnlockLabel.text = (blockDelay + pendingBlocks).asLocalizedUnlockString()
                showIt()
            } else if (lastTxHeight <= live_bc_height && (live_bc_height - lastTxHeight) <= blockDelay) {
                print("progress mode")
                contentView.blockUnlockLabel.text = (blockDelay - (live_bc_height - lastTxHeight)).asLocalizedUnlockString()
                showIt()
            } else if (balances.crypto.full.value != balances.crypto.unlocked.value) {
                print("About to dissapear mode")
                contentView.blockUnlockLabel.text = (1 as UInt64).asLocalizedUnlockString()
                showIt()
            }
        } else if (balances.crypto.full.value == balances.crypto.unlocked.value) {
            hideIt()
        }
        
        contentView.blockUnlockLabel.sizeToFit()
        contentView.setNeedsLayout()
        contentView.blockUnlockLabel.flex.markDirty()
    }
    
    private func render(balances:CryptoFiatBalance, displaySettings:BalanceDisplay) {
        //adjust the content based on the display settings
        switch displaySettings {
        case .full:
            contentView.cryptoTitleLabel.text = "XMR " + displaySettings.localizedString()
            contentView.fiatAmountLabel.text = balances.fiat.full.formatted()
            contentView.cryptoAmountLabel.text = balances.crypto.full.formatted()
            contentView.cryptoTitleLabel.textColor = UserInterfaceTheme.current.blue.highlight
        case .unlocked:
            contentView.cryptoTitleLabel.text = "XMR " + displaySettings.localizedString()
            contentView.fiatAmountLabel.text = balances.fiat.unlocked.formatted()
            contentView.cryptoAmountLabel.text = balances.crypto.unlocked.formatted()
            contentView.cryptoTitleLabel.textColor = UserInterfaceTheme.current.purple.highlight
        case .hidden:
            contentView.cryptoTitleLabel.text = "XMR " + displaySettings.localizedString()
            contentView.cryptoAmountLabel.text = "--"
            contentView.fiatAmountLabel.text = "-"
            contentView.cryptoTitleLabel.textColor = UserInterfaceTheme.current.textVariants.main
        }

        contentView.cryptoAmountLabel.sizeToFit()
        contentView.cryptoTitleLabel.sizeToFit()
        contentView.fiatAmountLabel.sizeToFit()
        
        contentView.setNeedsLayout()
        
        contentView.fiatAmountLabel.flex.markDirty()
        contentView.cryptoAmountLabel.flex.markDirty()
        contentView.cryptoTitleLabel.flex.markDirty()
    }
    
    private func updateTransactions(_ transactions: [TransactionDescription]) {

        contentView.transactionTitleLabel.isHidden = transactions.count <= 0
        
        let sortedTransactions = Dictionary(grouping: transactions) {
            return calendar.dateComponents([.day, .year, .month], from: ($0.date))
        }
        self.sortedTransactions = sortedTransactions
        
        var pendingValues = 0 as UInt64
        let doesHavePending = transactions.contains(where: { transaction in
            if (transaction.isPending) {
                pendingValues += transaction.totalAmount.value
                return true
            } else {
                return false
            }
        })
        areTransactionsPending = doesHavePending
        
        let heightSortedTransactions = transactions.sorted { t1, t2 in
            return t1.height > t2.height
        }
        
        if (areTransactionsPending == true || sortedTransactions.count > 0) {
            lastTransactionHeight = heightSortedTransactions[0].height
            updateBlocksToUnlock()
            if contentView.transactionTitleLabel.isHidden {
                contentView.transactionTitleLabel.isHidden = false
            }
        } else if !contentView.transactionTitleLabel.isHidden {
            contentView.transactionTitleLabel.isHidden = true
        }
        
        contentView.transactionsTableView.reloadData()
        let height = calculateTableHeight()
        contentView.transactionsTableView.flex.height(height).markDirty()
        contentView.rootFlexContainer.flex.layout(mode: .adjustHeight)
        contentView.setNeedsLayout()
    }
    
    private func calculateTableHeight() -> CGFloat {
        let height = sortedTransactions.reduce(DashboardView.tableSectionHeaderHeight) { (result, keyVal) -> CGFloat in
            return result + DashboardView.tableSectionHeaderHeight + (CGFloat(keyVal.1.count) * TransactionUITableViewCell.height)
        }
        
        return height
    }
    
    private func updateTitle(_ title: String) {
        if navigationItem.leftBarButtonItem?.title != title {
            navigationItem.leftBarButtonItem?.title = title
        }
    }

    @objc
    private func toAddressBookAction() {
        dashboardFlow?.change(route: .addressBook)
    }
    
    @objc
    private func refresh(_ refCont: UIRefreshControl) {
        store.dispatch(TransactionsActions.askToUpdate)
        Vibration.success.vibrate()
    }
}

fileprivate extension UInt64 {
    func asLocalizedUnlockString(asTime:Bool = true) -> String {
        if (asTime) {
            return String(self*averageBlocktimeMinutes) + " " + NSLocalizedString("minutes_to_unlock", comment:"")
        } else {
            return String(self) + " " + NSLocalizedString("blocks_to_unlock", comment:"")
        }
    }
}
