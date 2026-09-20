//
//  AdDateField.swift
//  ACI Admin
//
//  A date and time input wearing AdField's clothes.
//
//  Compact style on purpose: .graphical and .wheel both fight AdShell's ScrollView,
//  and events sit weeks out, which a row of pills can't express.
//

import SwiftUI

struct AdDateField: View {
    @Environment(\.palette) private var c
    let label: String
    @Binding var date: Date
    var earliest: Date? = nil
    var hint: String? = nil
    var error: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label.uppercased())
                .font(AdFont.label())
                .tracking(1.7)
                .foregroundStyle(c.fgMuted)

            picker
                .datePickerStyle(.compact)
                .labelsHidden()
                .tint(c.accent)
                .environment(\.calendar, .ghana)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(c.card, in: .rect(cornerRadius: 12))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(error != nil ? c.destructive : c.cardEdge)
                )

            if let error {
                Text(error)
                    .font(AdFont.sans(11.5))
                    .foregroundStyle(c.destructive)
            } else if let hint {
                Text(hint)
                    .font(AdFont.sans(11.5))
                    .lineSpacing(2)
                    .foregroundStyle(c.fgMuted)
            }
        }
        .padding(EdgeInsets(top: 0, leading: 20, bottom: 14, trailing: 20))
    }

    @ViewBuilder
    private var picker: some View {
        if let earliest {
            DatePicker(label, selection: $date, in: earliest...,
                       displayedComponents: [.date, .hourAndMinute])
        } else {
            DatePicker(label, selection: $date,
                       displayedComponents: [.date, .hourAndMinute])
        }
    }
}
