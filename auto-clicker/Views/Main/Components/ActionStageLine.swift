//
//  ActionStageLine.swift
//  auto-clicker
//
//  Created by Ben Tindall on 27/03/2022.
//

import SwiftUI
import Defaults

struct ActionStageLine<Content: View>: View {
    @ViewBuilder var content: () -> Content
    var trailing: AnyView?

    @Default(.appearanceSelectedTheme) private var activeTheme

    init(@ViewBuilder content: @escaping () -> Content, trailing: AnyView? = nil) {
        self.content = content
        self.trailing = trailing
    }

    var body: some View {
        HStack {
            HStack(content: content)
                .font(.system(size: 32, weight: .light))
                .foregroundColor(self.activeTheme.fontColour)
                .padding(.bottom, 5)

            Spacer()

            if let trailing = self.trailing {
                trailing
                    .padding(.bottom, 5)
            }
        }
    }
}

//struct ActionStageLine_Previews: PreviewProvider {
//    static var previews: some View {
//        ActionStageLine {
//
//        }
//    }
//}
