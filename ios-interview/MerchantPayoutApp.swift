//
//  MerchantPayoutApp.swift
//  ios-interview
//
//  Created by Checkout.com on 21/05/2026.
//

import SwiftUI

@main
struct MerchantPayoutApp: App {
    init() {
        // Register MockURLProtocol so URLSession.shared also routes through the mock server.
        URLProtocol.registerClass(MockURLProtocol.self)
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
