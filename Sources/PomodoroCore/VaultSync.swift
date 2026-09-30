import Foundation

/// Two-way merge between the app's entries and the vault's, content-keyed.
///
/// `base` is the merged state as of the last completed sync. Set logic
/// against it classifies every key: present on a side only → addition;
/// present in base but missing on a side → that side deleted it. Remaining
/// keys exist on both sides and take the local field values (done, priority,
/// title), so simultaneous edits resolve to the app. Entries unknown to the
/// app but present in the vault are adopted, which is how captures made
/// directly in Obsidian reach the list.
public enum VaultSync {

    public struct Result: Equatable {
        /// The unioned state in app display order (open tasks by priority and
        /// age, then notes by age).
        public let entries: [VaultEntry]
        /// True when the merged state differs from what the vault file holds.
        public let vaultNeedsWrite: Bool
        /// True when the merged state differs from the app's list.
        public let appNeedsUpdate: Bool
    }

    public static func merge(
        local: [VaultEntry],
        vault: [VaultEntry],
        base: [VaultEntry],
        now: Date
    ) -> Result {
        let baseKeys = Set(base.map(\.mergeKey))
        let localKeys = Set(local.map(\.mergeKey))
        let vaultKeys = Set(vault.map(\.mergeKey))
        let deletedLocally = baseKeys.subtracting(localKeys)
        let deletedInVault = baseKeys.subtracting(vaultKeys)
        let dead = deletedLocally.union(deletedInVault)

        var vaultByKey = [String: VaultEntry]()
        for entry in vault where !dead.contains(entry.mergeKey) {
            vaultByKey[entry.mergeKey] = entry
        }

        var merged: [VaultEntry] = []
        for entry in local where !dead.contains(entry.mergeKey) {
            // Shared keys: field edits on the vault side (checked in Obsidian,
            // priority changed there) pull in; title is fixed by the key.
            if let mirror = vaultByKey[entry.mergeKey],
                mirror.isDone != entry.isDone || mirror.priority != entry.priority
            {
                var updated = entry
                updated.isDone = mirror.isDone
                updated.priority = mirror.priority
                merged.append(updated)
            } else {
                merged.append(entry)
            }
        }
        // Vault-only keys: additions made in Obsidian. Renames read as a new
        // key, so they surface here and in the matching deletion above.
        for (key, entry) in vaultByKey.sorted(by: { $0.value.createdAt < $1.value.createdAt })
        where !localKeys.contains(key) {
            merged.append(entry)
        }

        let sorted = sort(merged)
        return Result(
            entries: sorted,
            vaultNeedsWrite: !sameContent(sorted, as: vault),
            appNeedsUpdate: !sameState(sorted, as: local)
        )
    }

    /// True when the file need not be rewritten: same keys in any order with
    /// matching checkbox and priority fields.
    private static func sameContent(_ entries: [VaultEntry], as target: [VaultEntry]) -> Bool {
        guard entries.count == target.count else { return false }
        let byKey = Dictionary(target.map { ($0.mergeKey, $0) }, uniquingKeysWith: { first, _ in first })
        return entries.allSatisfy { entry in
            guard let mirror = byKey[entry.mergeKey] else { return false }
            return mirror.isDone == entry.isDone && mirror.priority == entry.priority
        }
    }

    /// True when the app's list already matches the merge, compared by row
    /// identity (ids) so order changes alone never trigger a UI rebuild.
    private static func sameState(_ entries: [VaultEntry], as local: [VaultEntry]) -> Bool {
        guard entries.count == local.count else { return false }
        let byId = Dictionary(local.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return entries.allSatisfy { entry in
            guard let mirror = byId[entry.id] else { return false }
            return mirror.mergeKey == entry.mergeKey && mirror.isDone == entry.isDone
                && mirror.priority == entry.priority
        }
    }

    /// App display order: open tasks by priority then age, then notes by age.
    /// Completions (transient, grace-window only) trail their kind.
    private static func sort(_ entries: [VaultEntry]) -> [VaultEntry] {
        entries.sorted { lhs, rhs in
            if lhs.kind != rhs.kind { return lhs.kind == .task }
            if lhs.isDone != rhs.isDone { return !lhs.isDone }
            if !lhs.isDone, lhs.priority != rhs.priority {
                return (lhs.priority ?? .medium) > (rhs.priority ?? .medium)
            }
            return lhs.createdAt < rhs.createdAt
        }
    }
}
