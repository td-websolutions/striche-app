import SwiftUI
import Charts
import UIKit

// MARK: - German month helpers

enum MonthNames {
    static let full: [String] = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "de_DE")
        return f.standaloneMonthSymbols ?? []
    }()
    static let short: [String] = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "de_DE")
        return f.shortStandaloneMonthSymbols ?? []
    }()
    static func name(_ month: Int) -> String { full[safe: month - 1] ?? "\(month)" }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

private func eur(_ v: Double) -> String { String(format: "%.2f €", v) }

// MARK: - Statistics screen

struct StatisticsView: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State private var selectedYear: Int
    @State private var showReport = false

    init() {
        _selectedYear = State(initialValue: Calendar.current.component(.year, from: .now))
    }

    private var years: [Int] {
        let y = store.yearsWithData
        return y.isEmpty ? [Calendar.current.component(.year, from: .now)] : y
    }

    private var revenue: [Double] { store.monthlyRevenue(year: selectedYear) }
    private var paid: [Double] { store.monthlyPaid(year: selectedYear) }

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.appBackground.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 18) {
                        yearPicker
                        totalsRow
                        chartCard(title: "Umsatz pro Monat",
                                  subtitle: "Alle gebuchten Getränke & Speisen",
                                  data: revenue, color: Theme.gold)
                        chartCard(title: "Bezahlter Umsatz pro Monat",
                                  subtitle: "Beglichene Beträge (bar / Guthaben)",
                                  data: paid, color: Theme.mint)

                        Button {
                            Haptics.tap(); showReport = true
                        } label: {
                            Label("Monatsauswertung erstellen", systemImage: "doc.text.fill")
                        }
                        .buttonStyle(PrimaryButtonStyle())
                        .padding(.top, 4)
                    }
                    .padding(.horizontal, 18)
                    .padding(.vertical, 16)
                }
                .scrollBounceBehavior(.basedOnSize)
            }
            .navigationTitle("Statistik")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Fertig") { dismiss() } } }
            .toolbarColorScheme(.dark, for: .navigationBar)
            .sheet(isPresented: $showReport) {
                MonthlyReportSheet(initialYear: selectedYear)
            }
        }
        .preferredColorScheme(.dark)
    }

    private var yearPicker: some View {
        Menu {
            ForEach(years, id: \.self) { y in
                Button { selectedYear = y } label: {
                    if y == selectedYear { Label("\(y)", systemImage: "checkmark") } else { Text(verbatim: "\(y)") }
                }
            }
        } label: {
            HStack {
                Image(systemName: "calendar")
                Text(verbatim: "\(selectedYear)").font(.system(size: 16, weight: .bold, design: .rounded))
                Image(systemName: "chevron.up.chevron.down").font(.caption)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 16).padding(.vertical, 10)
            .glassCard(corner: 14)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var totalsRow: some View {
        HStack(spacing: 12) {
            totalChip(title: "Umsatz \(selectedYear)", value: revenue.reduce(0, +), color: Theme.gold)
            totalChip(title: "Bezahlt \(selectedYear)", value: paid.reduce(0, +), color: Theme.mint)
        }
    }

    private func totalChip(title: String, value: Double, color: Color) -> some View {
        VStack(spacing: 4) {
            Text(title).font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(Theme.textSecondary)
            Text(eur(value)).font(.system(size: 20, weight: .heavy, design: .rounded))
                .foregroundStyle(color)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .glassCard(corner: 16)
    }

    private func chartCard(title: String, subtitle: String, data: [Double], color: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.system(size: 15, weight: .bold, design: .rounded)).foregroundStyle(.white)
            Text(subtitle).font(.system(size: 11, weight: .medium, design: .rounded)).foregroundStyle(Theme.textSecondary)
            if data.allSatisfy({ $0 == 0 }) {
                Text("Keine Daten in \(selectedYear)")
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(Theme.textSecondary)
                    .frame(maxWidth: .infinity, minHeight: 120)
            } else {
                Chart(Array(data.enumerated()), id: \.offset) { idx, value in
                    BarMark(
                        x: .value("Monat", MonthNames.short[safe: idx] ?? "\(idx+1)"),
                        y: .value("Betrag", value)
                    )
                    .foregroundStyle(color.gradient)
                    .cornerRadius(4)
                }
                .chartYAxis {
                    AxisMarks { value in
                        AxisGridLine().foregroundStyle(Color.white.opacity(0.08))
                        AxisValueLabel {
                            if let d = value.as(Double.self) {
                                Text("\(Int(d))").font(.system(size: 9)).foregroundStyle(Theme.textSecondary)
                            }
                        }
                    }
                }
                .chartXAxis {
                    AxisMarks { value in
                        AxisValueLabel {
                            if let s = value.as(String.self) {
                                Text(s).font(.system(size: 8)).foregroundStyle(Theme.textSecondary)
                            }
                        }
                    }
                }
                .frame(height: 160)
                .padding(.top, 6)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(corner: 18)
    }
}

// MARK: - Monthly report (dynamic + export)

struct MonthlyReportSheet: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State private var year: Int
    @State private var month: Int
    @State private var shareItem: ShareItem?

    init(initialYear: Int) {
        _year = State(initialValue: initialYear)
        _month = State(initialValue: Calendar.current.component(.month, from: .now))
    }

    private var years: [Int] {
        let y = store.yearsWithData
        return y.isEmpty ? [Calendar.current.component(.year, from: .now)] : y
    }

    private var positions: [ReportPosition] { store.reportPositions(year: year, month: month) }
    private var totalSum: Double { positions.reduce(0) { $0 + $1.total } }
    private var paidSum: Double { positions.reduce(0) { $0 + $1.paidTotal } }
    private var openSum: Double { positions.reduce(0) { $0 + $1.openTotal } }
    private var totalCount: Int { positions.reduce(0) { $0 + $1.count } }

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.appBackground.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 16) {
                        pickers
                        summaryCard
                        if positions.isEmpty {
                            Text("Keine Buchungen in \(MonthNames.name(month)) \(year)")
                                .font(.system(size: 14, weight: .medium, design: .rounded))
                                .foregroundStyle(Theme.textSecondary)
                                .padding(.top, 30)
                        } else {
                            positionsCard
                            exportButtons
                        }
                    }
                    .padding(.horizontal, 18)
                    .padding(.vertical, 16)
                }
                .scrollBounceBehavior(.basedOnSize)
            }
            .navigationTitle("Monatsauswertung")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Schließen") { dismiss() } } }
            .toolbarColorScheme(.dark, for: .navigationBar)
            .sheet(item: $shareItem) { item in
                ShareSheet(urls: [item.url])
            }
        }
        .preferredColorScheme(.dark)
    }

    private var pickers: some View {
        HStack(spacing: 12) {
            Menu {
                ForEach(1...12, id: \.self) { m in
                    Button { month = m } label: {
                        if m == month { Label(MonthNames.name(m), systemImage: "checkmark") }
                        else { Text(MonthNames.name(m)) }
                    }
                }
            } label: { pickerLabel(MonthNames.name(month)) }

            Menu {
                ForEach(years, id: \.self) { y in
                    Button { year = y } label: {
                        if y == year { Label("\(y)", systemImage: "checkmark") } else { Text(verbatim: "\(y)") }
                    }
                }
            } label: { pickerLabel("\(year)") }
        }
    }

    private func pickerLabel(_ text: String) -> some View {
        HStack {
            Text(text).font(.system(size: 15, weight: .bold, design: .rounded))
            Spacer()
            Image(systemName: "chevron.up.chevron.down").font(.caption)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 14).padding(.vertical, 11)
        .frame(maxWidth: .infinity)
        .glassCard(corner: 14)
    }

    private var summaryCard: some View {
        HStack(spacing: 10) {
            summaryItem("Umsatz", totalSum, Theme.gold)
            summaryItem("Bezahlt", paidSum, Theme.mint)
            summaryItem("Offen", openSum, Theme.accent)
        }
    }

    private func summaryItem(_ title: String, _ value: Double, _ color: Color) -> some View {
        VStack(spacing: 3) {
            Text(title).font(.system(size: 10, weight: .bold, design: .rounded)).foregroundStyle(Theme.textSecondary)
            Text(eur(value)).font(.system(size: 15, weight: .heavy, design: .rounded)).foregroundStyle(color)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 12).glassCard(corner: 14)
    }

    private var positionsCard: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Position").font(.system(size: 11, weight: .bold, design: .rounded))
                Spacer()
                Text("Anz.").font(.system(size: 11, weight: .bold, design: .rounded)).frame(width: 40, alignment: .trailing)
                Text("Summe").font(.system(size: 11, weight: .bold, design: .rounded)).frame(width: 70, alignment: .trailing)
            }
            .foregroundStyle(Theme.gold)
            .padding(.vertical, 8)
            Divider().overlay(Color.white.opacity(0.1))
            ForEach(positions) { p in
                HStack {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(p.name).font(.system(size: 14, weight: .semibold, design: .rounded)).foregroundStyle(.white)
                        if let s = p.sizeLabel {
                            Text(s).font(.system(size: 11, design: .rounded)).foregroundStyle(Theme.textSecondary)
                        }
                    }
                    Spacer()
                    Text("\(p.count)×").font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(.white).frame(width: 40, alignment: .trailing)
                    VStack(alignment: .trailing, spacing: 1) {
                        Text(eur(p.total)).font(.system(size: 13, weight: .heavy, design: .rounded)).foregroundStyle(.white)
                        if p.openTotal > 0 {
                            Text("offen \(eur(p.openTotal))").font(.system(size: 9, weight: .bold, design: .rounded))
                                .foregroundStyle(Theme.accent)
                        }
                    }
                    .frame(width: 70, alignment: .trailing)
                }
                .padding(.vertical, 9)
                Divider().overlay(Color.white.opacity(0.06))
            }
            HStack {
                Text("Gesamt").font(.system(size: 14, weight: .heavy, design: .rounded)).foregroundStyle(.white)
                Spacer()
                Text("\(totalCount)×").font(.system(size: 13, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white).frame(width: 40, alignment: .trailing)
                Text(eur(totalSum)).font(.system(size: 14, weight: .heavy, design: .rounded))
                    .foregroundStyle(Theme.gold).frame(width: 70, alignment: .trailing)
            }
            .padding(.top, 10)
        }
        .padding(16)
        .glassCard(corner: 18)
    }

    private var exportButtons: some View {
        HStack(spacing: 12) {
            Button {
                Haptics.tap()
                if let url = ReportExporter.pdf(positions: positions, month: month, year: year,
                                                clubName: store.club?.name ?? "Verein",
                                                total: totalSum, paid: paidSum, open: openSum, count: totalCount) {
                    shareItem = ShareItem(url: url)
                }
            } label: {
                Label("PDF", systemImage: "arrow.down.doc.fill").frame(maxWidth: .infinity)
            }
            .buttonStyle(PrimaryButtonStyle())

            Button {
                Haptics.tap()
                if let url = ReportExporter.csv(positions: positions, month: month, year: year,
                                                clubName: store.club?.name ?? "Verein",
                                                total: totalSum, paid: paidSum, open: openSum, count: totalCount) {
                    shareItem = ShareItem(url: url)
                }
            } label: {
                Label("Excel", systemImage: "tablecells.fill").frame(maxWidth: .infinity)
            }
            .buttonStyle(PrimaryButtonStyle(filled: false))
        }
    }
}

// MARK: - Share sheet

struct ShareItem: Identifiable {
    let id = UUID()
    let url: URL
}

struct ShareSheet: UIViewControllerRepresentable {
    let urls: [URL]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: urls, applicationActivities: nil)
    }
    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}

// MARK: - Report export (PDF + CSV)

enum ReportExporter {
    private static func eur(_ v: Double) -> String { String(format: "%.2f EUR", v) }

    private static func tempURL(_ name: String) -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(name)
    }

    static func csv(positions: [ReportPosition], month: Int, year: Int, clubName: String,
                    total: Double, paid: Double, open: Double, count: Int) -> URL? {
        var rows: [String] = []
        rows.append("\(clubName) - Auswertung \(MonthNames.name(month)) \(year)")
        rows.append("")
        rows.append("Position;Anzahl;Einzelpreis;Gesamt;Bezahlt;Offen")
        let f: (Double) -> String = { String(format: "%.2f", $0).replacingOccurrences(of: ".", with: ",") }
        for p in positions {
            let pos = (p.name + (p.sizeLabel.map { " " + $0 } ?? "")).replacingOccurrences(of: ";", with: ",")
            rows.append("\(pos);\(p.count);\(f(p.unitPrice));\(f(p.total));\(f(p.paidTotal));\(f(p.openTotal))")
        }
        rows.append("")
        rows.append("Gesamt;\(count);;\(f(total));\(f(paid));\(f(open))")
        let csv = "\u{FEFF}" + rows.joined(separator: "\r\n")
        let url = tempURL("Auswertung_\(year)_\(String(format: "%02d", month)).csv")
        do { try csv.write(to: url, atomically: true, encoding: .utf8); return url } catch { return nil }
    }

    static func pdf(positions: [ReportPosition], month: Int, year: Int, clubName: String,
                    total: Double, paid: Double, open: Double, count: Int) -> URL? {
        let pageW: CGFloat = 595, pageH: CGFloat = 842, margin: CGFloat = 40
        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: pageW, height: pageH))
        let url = tempURL("Auswertung_\(year)_\(String(format: "%02d", month)).pdf")

        let title = [NSAttributedString.Key.font: UIFont.boldSystemFont(ofSize: 20)]
        let sub = [NSAttributedString.Key.font: UIFont.systemFont(ofSize: 12),
                   .foregroundColor: UIColor.darkGray]
        let head = [NSAttributedString.Key.font: UIFont.boldSystemFont(ofSize: 11)]
        let cell = [NSAttributedString.Key.font: UIFont.systemFont(ofSize: 11)]
        let cellB = [NSAttributedString.Key.font: UIFont.boldSystemFont(ofSize: 11)]

        // Columns: Position | Anz | Einzel | Gesamt | Bezahlt | Offen
        let colPos = margin
        let colAnz = pageW - margin - 360
        let colEinzel = pageW - margin - 290
        let colGes = pageW - margin - 200
        let colBez = pageW - margin - 110
        let colOffen = pageW - margin - 30

        func drawRight(_ text: String, rightX: CGFloat, y: CGFloat, attrs: [NSAttributedString.Key: Any]) {
            let s = NSAttributedString(string: text, attributes: attrs)
            let w = s.size().width
            s.draw(at: CGPoint(x: rightX - w, y: y))
        }

        do {
            try renderer.writePDF(to: url) { ctx in
                ctx.beginPage()
                var y: CGFloat = margin
                ("\(clubName)" as NSString).draw(at: CGPoint(x: margin, y: y), withAttributes: title)
                y += 28
                ("Monatsauswertung – \(MonthNames.name(month)) \(year)" as NSString)
                    .draw(at: CGPoint(x: margin, y: y), withAttributes: sub)
                y += 30

                // header row
                ("Position" as NSString).draw(at: CGPoint(x: colPos, y: y), withAttributes: head)
                drawRight("Anz.", rightX: colAnz, y: y, attrs: head)
                drawRight("Einzel", rightX: colEinzel, y: y, attrs: head)
                drawRight("Gesamt", rightX: colGes, y: y, attrs: head)
                drawRight("Bezahlt", rightX: colBez, y: y, attrs: head)
                drawRight("Offen", rightX: colOffen, y: y, attrs: head)
                y += 18
                ctx.cgContext.setStrokeColor(UIColor.lightGray.cgColor)
                ctx.cgContext.move(to: CGPoint(x: margin, y: y))
                ctx.cgContext.addLine(to: CGPoint(x: pageW - margin, y: y))
                ctx.cgContext.strokePath()
                y += 8

                for p in positions {
                    if y > pageH - margin - 60 {
                        ctx.beginPage(); y = margin
                    }
                    let name = p.name + (p.sizeLabel.map { " · " + $0 } ?? "")
                    (name as NSString).draw(at: CGPoint(x: colPos, y: y), withAttributes: cell)
                    drawRight("\(p.count)", rightX: colAnz, y: y, attrs: cell)
                    drawRight(eur(p.unitPrice), rightX: colEinzel, y: y, attrs: cell)
                    drawRight(eur(p.total), rightX: colGes, y: y, attrs: cell)
                    drawRight(eur(p.paidTotal), rightX: colBez, y: y, attrs: cell)
                    drawRight(eur(p.openTotal), rightX: colOffen, y: y, attrs: cell)
                    y += 18
                }

                y += 6
                ctx.cgContext.move(to: CGPoint(x: margin, y: y))
                ctx.cgContext.addLine(to: CGPoint(x: pageW - margin, y: y))
                ctx.cgContext.strokePath()
                y += 10
                ("Gesamt" as NSString).draw(at: CGPoint(x: colPos, y: y), withAttributes: cellB)
                drawRight("\(count)", rightX: colAnz, y: y, attrs: cellB)
                drawRight(eur(total), rightX: colGes, y: y, attrs: cellB)
                drawRight(eur(paid), rightX: colBez, y: y, attrs: cellB)
                drawRight(eur(open), rightX: colOffen, y: y, attrs: cellB)
            }
            return url
        } catch { return nil }
    }
}
