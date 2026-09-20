//
//  PressKeyListener.swift
//  auto-clicker
//
//  Created by Ben Tindall on 07/04/2022.
//

import SwiftUI
import Defaults

struct PressKeyListener: View {
    @Default(.autoClickerState) private var formState

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            ForEach(self.formState.pressInputs.indices, id: \.self) { index in
                PressInputSlotRow(input: self.$formState.pressInputs[index])
            }
        }
        .font(.system(size: 18, weight: .light))
    }
}

struct PressInputCountControls: View {
    @Default(.autoClickerState) private var formState

    private var canAdd: Bool {
        self.formState.pressInputs.count < MAX_PRESS_INPUTS
    }

    private var canRemove: Bool {
        self.formState.pressInputs.count > MIN_PRESS_INPUTS
    }

    private func addInput() {
        guard self.canAdd else {
            return
        }

        self.formState.pressInputs.append(Input())
    }

    private func removeInput() {
        guard self.canRemove else {
            return
        }

        self.formState.pressInputs.removeLast()
    }

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Button(action: self.addInput) {
                Text("press_input_add", comment: "Add another input")
            }
            .buttonStyle(UnderlinedButtonStyle())
            .disabled(!self.canAdd)

            Button(action: self.removeInput) {
                Text("press_input_remove", comment: "Remove the last input")
            }
            .buttonStyle(UnderlinedButtonStyle())
            .disabled(!self.canRemove)
        }
        .font(.system(size: 18, weight: .light))
        .padding(.trailing, 10)
    }
}
