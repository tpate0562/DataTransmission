//
//  ContentView.swift
//  DataTransmission
//
//  Root view with tab navigation between Send and Receive.
//

import SwiftUI

struct ContentView: View {
    var body: some View {
        TabView {
            SenderView()
                .tabItem {
                    Label("Send", systemImage: "arrow.up.doc.fill")
                }

            ReceiverView()
                .tabItem {
                    Label("Receive", systemImage: "arrow.down.doc.fill")
                }
        }
    }
}

#Preview {
    ContentView()
}
