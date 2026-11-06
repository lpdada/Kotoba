import SwiftUI

struct DecksView: View {
    @EnvironmentObject private var app: AppModel
    @State private var editingDeck: Deck?
    @State private var isCreating = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                ForEach(app.decks) { deck in
                    deckCard(deck)
                }

                Button {
                    isCreating = true
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "plus.circle.fill")
                        Text("新建分组")
                            .font(Theme.font(size: 14, weight: .semibold))
                        Spacer()
                    }
                    .padding(14)
                    .background(Theme.accentSoft, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .foregroundStyle(Theme.accent)
                }
                .buttonStyle(.plain)

                Text("分组只是组织方式，所有词都会进入同一套间隔复习队列；每组的「每日新词」只影响复习排队时的取样量。")
                    .font(Theme.font(size: 11))
                    .foregroundStyle(Theme.secondaryText)
                    .padding(.top, 4)
            }
            .padding(18)
        }
        .background(Theme.screenBackground)
        .navigationTitle("分组")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $editingDeck) { deck in
            DeckEditorSheet(deck: deck)
                .environmentObject(app)
        }
        .sheet(isPresented: $isCreating) {
            DeckEditorSheet(deck: nil)
                .environmentObject(app)
        }
    }

    private func deckCard(_ deck: Deck) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(deck.name)
                            .font(Theme.font(size: 17, weight: .semibold, design: .serif))
                            .foregroundStyle(Theme.ink)
                        if deck.id == Deck.defaultDeckID {
                            TagLabel(text: "默认", tint: Theme.accent)
                        }
                    }
                    if !deck.detail.isEmpty {
                        Text(deck.detail)
                            .font(Theme.font(size: 11))
                            .foregroundStyle(Theme.secondaryText)
                    }
                }
                Spacer()
                Button {
                    editingDeck = deck
                } label: {
                    Image(systemName: "slider.horizontal.3")
                        .font(Theme.font(size: 14))
                        .foregroundStyle(Theme.secondaryText)
                }
                .buttonStyle(.plain)
                .a11yButton("编辑分组 \(deck.name)", hint: "修改每日新词与复习上限")
            }

            HStack(spacing: 10) {
                infoPill(title: "词数", value: "\(app.wordCount(inDeck: deck.id))")
                infoPill(title: "每日新词", value: "\(deck.newPerDay)")
                infoPill(title: "每日上限", value: "\(deck.reviewLimit)")
            }

            if deck.id != Deck.defaultDeckID {
                Button(role: .destructive) {
                    app.deleteDeck(deck)
                } label: {
                    Text("删除分组")
                        .font(Theme.font(size: 11, weight: .medium))
                        .foregroundStyle(Theme.rose)
                }
                .buttonStyle(.plain)
            }
        }
        .card()
    }

    private func infoPill(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title)
                .font(Theme.font(size: 9))
                .foregroundStyle(Theme.secondaryText)
            Text(value)
                .font(Theme.font(size: 15, weight: .semibold, design: .rounded))
                .foregroundStyle(Theme.ink)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(9)
        .background(Theme.cardMuted, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

struct DeckEditorSheet: View {
    let deck: Deck?

    @EnvironmentObject private var app: AppModel
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var detail = ""
    @State private var newPerDay = 8
    @State private var reviewLimit = 60

    var body: some View {
        NavigationStack {
            Form {
                Section("名称") {
                    TextField("分组名", text: $name)
                    TextField("备注（可选）", text: $detail)
                }
                Section("每日节奏") {
                    Stepper("每日新词 \(newPerDay)", value: $newPerDay, in: 0...60)
                    Stepper("每日复习上限 \(reviewLimit)", value: $reviewLimit, in: 10...300)
                }
            }
            .navigationTitle(deck == nil ? "新建分组" : "编辑分组")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { save() }
                        .fontWeight(.semibold)
                }
            }
            .onAppear {
                guard let deck else {
                    name = ""
                    detail = ""
                    newPerDay = app.profile.dailyNewWords
                    reviewLimit = app.profile.dailyReviewLimit
                    return
                }
                name = deck.name
                detail = deck.detail
                newPerDay = deck.newPerDay
                reviewLimit = deck.reviewLimit
            }
        }
        .presentationDetents([.medium])
    }

    private func save() {
        if var existing = deck {
            existing.name = name.trimmingCharacters(in: .whitespaces).isEmpty ? existing.name : name
            existing.detail = detail
            existing.newPerDay = newPerDay
            existing.reviewLimit = reviewLimit
            app.updateDeck(existing)
        } else {
            var created = app.createDeck(name: name, detail: detail)
            created.newPerDay = newPerDay
            created.reviewLimit = reviewLimit
            app.updateDeck(created)
        }
        dismiss()
    }
}
