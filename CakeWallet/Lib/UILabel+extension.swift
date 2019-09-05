import UIKit

extension UILabel {
    convenience init(font: UIFont = UIFont.systemFont(ofSize: 16)) {
        self.init()
        self.font = font
        self.numberOfLines = 0
        self.textColor = UserInterfaceTheme.current.background
    }
    
    convenience init(fontSize size: CGFloat = 16) {
        self.init()
        self.font = applyFont(ofSize: size)
        self.textColor = UserInterfaceTheme.current.background
    }
    
    convenience init(text: String = "") {
        self.init()
        self.text = text
        self.textColor = UserInterfaceTheme.current.background
    }
    
    static func withLightText(font: UIFont = UIFont.systemFont(ofSize: 16)) -> UILabel {
        let label = UILabel(font: font)
        
        //tstag
        label.textColor = UserInterfaceTheme.current.background
        label.numberOfLines = 0
        return label
    }
    
    static func withLightText(fontSize size: CGFloat = 16) -> UILabel {
        let label = UILabel(fontSize: size)
        label.textColor = UserInterfaceTheme.current.background
        label.font = applyFont(ofSize: size)
        label.numberOfLines = 0
        return label
    }
}
