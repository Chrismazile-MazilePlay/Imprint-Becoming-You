//
//  ContentView.swift
//  DynamicHeightSheet
//
//  Created by Balaji Venkatesh on 31/08/25.
//

import SwiftUI

/// Dummy Enum for UI Demo
enum Padding: String, CaseIterable {
    case small = "Small (50)"
    case medium = "Medium (100)"
    case large = "Large (250)"
    
    var value: CGFloat {
        switch self {
        case .small: 50
        case .medium: 100
        case .large: 250
        }
    }
}

struct ContentView: View {
    @State private var padding: Padding = .small
    @State private var showSheet: Bool = false
    @State private var showTrayView: Bool = false
    var body: some View {
        NavigationStack {
            List {
                Section("Usage") {
                    Text(
                    """
                    .sheet(...) {
                        DynamicSheet {
                            // View
                        }
                    }
                    """
                    )
                    .monospaced()
                }
                
                Button("Show Basic Demo") {
                    showSheet.toggle()
                }
                
                Button("Show Tray View") {
                    showTrayView.toggle()
                }
            }
            .navigationTitle("Dynamic Sheet")
        }
        .sheet(isPresented: $showSheet) {
            DynamicSheet(animation: .smooth(duration: 0.35, extraBounce: 0)) {
                VStack(spacing: 15) {
                    VStack(spacing: 6) {
                        Text("Hello From Dynamic Sheet!")
                            .fontWeight(.medium)
                        
                        Text("Select Padding from the picker to see the change")
                            .font(.caption2)
                            .foregroundStyle(.gray)
                    }
                    .padding(.bottom, 10)
                    
                    Picker("", selection: $padding) {
                        ForEach(Padding.allCases, id: \.rawValue) {
                            Text($0.rawValue)
                                .tag($0)
                        }
                    }
                    .pickerStyle(.segmented)
                    
                    Text("Selected Value: **.padding(.vertical, \(Int(padding.value)))**")
                        .font(.callout)
                        .foregroundStyle(.primary.opacity(0.8))
                        .padding(.top, 10)
                }
                .padding(.horizontal, 30)
                .padding(.vertical, padding.value)
            }
        }
        .sheet(isPresented: $showTrayView) {
            let animation: Animation = .snappy(duration: 0.3, extraBounce: 0)
            DynamicSheet(animation: animation) {
                TrayView(animation: animation)
            }
        }
    }
}

#Preview {
    ContentView()
}
