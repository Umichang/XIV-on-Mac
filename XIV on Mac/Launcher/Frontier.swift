//
//  Frontier.swift
//  XIV on Mac
//
//  Created by Marc-Aurel Zent on 07.02.22.
//

import Cocoa
import OrderedCollections
import SeeURL
import XIVLauncher

class Frontier {
    
    static var squareTime: Int64 {
        Int64((Date().timeIntervalSince1970 * 1000.0).rounded())
    }
    
    private static func generateReferer(lang: FFXIVLanguage) -> URL {
        let dateFormatter = DateFormatter()
        dateFormatter.timeZone = TimeZone(secondsFromGMT: 0)
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        dateFormatter.dateFormat = "yyyy-MM-dd-HH-mm"
        let time = dateFormatter.string(from: Date())
        let rcLang = lang.code.replacingOccurrences(of: "-", with: "_")
        return URL(string: "https://launcher.finalfantasyxiv.com/v620/index.html?rc_lang=\(rcLang)&time=\(time)")!
    }
    
    static var referer: URL {
        generateReferer(lang: Settings.language)
    }
    
    static var refererGlobal: URL {
        generateReferer(lang: FFXIVLanguage.english)
    }
    
    static var headline: URL {
        let lang = Settings.language.code
        return URL(string: "https://frontier.ffxiv.com/news/headline.json?lang=\(lang)&media=pcapp&_=\(squareTime)")!
    }
    
    static func fetch(url: URL, accept: String? = nil, global: Bool = false) -> HTTPClient.Response? {
        let headers: OrderedDictionary = [
            "User-Agent": String(cString: getUserAgent()),
            "Accept": accept,
            "Accept-Encoding": "gzip, deflate",
            "Origin": "https://launcher.finalfantasyxiv.com",
            "Referer": (global ? refererGlobal : referer).absoluteString
        ]
        return HTTPClient.fetch(url: url, headers: headers)
    }
    
    static func fetchImage(url: URL?) -> NSImage? {
        guard let url = url,
            let response = fetch(url: url) else {
            return nil
        }
        return NSImage(data: response.body)
    }
    
    struct Gate: Codable {
        let status: Int
        let message: [String]?
        let news: [String]?
    }
    
    struct Login: Codable {
        let status: Int
    }
    
    static var gameMaintenance: Bool {
        let url = URL(string: "https://frontier.ffxiv.com/worldStatus/gate_status.json?lang=\(Settings.language.code)&_=\(squareTime)")!
        guard let response = fetch(url: url) else {
            return true
        }
        guard response.statusCode == 200 else {
            return true
        }
        let jsonDecoder = JSONDecoder()
        do {
            let gate = try jsonDecoder.decode(Gate.self, from: response.body)
            return gate.status != 1
        } catch {
            return true
        }
    }
    
    static var loginMaintenance: Bool {
        let url = URL(string: "https://frontier.ffxiv.com/worldStatus/login_status.json?_=\(squareTime)")!
        guard let response = fetch(url: url, global: true) else {
            return true
        }
        guard response.statusCode == 200 else {
            return true
        }
        let jsonDecoder = JSONDecoder()
        do {
            let login = try jsonDecoder.decode(Login.self, from: response.body)
            return login.status != 1
        } catch {
            return true
        }
    }
    
    struct Info: Codable {
        struct News: Codable, Identifiable, Hashable {
            let date: String
            let title: String
            let url: String
            let id: String
            let tag: String?
            
            var usableURL : URL? {
                // For news and such, SE doesn't tend to return us the URL directly for... reasons known only to them
                if self.url.count > 0
                {
                    return URL(string: url)
                }
                if self.id.count == 0
                {
                    return nil
                }
                // But if they gave us an ID, the URL can be constructed if you know the appropriate regional Lodestone page
                var seURLBase : URL? = nil
                switch (Settings.language.code)
                {
                case "en-us":
                    seURLBase = URL(string: "https://na.finalfantasyxiv.com/lodestone/news/detail/")
                case "en-gb":
                    seURLBase = URL(string: "https://eu.finalfantasyxiv.com/lodestone/news/detail/")
                case "fr":
                    seURLBase = URL(string: "https://fr.finalfantasyxiv.com/lodestone/news/detail/")
                case "de":
                    seURLBase = URL(string: "https://de.finalfantasyxiv.com/lodestone/news/detail/")
                case "ja":
                    seURLBase = URL(string: "https://jp.finalfantasyxiv.com/lodestone/news/detail/")
                default:
                    seURLBase = nil
                }
            
                guard let seURLBase = seURLBase else
                {
                    return nil
                }
                if #available(macOS 13.0, *) {
                    return seURLBase.appending(path: self.id)
                } else {
                    return seURLBase.appendingPathComponent(self.id)
                }
                
            }
            
        }
        
        struct Banner: Codable, Identifiable {
            var id: String { lsbBanner }
            
            let lsbBanner: String
            let link: String
            var bannerImage: NSImage = NSImage(systemSymbolName: "wifi.slash", accessibilityDescription: nil)!
            
            enum CodingKeys: String, CodingKey {
                case lsbBanner = "lsb_banner"
                case link
            }
        }
        
        let news, topics, pinned: [News]
        let banner: [Banner]
    }
    
    static var info: Info? {
        guard let response = fetch(url: headline) else {
            return nil
        }
        guard let data = String(decoding: response.body, as: UTF8.self).unescapingUnicodeCharacters.data(using: .utf8) else {
            return nil
        }
        let jsonDecoder = JSONDecoder()
        do {
            return try jsonDecoder.decode(Info.self, from: data)
        } catch {
            return nil
        }
    }
}

extension String {
    var unescapingUnicodeCharacters: String {
        let mutableString = NSMutableString(string: self)
        CFStringTransform(mutableString, nil, "Any-Hex/Java" as NSString, true)
        
        return mutableString as String
    }
}

class FrontierTableView: NSObject {
    static let columnText = "text"
    static let columnIcon = "icon"
    
    var items: [Frontier.Info.News] = [] {
        didSet {
            tableView.reloadData()
        }
    }
    
    var icon: NSImage
    var tableView: NSTableView
    
    init(icon: NSImage) {
        self.icon = icon
        tableView = NSTableView(frame: .zero)
        super.init()
        tableView.intercellSpacing = NSSize(width: 0, height: 9)
        tableView.rowSizeStyle = .large
        tableView.backgroundColor = .clear
        tableView.headerView = nil
        tableView.dataSource = self
        tableView.delegate = self
        let iconCol = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(rawValue: FrontierTableView.columnIcon))
        let textCol = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(rawValue: FrontierTableView.columnText))
        iconCol.width = 20
        textCol.width = 433
        tableView.addTableColumn(iconCol)
        tableView.addTableColumn(textCol)
        tableView.target = self
        tableView.action = #selector(onItemClicked)
    }
    
    func add(items: [Frontier.Info.News]) {
        self.items += items
    }
    
    @objc private func onItemClicked() {
        let index = abs(tableView.clickedRow)
        guard index < items.count else {
            return
        }
        if let url = URL(string: items[abs(tableView.clickedRow)].url) {
            NSWorkspace.shared.open(url)
        }
    }
}

extension FrontierTableView: NSTableViewDelegate, NSTableViewDataSource {
    func numberOfRows(in tableView: NSTableView) -> Int {
        return items.count
    }
    
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        switch (tableColumn?.identifier)!.rawValue {
        case FrontierTableView.columnIcon:
            return NSImageView(image: icon)
        case FrontierTableView.columnText:
            return createCell(name: items[row].title)
        default:
            fatalError("FrontierTableView identifier not found")
        }
    }
    
    private func createCell(name: String) -> NSView {
        let text = NSTextField(string: name)
        text.cell?.usesSingleLineMode = false
        text.cell?.wraps = true
        text.cell?.lineBreakMode = .byWordWrapping
        text.isEditable = false
        text.isBordered = false
        text.drawsBackground = false
        text.preferredMaxLayoutWidth = 433
        return text
    }
    
    func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
        return createCell(name: items[row].title).intrinsicContentSize.height
    }
    
    func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool {
        return false
    }
    
    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
        let rowView = NSTableRowView()
        rowView.isEmphasized = false
        return rowView
    }
}
