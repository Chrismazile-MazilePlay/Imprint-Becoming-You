//
//  ContentView.swift
//  InstagramProfileScroll
//
//  Created by Balaji Venkatesh on 17/05/25.
//

import SwiftUI

struct ContentView: View {
    @State private var symbolToggle: Bool = false
    var body: some View {
        HeaderPageScrollView(displaysSymbols: symbolToggle) {
            HeaderView()
        } labels: {
            PageLabel(title: "Posts", symbolImage: "square.grid.3x3.fill")
            PageLabel(title: "Reels", symbolImage: "photo.stack.fill")
            PageLabel(title: "Tagged", symbolImage: "person.crop.rectangle")
        } pages: {
            /// Each View Represents Individual Tab View!
            LazyVStack(spacing: 0) {
                Text(
                    """
                    HeaderPageScrollView {
                        // Header
                    } labels: {
                        // Tab Items
                    } pages: {
                        // Tab Views
                    }
                    """
                )
                .monospaced()
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(15)
                .background(.gray.opacity(0.1), in: .rect(cornerRadius: 15))
                .padding([.horizontal, .top], 15)
                .padding(.top, 10)
                
                DummyView(.red, count: 50)
            }
            
            DummyView(.yellow, count: 10)
            
            DummyView(.indigo, count: 5)
        } onRefresh: {
            print("Refresh Data")
        }
    }
    
    @ViewBuilder
    private func HeaderView() -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 15) {
                Image(.pic)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 80, height: 80)
                    .clipShape(.circle)
                
                VStack(alignment: .leading, spacing: 15) {
                    Text("iJustine")
                        .fontWeight(.semibold)
                    
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("7,358")
                                .fontWeight(.semibold)
                            Text("posts")
                                .font(.caption)
                        }
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text("1,6M")
                                .fontWeight(.semibold)
                            Text("followers")
                                .font(.caption)
                        }
                        .frame(maxWidth: .infinity)
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text("2,155")
                                .fontWeight(.semibold)
                            Text("following")
                                .font(.caption)
                        }
                    }
                }
                .padding(.horizontal, 10)
            }
            
            Text("Public figure")
                .font(.callout)
                .foregroundStyle(.gray)
            
            Text("Lorem Ipsum is simply dummy text of the printing and typesetting industry. Lorem Ipsum has been the industry's standard dummy text ever since the 1500s.")
                .font(.callout)
                .fontWeight(.light)
            
            Toggle("Display Symbols", isOn: $symbolToggle)
            
            Spacer(minLength: 0)
        }
        .padding(15)
    }
    
    /// Dummy Looping View
    @ViewBuilder
    private func DummyView(_ color: Color, count: Int) -> some View {
        LazyVGrid(columns: Array(repeating: GridItem(), count: 3)) {
            ForEach(0..<count, id: \.self) { index in
                RoundedRectangle(cornerRadius: 12)
                    .fill(color.gradient)
                    .frame(height: 160)
            }
        }
        .padding(15)
    }
}

#Preview {
    ContentView()
}
