import WidgetKit
import SwiftUI
import UsageCore

struct UsageEntry: TimelineEntry {
    let date: Date
    let board: UsageBoard?
}

struct UsageTimelineProvider: TimelineProvider {
    static let appGroupID = "group.com.gilad.agentusage"

    func placeholder(in context: Context) -> UsageEntry {
        UsageEntry(date: Date(), board: nil)
    }

    func getSnapshot(in context: Context, completion: @escaping (UsageEntry) -> Void) {
        let store = SnapshotStore(appGroupID: Self.appGroupID)
        completion(UsageEntry(date: Date(), board: store.load()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<UsageEntry>) -> Void) {
        let store = SnapshotStore(appGroupID: Self.appGroupID)
        let entry = UsageEntry(date: Date(), board: store.load())
        let next = Date().addingTimeInterval(15 * 60)
        completion(Timeline(entries: [entry], policy: .after(next)))
    }
}

struct AgentUsageWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "AgentUsageWidget", provider: UsageTimelineProvider()) { entry in
            UsageWidgetView(entry: entry)
        }
        .configurationDisplayName("Agent Usage")
        .description("Plan-quota usage for Claude and OpenAI.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}
