import UIKit
import Alamofire
import SwiftyJSON
import CWMonero
import CakeWalletLib
import RxSwift
import RxBiBinding
import RxCocoa

final class TradeDetailsViewController: BaseViewController<TransactionDetailsView>, UITableViewDataSource, UITableViewDelegate {
    private(set) var items: [TradeDetailsCellItem] = []
    private let trade: TradeInfo
    private var tradeDetails: BehaviorRelay<Trade?>
    private lazy var updateTradeStateTimer: Timer = {
        return Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [weak self] timer in
            self?.updateTradeDetails()
        }
    }()
    
    private let disposeBag: DisposeBag
    
    init(trade: TradeInfo) {
        self.trade = trade
        tradeDetails = BehaviorRelay(value: nil)
        disposeBag = DisposeBag()
        super.init()
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        updateTradeDetails()
        setRows(trade: trade)
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        fetchTradeDetails()
    }
    
    override func configureBinds() {
        super.configureBinds()
        title = "Trade details"
        let backButton = UIBarButtonItem(title: "", style: .plain, target: self, action: nil)
        navigationItem.backBarButtonItem = backButton
        
        contentView.table.dataSource = self
        contentView.table.delegate = self
        contentView.table.register(items: [TradeDetailsCellItem.self])
        
        updateTradeStateTimer.fire()
        
        let tradeObserver = tradeDetails.asObservable()
        tradeObserver.map({ [weak self] trade -> [TradeDetailsCellItem] in
            guard let this = self, let trade = trade else { return [] }
            
            return this.items.map{ item -> TradeDetailsCellItem in
                if item.row == .state {
                    return TradeDetailsCellItem(row: .state, value: trade.state.formatted())
                }
                
                return item
            }
        }).subscribe(onNext: { [weak self] items in
            self?.items = items
            self?.contentView.table.reloadData()
        }).disposed(by: disposeBag)
    }
    
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return items.count
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let item = items[indexPath.row]
        return tableView.dequeueReusableCell(withItem: item, for: indexPath)
    }
    
    private func setRows(trade: TradeInfo) {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "MMM d, yyyy HH:mm"
        let formattedDate = dateFormatter.string(from: Date(timeIntervalSince1970: trade.date))
        
        items.append(TradeDetailsCellItem(row: .tradeID, value: trade.tradeID))
        
        items.append(TradeDetailsCellItem(row: .date, value: formattedDate))
        
        items.append(TradeDetailsCellItem(row: .exchangeProvider, value: trade.provider))
        
        items.append(TradeDetailsCellItem(row: .state, value: "Fetching..."))
    }
    
    private func fetchTradeDetails() {
        guard let provider = trade.exchangeProvider else {
            return
        }
        
        findTradeByID(id: trade.tradeID, provider: provider)
            .bind(to: tradeDetails)
            .disposed(by: disposeBag)
    }
    
    private func findTradeByID(id: String, provider: ExchangeProvider) -> Observable<Trade> {
        let trade: Observable<Trade>
        
        switch provider {
        case .morph:
            trade = MorphTrade.findBy(id: id)
        case .changenow:
            trade = ChangeNowTrade.findBy(id: id)
        case .xmrto:
            trade = XMRTOTrade.findBy(id: id)
        }
        
        return trade
    }
    
    private func updateTradeDetails() {
        if let val = tradeDetails.value {
            val.update().bind(to: tradeDetails).disposed(by: disposeBag)
        }
    }
    
    @objc
    private func dismissAction() {
        dismiss(animated: true) { [weak self] in
            self?.onDismissHandler?()
        }
    }
}
