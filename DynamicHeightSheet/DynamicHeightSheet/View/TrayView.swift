//
//  TrayView.swift
//  DynamicHeightSheet
//
//  Created by Balaji Venkatesh on 31/08/25.
//

import SwiftUI

/// View 1 Mock Data
struct Action: Identifiable, Hashable {
    var id: String = UUID().uuidString
    var image: String
    var title: String
}

let actions: [Action] = [
    .init(image: "xbox.logo", title: "Game Pass"),
    .init(image: "playstation.logo", title: "PS Plus"),
    .init(image: "apple.logo", title: "iCloud+"),
    .init(image: "appletv.fill", title: "Apple TV"),
]

/// View 2 Mock Data
struct Period: Identifiable {
    var id: String = UUID().uuidString
    var title: String
    var value: Int
}

let periods: [Period] = [
    .init(title: "1", value: 1),
    .init(title: "3", value: 3),
    .init(title: "5", value: 5),
    .init(title: "7", value: 7),
    .init(title: "9", value: 9),
    .init(title: "Custom", value: 0),
]

/// View 3 Mock Data
struct KeyPad: Identifiable {
    var id: String = UUID().uuidString
    var title: String
    var value: Int
    var isBack: Bool = false
}

enum CurrentView {
    case actions
    case periods
    case keypad
}

/// Custom keypad data ranges from 0 to 9 and includes a back button
let keypadValues: [KeyPad] = (1...9).compactMap({ .init(title: String("\($0)"), value: $0) }) + [
    .init(title: "0", value: 0),
    .init(title: "chevron.left", value: -1, isBack: true)
]

struct TrayView: View {
    var animation: Animation
    @State private var currentView: CurrentView = .actions
    @State private var selectedAction: Action?
    @State private var selectedPeriod: Period?
    @State private var duration: String = ""
    @Environment(\.dismiss) var dismiss
    var body: some View {
        VStack(spacing: 20) {
            ZStack {
                switch currentView {
                case .actions: View1()
                        .geometryGroup()
                        .transition(
                            .blurReplace(.upUp)
                        )
                case .periods: View2()
                        .geometryGroup()
                        .transition(
                            .blurReplace(.downUp)
                        )
                case .keypad: View3()
                        .geometryGroup()
                        .transition(.blurReplace(.upUp))
                }
            }
            .geometryGroup()
            
            /// Continue Button
            Button {
                if currentView == .actions {
                    withAnimation(animation) {
                        currentView = .periods
                    }
                } else {
                    print("Subscribe")
                }
            } label: {
                Text(currentView == .actions ? "Continue" : "Subscribe")
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 15)
                    .foregroundStyle(.white)
                    .background(.blue, in: .capsule)
            }
            .disabledWithOpacity(currentView == .actions ? selectedAction == nil : false)
            .disabledWithOpacity(currentView == .periods ? selectedPeriod == nil : false)
            .disabledWithOpacity(currentView == .keypad ? duration.isEmpty : false)
            .padding(.top, 15)
            .geometryGroup()
        }
        .padding([.horizontal, .top], 20)
        .padding(.bottom, isiOS26 ? 0 : 10)
        .frame(maxHeight: .infinity, alignment: .bottom)
    }
    
    /// View 1
    @ViewBuilder
    func View1() -> some View {
        VStack(spacing: 12) {
            HStack {
                Text("Choose Subscription")
                    .font(.title2)
                    .fontWeight(.semibold)
                
                Spacer(minLength: 0)
                
                Button {
                    /// Dismissing Sheet
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title)
                        .foregroundStyle(Color.gray, Color.primary.opacity(0.1))
                }
            }
            .padding(.bottom, 10)
            
            /// Custom Checkbox Menu
            ForEach(actions) { action in
                let isSelected: Bool = selectedAction?.id == action.id
                
                HStack(spacing: 10) {
                    Image(systemName: action.image)
                        .font(.title)
                        .frame(width: 40)
                    
                    Text(action.title)
                        .fontWeight(.semibold)
                    
                    Spacer(minLength: 0)
                    
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle.fill")
                        .font(.title)
                        .contentTransition(.symbolEffect)
                        .foregroundStyle(isSelected ? Color.blue : Color.gray.opacity(0.2))
                }
                .padding(.vertical, 6)
                .contentShape(.rect)
                .onTapGesture {
                    withAnimation(.snappy) {
                        selectedAction = isSelected ? nil : action
                    }
                }
            }
        }
    }
    
    /// View 2
    @ViewBuilder
    func View2() -> some View {
        VStack(spacing: 12) {
            HStack {
                Text("Choose Period")
                    .font(.title2)
                    .fontWeight(.semibold)
                
                Spacer(minLength: 0)
                
                Button {
                    withAnimation(animation) {
                        currentView = .actions
                    }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title)
                        .foregroundStyle(Color.gray, Color.primary.opacity(0.1))
                }
            }
            .padding(.bottom, 25)
            
            Text("Choose the period you want\nto get subscribed.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.gray)
                .padding(.bottom, 20)
                .fixedSize(horizontal: false, vertical: true)
            
            /// Grid Box View
            LazyVGrid(columns: Array(repeating: GridItem(), count: 3), spacing: 15) {
                ForEach(periods) { period in
                    let isSelected = selectedPeriod?.id == period.id
                    
                    VStack(spacing: 6) {
                        Text(period.title)
                            .font(period.value == 0 ? .title3 : .title2)
                            .fontWeight(.semibold)
                        
                        if period.value != 0 {
                            Text(period.value == 1 ? "Month" : "Months")
                                .font(.caption)
                                .foregroundStyle(.gray)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 80)
                    .background {
                        RoundedRectangle(cornerRadius: 20)
                            .fill((isSelected ? Color.blue : Color.gray).opacity(isSelected ? 0.2 : 0.1))
                    }
                    .contentShape(.rect)
                    .onTapGesture {
                        withAnimation(animation) {
                            if period.value == 0 {
                                /// Go To Custom Keypad View (View 3)
                                currentView = .keypad
                            } else {
                                selectedPeriod = isSelected ? nil : period
                            }
                        }
                    }
                }
            }
        }
    }
    
    /// View 3
    @ViewBuilder
    func View3() -> some View {
        VStack(spacing: 12) {
            HStack {
                Text("Custom Duration")
                    .font(.title2)
                    .fontWeight(.semibold)
                
                Spacer(minLength: 0)
                
                Button {
                    withAnimation(animation) {
                        currentView = .periods
                    }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title)
                        .foregroundStyle(Color.gray, Color.primary.opacity(0.1))
                }
            }
            .padding(.bottom, 10)
            
            VStack(spacing: 6) {
                Text(duration.isEmpty ? "0" : duration)
                    .font(.system(size: 60, weight: .black))
                    .contentTransition(.numericText())
                
                Text("Days")
                    .font(.caption)
                    .foregroundStyle(.gray)
            }
            .padding(.vertical, 20)
            
            /// Custom Keypad View
            LazyVGrid(columns: Array(repeating: GridItem(), count: 3), spacing: 15) {
                ForEach(keypadValues) { keyValue in
                    if keyValue.value == 0 {
                        Spacer()
                    }
                    
                    Group {
                        if keyValue.isBack {
                            Image(systemName: keyValue.title)
                        } else {
                            Text(keyValue.title)
                        }
                    }
                    .font(.title2)
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity)
                    .frame(height: 60)
                    .contentShape(.rect)
                    .onTapGesture {
                        withAnimation(.snappy) {
                            if keyValue.isBack {
                                if !duration.isEmpty {
                                    duration.removeLast()
                                }
                            } else {
                                duration.append(keyValue.title)
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, -15)
        }
    }
}

extension View {
    func disabledWithOpacity(_ status: Bool) -> some View {
        self
            .disabled(status)
            .opacity(status ? 0.5 : 1)
    }
}
