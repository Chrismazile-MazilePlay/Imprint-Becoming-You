//
//  ContentView.swift
//  ResizableHeaderScroll
//
//  Created by Balaji Venkatesh on 14/05/25.
//

import SwiftUI

let types: [String] = ["iPhone", "iPad", "MacBook", "Apple Watch", "AirPods", "HomePod", "VisionPro"]

struct ContentView: View {
    @State private var selectedType: String = types.first!
    @Namespace private var animation
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        ResizableHeaderScrollView {
            HStack(spacing: 15) {
                Button {
                    
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.title3)
                }
                
                Spacer(minLength: 0)
                
                Button {
                    
                } label: {
                    Image(systemName: "magnifyingglass")
                        .font(.title3)
                }
                
                Button {
                    
                } label: {
                    Image(systemName: "bubble")
                        .font(.title3)
                }
            }
            .overlay(content: {
                Text("Apple Store")
                    .fontWeight(.semibold)
            })
            .foregroundStyle(Color.primary)
            .padding(.horizontal, 15)
            .padding(.top, 15)
        } stickyHeader: {
            ScrollView(.horizontal, content: {
                HStack(spacing: 10) {
                    ForEach(types, id: \.self) { type in
                        Text(type)
                            .fontWeight(.semibold)
                            .padding(.horizontal, 20)
                            .foregroundStyle(selectedType == type ? (scheme == .dark ? .black : .white) : .gray)
                            .frame(height: 30)
                            .background {
                                if selectedType == type {
                                    Capsule()
                                        .fill(Color.primary)
                                        .matchedGeometryEffect(id: "ACTIVETAB", in: animation)
                                }
                            }
                            .contentShape(.rect)
                            .onTapGesture {
                                withAnimation(.snappy) {
                                    selectedType = type
                                }
                            }
                    }
                }
            })
            .scrollIndicators(.hidden)
            .scrollPosition(id: .init(get: {
                return selectedType
            }, set: { _ in
                
            }), anchor: .center)
            .safeAreaPadding(15)
            .padding(.top, 10)
        } background: {
            Rectangle()
                .fill(.ultraThinMaterial)
                .overlay(alignment: .bottom) {
                    Divider()
                }
        } content: {
            VStack(alignment: .leading, spacing: 15) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Usage")
                        .font(.caption2)
                        .foregroundStyle(.gray)
                    
                    Text(
                        """
                        ResizableHeaderScrollView {
                            
                        } stickyHeader: {
                            
                        } content: {
                            
                        }
                        """
                    )
                    .monospaced()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(15)
                    .background(.ultraThinMaterial, in: .rect(cornerRadius: 10))
                }
                
                ForEach(1...100, id: \.self) { _ in
                    RoundedRectangle(cornerRadius: 15)
                        .fill(.gray.opacity(0.3))
                        .frame(height: 50)
                }
            }
            .padding(15)
        }
    }
}

#Preview {
    ContentView()
}
