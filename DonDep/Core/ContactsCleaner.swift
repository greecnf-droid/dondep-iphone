import Foundation
import Contacts

struct ContactGroup: Identifiable {
    let id = UUID()
    var contacts: [CNContact]
    var reason: String
}

@MainActor
final class ContactsCleaner: ObservableObject {
    enum State { case idle, loading, denied, loaded }

    @Published var state: State = .idle
    @Published var groups: [ContactGroup] = []
    @Published var emptyContacts: [CNContact] = []
    @Published var total = 0

    nonisolated static func keys() -> [CNKeyDescriptor] {
        [
            CNContactFormatter.descriptorForRequiredKeys(for: .fullName),
            CNContactPhoneNumbersKey as CNKeyDescriptor,
            CNContactEmailAddressesKey as CNKeyDescriptor,
            CNContactOrganizationNameKey as CNKeyDescriptor,
            CNContactIdentifierKey as CNKeyDescriptor
        ]
    }

    func load() async {
        state = .loading
        let store = CNContactStore()
        let status = CNContactStore.authorizationStatus(for: .contacts)
        if status == .notDetermined {
            _ = try? await store.requestAccess(for: .contacts)
        }
        let now = CNContactStore.authorizationStatus(for: .contacts)
        guard now == .authorized || now.rawValue == 4 /* .limited (iOS 18) */ else {
            state = .denied
            return
        }
        let (groups, empty, total) = await Task.detached(priority: .userInitiated) {
            ContactsCleaner.analyze()
        }.value
        self.groups = groups
        self.emptyContacts = empty
        self.total = total
        state = .loaded
    }

    nonisolated static func displayName(_ c: CNContact) -> String {
        let n = CNContactFormatter.string(from: c, style: .fullName) ?? ""
        if !n.isEmpty { return n }
        if !c.organizationName.isEmpty { return c.organizationName }
        return "(Không tên)"
    }

    nonisolated static func normalizeName(_ s: String) -> String {
        s.lowercased()
            .replacingOccurrences(of: "đ", with: "d")
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "vi_VN"))
            .components(separatedBy: .whitespacesAndNewlines).joined()
    }

    nonisolated static func normalizePhone(_ s: String) -> String {
        var digits = s.filter { $0.isNumber }
        if digits.hasPrefix("84") && digits.count >= 11 { digits = "0" + digits.dropFirst(2) }
        return String(digits.suffix(9))
    }

    nonisolated static func analyze() -> ([ContactGroup], [CNContact], Int) {
        let store = CNContactStore()
        var contacts: [CNContact] = []
        let req = CNContactFetchRequest(keysToFetch: keys())
        try? store.enumerateContacts(with: req) { c, _ in contacts.append(c) }

        var uf = UnionFind(contacts.count)
        var nameIdx: [String: Int] = [:]
        var phoneIdx: [String: Int] = [:]
        var emailIdx: [String: Int] = [:]
        var empty: [CNContact] = []

        for (i, c) in contacts.enumerated() {
            let fullName = CNContactFormatter.string(from: c, style: .fullName) ?? ""
            let name = normalizeName(fullName)
            if name.isEmpty && c.organizationName.isEmpty && c.phoneNumbers.isEmpty && c.emailAddresses.isEmpty {
                empty.append(c)
                continue
            }
            if !name.isEmpty {
                if let j = nameIdx[name] { uf.union(j, i) } else { nameIdx[name] = i }
            }
            for p in c.phoneNumbers {
                let k = normalizePhone(p.value.stringValue)
                guard k.count >= 8 else { continue }
                if let j = phoneIdx[k] { uf.union(j, i) } else { phoneIdx[k] = i }
            }
            for e in c.emailAddresses {
                let k = (e.value as String).lowercased().trimmingCharacters(in: .whitespaces)
                guard !k.isEmpty else { continue }
                if let j = emailIdx[k] { uf.union(j, i) } else { emailIdx[k] = i }
            }
        }

        var groups: [ContactGroup] = []
        for g in uf.groups() {
            let members = g.map { contacts[$0] }
            let names = Set(members.map { normalizeName(CNContactFormatter.string(from: $0, style: .fullName) ?? "") })
            let reason = names.count == 1 ? "Trùng tên" : "Trùng số điện thoại / email"
            let sorted = members.sorted { infoCount($0) > infoCount($1) }
            groups.append(ContactGroup(contacts: sorted, reason: reason))
        }
        groups.sort { displayName($0.contacts[0]) < displayName($1.contacts[0]) }
        return (groups, empty, contacts.count)
    }

    nonisolated static func infoCount(_ c: CNContact) -> Int {
        c.phoneNumbers.count + c.emailAddresses.count + (c.organizationName.isEmpty ? 0 : 1)
    }

    /// Gộp: giữ liên hệ đầy đủ nhất, bổ sung số điện thoại/email từ các bản còn lại rồi xóa chúng.
    func merge(_ group: ContactGroup) async throws {
        try await Task.detached {
            try ContactsCleaner.mergeSync(group.contacts)
        }.value
        groups.removeAll { $0.id == group.id }
    }

    func mergeAll() async throws {
        let all = groups
        try await Task.detached {
            for g in all { try ContactsCleaner.mergeSync(g.contacts) }
        }.value
        groups.removeAll()
    }

    nonisolated static func mergeSync(_ contacts: [CNContact]) throws {
        guard contacts.count >= 2, let keep = contacts.first?.mutableCopy() as? CNMutableContact else { return }
        var phones = Set(keep.phoneNumbers.map { normalizePhone($0.value.stringValue) })
        var emails = Set(keep.emailAddresses.map { ($0.value as String).lowercased() })
        var newPhones = keep.phoneNumbers
        var newEmails = keep.emailAddresses
        for other in contacts.dropFirst() {
            for p in other.phoneNumbers where phones.insert(normalizePhone(p.value.stringValue)).inserted {
                newPhones.append(p)
            }
            for e in other.emailAddresses where emails.insert((e.value as String).lowercased()).inserted {
                newEmails.append(e)
            }
            if keep.organizationName.isEmpty && !other.organizationName.isEmpty {
                keep.organizationName = other.organizationName
            }
        }
        keep.phoneNumbers = newPhones
        keep.emailAddresses = newEmails
        let save = CNSaveRequest()
        save.update(keep)
        for other in contacts.dropFirst() {
            if let m = other.mutableCopy() as? CNMutableContact { save.delete(m) }
        }
        try CNContactStore().execute(save)
    }

    func deleteEmpty() async throws {
        let list = emptyContacts
        try await Task.detached {
            let save = CNSaveRequest()
            for c in list { if let m = c.mutableCopy() as? CNMutableContact { save.delete(m) } }
            try CNContactStore().execute(save)
        }.value
        emptyContacts.removeAll()
    }
}
