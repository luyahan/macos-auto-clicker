//
//  PressInputSlotRow.swift
//  auto-clicker
//
//  Created by Ben Tindall on 07/04/2022.
//

import SwiftUI

struct PressInputSlotRow: View {
    @State private var showingPressKeyListenerModal = false

    @Binding var input: Input

    var body: some View {
        Button(self.input.readable) {
            self.showingPressKeyListenerModal = true
        }
        .buttonStyle(UnderlinedButtonStyle())
        .sheet(isPresented: self.$showingPressKeyListenerModal, content: {
            PressKeyListenerModal(input: self.$input)
        })
    }
}
