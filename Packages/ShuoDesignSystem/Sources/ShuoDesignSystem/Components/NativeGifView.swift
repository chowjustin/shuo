//
//  File.swift
//  ShuoDesignSystem
//
//  Created by Matthew Sebastian Lesmana on 28/07/26.
//

import SwiftUI
import WebKit

struct NativeGifView: UIViewRepresentable {
    let gifName: String

    func makeUIView(context: Context) -> WKWebView {
        let webView = WKWebView()
        webView.allowsLinkPreview = false
        webView.allowsBackForwardNavigationGestures = false
        webView.scrollView.isScrollEnabled = false
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear

        // Reads from Assets.xcassets as a Data Set, not a loose bundle file.
        if let asset = NSDataAsset(name: gifName, bundle: .module) {
            let base64 = asset.data.base64EncodedString()

            let html = """
            <html>
            <body style="margin:0;background:transparent;display:flex;justify-content:center;align-items:center;">
                <img src="data:image/gif;base64,\(base64)" style="width:100%;height:100%;object-fit:contain;" />
            </body>
            </html>
            """

            webView.loadHTMLString(html, baseURL: nil)
        }
        
        if let asset = NSDataAsset(name: gifName, bundle: .module) {
            print("✅ Found \(gifName)")
            print("Size:", asset.data.count)
        } else {
            print("❌ Couldn't find \(gifName)")
        }


        
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}
}
