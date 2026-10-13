import Darwin
import Foundation
import SafariServices

// Entry point Safari instantiates for every runtime.sendNativeMessage from the extension's JS.
// Deliberately tiny: decode the message, hand it to the process-wide SafariRelay, encode the reply.
// The relay keeps ONE socket to the Tattle app for the life of the appex process, so the app sees
// a stable "Safari connected" connection, exactly like tattle-bridge gives Chrome/Firefox.
//
// Dev/production isolation: the flavour comes from this appex's own Info.plist (stamped by the build
// script from the containing app), so TattleSafari Dev can only ever reach "Tattle Dev"'s socket.

private enum Shared {
    static let relay: SafariRelay = {
        let raw = Bundle.main.object(forInfoDictionaryKey: "TattleFlavour") as? String
        let flavour = raw.flatMap(AppFlavour.init(rawValue:)) ?? .dev  // unknown => the safe, dev side
        // A sandboxed process's NSHomeDirectory() is its container, so ask the user database.
        let home = getpwuid(getuid()).flatMap { String(cString: $0.pointee.pw_dir) } ?? NSHomeDirectory()
        let path = flavour.socketPath(home: home)
        return SafariRelay(connect: { try UnixSocketLink.connect(path: path) })
    }()
}

@objc(SafariWebExtensionHandler)
final class SafariWebExtensionHandler: NSObject, NSExtensionRequestHandling {
    func beginRequest(with context: NSExtensionContext) {
        let item = context.inputItems.first as? NSExtensionItem
        // "message" is the value of SFExtensionMessageKey (deprecated constant on newer SDKs).
        let request = item?.userInfo?["message"] as? [String: Any]
        let response = NSExtensionItem()
        response.userInfo = ["message": Shared.relay.handle(request)]
        context.completeRequest(returningItems: [response], completionHandler: nil)
    }
}
