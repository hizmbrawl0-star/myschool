import SwiftUI
import UserNotifications

@main
struct myschoolApp: App {
    @StateObject private var store = ScheduleStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
                .preferredColorScheme(.light)
        }
    }
}

enum Weekday: String, CaseIterable, Codable, Identifiable {
    case monday = "Пн", tuesday = "Вт", wednesday = "Ср", thursday = "Чт", friday = "Пт"
    var id: String { rawValue }
}

struct Subject: Codable, Identifiable, Equatable {
    var id = UUID()
    var name: String
    var room: String
}

struct Lesson: Codable, Identifiable {
    var id = UUID()
    var subjectID: UUID?
}

struct LessonTime: Codable {
    var start: Date
    var end: Date
}

final class ScheduleStore: ObservableObject {
    @Published var subjects: [Subject] = [] { didSet { save() } }
    @Published var lessons: [Weekday: [Lesson]] = [:] { didSet { save() } }
    @Published var times: [LessonTime] = [] { didSet { save() } }
    @Published var lessonMinutes = 45 { didSet { rebuildTimes() } }
    @Published var breakMinutes = 10 { didSet { rebuildTimes() } }
    @Published var selectedDay: Weekday = .monday

    private let key = "myschool.data"

    init() {
        if let data = UserDefaults.standard.data(forKey: key),
           let saved = try? JSONDecoder().decode(SavedData.self, from: data) {
            subjects = saved.subjects; lessons = saved.lessons; times = saved.times
            lessonMinutes = saved.lessonMinutes; breakMinutes = saved.breakMinutes
        } else { resetDefaults() }
    }

    var currentLessons: [Lesson] {
        get { lessons[selectedDay] ?? Array(repeating: Lesson(), count: 8) }
        set { lessons[selectedDay] = newValue }
    }

    func resetDefaults() {
        rebuildTimes()
        for day in Weekday.allCases { lessons[day] = Array(repeating: Lesson(), count: 8) }
    }

    func rebuildTimes() {
        let base = Calendar.current.date(bySettingHour: 8, minute: 0, second: 0, of: .now)!
        times = (0..<8).map { i in
            let start = base.addingTimeInterval(Double(i * (lessonMinutes + breakMinutes)) * 60)
            return LessonTime(start: start, end: start.addingTimeInterval(Double(lessonMinutes) * 60))
        }
    }

    func subject(for lesson: Lesson) -> Subject? { subjects.first { $0.id == lesson.subjectID } }

    func requestNotifications() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    func scheduleNotifications() {
        let center = UNUserNotificationCenter.current()
        center.removeAllPendingNotificationRequests()
        for day in Weekday.allCases {
            guard let list = lessons[day] else { continue }
            for (index, lesson) in list.enumerated() where index < times.count {
                guard let subject = subject(for: lesson) else { continue }
                let content = UNMutableNotificationContent()
                content.title = "Урок закончился"
                let next = list.dropFirst(index + 1).compactMap { subject(for: $0) }.first
                content.body = next.map { "\(subject.name) закончилась. Далее: \($0.name), кабинет \($0.room)" } ?? "\(subject.name) закончилась."
                content.sound = .default
                let components = Calendar.current.dateComponents([.hour, .minute], from: times[index].end)
                let weekday = (Weekday.allCases.firstIndex(of: day) ?? 0) + 2
                var trigger = DateComponents(); trigger.weekday = weekday; trigger.hour = components.hour; trigger.minute = components.minute
                center.add(UNNotificationRequest(identifier: "\(day.rawValue)-\(index)", content: content, trigger: UNCalendarNotificationTrigger(dateMatching: trigger, repeats: true))
            }
        }
    }

    private struct SavedData: Codable { var subjects: [Subject]; var lessons: [Weekday: [Lesson]]; var times: [LessonTime]; var lessonMinutes: Int; var breakMinutes: Int }
    private func save() { if let data = try? JSONEncoder().encode(SavedData(subjects: subjects, lessons: lessons, times: times, lessonMinutes: lessonMinutes, breakMinutes: breakMinutes)) { UserDefaults.standard.set(data, forKey: key) } }
}

struct ContentView: View {
    @EnvironmentObject var store: ScheduleStore
    var body: some View {
        TabView {
            ScheduleView().tabItem { Label("Расписание", systemImage: "calendar") }
            SubjectsView().tabItem { Label("Предметы", systemImage: "books.vertical") }
            SettingsView().tabItem { Label("Настройки", systemImage: "slider.horizontal.3") }
        }
        .tint(.black)
        .onAppear { store.requestNotifications() }
    }
}

struct ScheduleView: View {
    @EnvironmentObject var store: ScheduleStore
    @State private var lessonToEdit: Int?
    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                Picker("День", selection: $store.selectedDay) { ForEach(Weekday.allCases) { Text($0.rawValue).tag($0) } }.pickerStyle(.segmented)
                List {
                    ForEach(Array(store.currentLessons.enumerated()), id: \.element.id) { index, lesson in
                        HStack {
                            Text("\(index + 1)").font(.system(size: 18, weight: .heavy)).frame(width: 28)
                            VStack(alignment: .leading) {
                                Text(store.subject(for: lesson)?.name ?? "Выбрать предмет").font(.headline)
                                Text(store.subject(for: lesson).map { "Кабинет \($0.room)" } ?? "Нажмите, чтобы назначить")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer(); Text(time(index)).font(.caption.monospacedDigit())
                        }
                        .contentShape(Rectangle())
                        .onTapGesture { lessonToEdit = index }
                    }
                }.listStyle(.plain)
            }.padding()
            .navigationTitle("myschool")
            .toolbar { Button("Обновить") { store.scheduleNotifications() }.fontWeight(.bold) }
            .confirmationDialog("Предмет для урока", isPresented: Binding(get: { lessonToEdit != nil }, set: { if !$0 { lessonToEdit = nil } })) {
                ForEach(store.subjects) { subject in
                    Button("\(subject.name) • каб. \(subject.room)") {
                        if let index = lessonToEdit { var list = store.currentLessons; list[index].subjectID = subject.id; store.currentLessons = list }
                        lessonToEdit = nil
                    }
                }
                if lessonToEdit != nil { Button("Очистить", role: .destructive) { if let index = lessonToEdit { var list = store.currentLessons; list[index].subjectID = nil; store.currentLessons = list }; lessonToEdit = nil } }
            }
        }
    }
    private func time(_ index: Int) -> String { guard index < store.times.count else { return "" }; return "\(store.times[index].start.formatted(date: .omitted, time: .shortened))" }
}

struct SubjectsView: View {
    @EnvironmentObject var store: ScheduleStore
    @State private var name = ""; @State private var room = ""
    var body: some View {
        NavigationStack { List {
            Section("Добавить предмет") { TextField("Название предмета", text: $name); TextField("Кабинет", text: $room); Button("Добавить") { guard !name.isEmpty else { return }; store.subjects.append(Subject(name: name, room: room)); name = ""; room = "" }.fontWeight(.bold) }
            Section("Мои предметы") { ForEach(store.subjects) { Text("\($0.name)  •  \($0.room)") }.onDelete { store.subjects.remove(atOffsets: $0) } }
        }.navigationTitle("Предметы") }
    }
}

struct SettingsView: View {
    @EnvironmentObject var store: ScheduleStore
    var body: some View { NavigationStack { List {
        Section("Уведомления") { Button("Запланировать уведомления") { store.scheduleNotifications() }.fontWeight(.bold); Text("Уведомление приходит сразу после окончания урока.").font(.caption).foregroundStyle(.secondary) }
        Section("Звонки") {
            DatePicker("Начало первого урока", selection: Binding(get: { store.times.first?.start ?? .now }, set: { newValue in if !store.times.isEmpty { let minutes = Calendar.current.dateComponents([.hour, .minute], from: newValue); let base = Calendar.current.date(bySettingHour: minutes.hour ?? 8, minute: minutes.minute ?? 0, second: 0, of: .now)!; store.times[0].start = base; store.rebuildTimes() } }), displayedComponents: .hourAndMinute)
            Stepper("Урок: \(store.lessonMinutes) мин", value: $store.lessonMinutes, in: 20...90, step: 5)
            Stepper("Перемена: \(store.breakMinutes) мин", value: $store.breakMinutes, in: 0...30, step: 5)
            Text("Эти настройки применяются ко всем пяти учебным дням.").font(.caption).foregroundStyle(.secondary)
        }
    }.navigationTitle("Настройки") } }
}
