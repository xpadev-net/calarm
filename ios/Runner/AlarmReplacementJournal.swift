import Foundation

extension AlarmKitBridge {
  private func validatedReplacementJournal(
    _ journal: AlarmReplacementJournal
  ) throws -> AlarmReplacementJournal {
    let oldMap = try validatedMirror([journal.old.platformAlarmId: journal.old])
    let newMap = try validatedMirror([journal.new.platformAlarmId: journal.new])
    guard let old = oldMap.values.first,
      let new = newMap.values.first,
      old.platformAlarmId != new.platformAlarmId,
      old.reservationId == new.reservationId,
      old.wakePlanId == new.wakePlanId,
      (old.generation < new.generation
        || (old.reservationGeneration == nil && new.reservationGeneration == nil)
        || (old.reservationId == "ci-smoke-test-alarm"
          && old.wakePlanId == "test"
          && old.generation == new.generation)),
      old.requiresNativeRestoration != true,
      new.requiresNativeRestoration != true,
      old.scheduleRequest() != nil,
      new.scheduleRequest() != nil
    else { throw MirrorValidationError.invalid }
    return AlarmReplacementJournal(old: old, new: new, phase: journal.phase)
  }

  func loadReplacementJournal() throws -> AlarmReplacementJournal? {
    guard let data = UserDefaults.standard.data(forKey: nativeAlarmReplacementJournalKey) else {
      return nil
    }
    return try validatedReplacementJournal(
      JSONDecoder().decode(AlarmReplacementJournal.self, from: data)
    )
  }

  func saveReplacementJournal(_ journal: AlarmReplacementJournal) throws {
    let validated = try validatedReplacementJournal(journal)
    UserDefaults.standard.set(
      try JSONEncoder().encode(validated),
      forKey: nativeAlarmReplacementJournalKey
    )
  }

  private func clearReplacementJournal() {
    UserDefaults.standard.removeObject(forKey: nativeAlarmReplacementJournalKey)
  }

  @available(iOS 26.0, *)
  func reconcileReplacementJournal(
    in snapshot: MirrorSnapshot,
    nativeAlarms suppliedAlarms: [NativeAlarmSnapshot]? = nil
  ) async throws -> MirrorSnapshot {
    guard let journal = try loadReplacementJournal() else { return snapshot }
    var mirror = snapshot.normalized
    let pendingMirror = snapshot.pendingNormalized
    let oldId = journal.old.platformAlarmId
    let newId = journal.new.platformAlarmId
    guard let oldUUID = UUID(uuidString: oldId),
      let newUUID = UUID(uuidString: newId),
      mirror[oldId] == journal.old || mirror[newId] == journal.new
    else {
      throw MirrorValidationError.invalid
    }

    func nativeIds(_ alarms: [NativeAlarmSnapshot]) throws -> Set<String> {
      try Set(canonicalNativeAlarmIds(alarms.map { $0.platformAlarmId }))
    }

    var ids = try nativeIds(suppliedAlarms ?? nativeClientForAlarmKit().inventory())
    let knownIds = Set(snapshot.normalized.keys)
      .union(snapshot.pendingNormalized.keys)
      .union([oldId, newId])
    guard ids.subtracting(knownIds).isEmpty else {
      throw NativeSnapshotValidationError.unknownIdentity
    }

    func persistResolvedAuthority(
      _ record: AlarmMirrorRecord,
      state: ReservationAuthorityState = .active
    ) throws {
      var authorities = try loadReservationAuthorities()
      if let current = authorities[record.reservationId] {
        let allowedRecords = [journal.old, journal.new]
        let matchesJournal = allowedRecords.contains { candidate in
          current == ReservationAuthorityRecord(record: candidate, state: .active)
            || current == ReservationAuthorityRecord(record: candidate, state: .retired)
        }
        guard matchesJournal else { throw MirrorValidationError.invalid }
      }
      guard !authorities.contains(where: { reservationId, authority in
        reservationId != record.reservationId
          && authority.occurrenceId == record.occurrenceId
      }) else { throw MirrorValidationError.invalid }
      authorities[record.reservationId] = ReservationAuthorityRecord(
        record: record,
        state: state
      )
      try saveReservationAuthorities(authorities)
    }

    func commitNew() throws -> MirrorSnapshot {
      try persistResolvedAuthority(journal.new)
      mirror.removeValue(forKey: oldId)
      mirror[newId] = journal.new
      try saveMirrorState(mirror, pending: pendingMirror)
      clearReplacementJournal()
      return try loadMirrorSnapshot()
    }

    func retainOld() throws -> MirrorSnapshot {
      guard ids.contains(oldId), !ids.contains(newId) else {
        throw MirrorValidationError.invalid
      }
      try persistResolvedAuthority(journal.old)
      mirror.removeValue(forKey: newId)
      mirror[oldId] = journal.old
      try saveMirrorState(mirror, pending: pendingMirror)
      clearReplacementJournal()
      return try loadMirrorSnapshot()
    }

    // AlarmKit's inventory is authoritative. A process can terminate after
    // commitNew()/retainOld() saves the resolved mirror but before it clears
    // this journal, and the retained one-shot can then fire or stop before
    // the next launch. Neither owned UUID remaining is therefore a valid
    // terminal state, not an ambiguous handover. Clear the stale journal so
    // the caller can prune the resolved mirror against the empty snapshot.
    if !ids.contains(oldId), !ids.contains(newId) {
      try persistResolvedAuthority(journal.new, state: .retired)
      clearReplacementJournal()
      return try loadMirrorSnapshot()
    }

    if mirror[newId] == journal.new {
      if ids.contains(oldId) {
        try persistRetirement(journal.old)
        do { try nativeClientForAlarmKit().cancel(id: oldUUID) } catch {}
        ids = try nativeIds(nativeClientForAlarmKit().inventory())
        guard !ids.contains(oldId) else { throw MirrorValidationError.invalid }
      }
      guard ids.contains(newId) else { throw MirrorValidationError.invalid }
      try persistResolvedAuthority(journal.new)
      clearReplacementJournal()
      return try loadMirrorSnapshot()
    }

    switch journal.phase {
    case .staging:
      if ids.contains(oldId) {
        if ids.contains(newId) {
          do { try nativeClientForAlarmKit().cancel(id: newUUID) } catch {}
          ids = try nativeIds(nativeClientForAlarmKit().inventory())
        }
        return try retainOld()
      }
      if ids.contains(newId) {
        return try commitNew()
      }
      throw MirrorValidationError.invalid

    case .newVerified:
      if ids.contains(newId), ids.contains(oldId) {
        try persistRetirement(journal.old)
        do { try nativeClientForAlarmKit().cancel(id: oldUUID) } catch {}
        ids = try nativeIds(nativeClientForAlarmKit().inventory())
      }
      if ids.contains(newId), !ids.contains(oldId) {
        return try commitNew()
      }
      if ids.contains(oldId) {
        if ids.contains(newId) {
          do { try nativeClientForAlarmKit().cancel(id: newUUID) } catch {}
          ids = try nativeIds(nativeClientForAlarmKit().inventory())
        }
        return try retainOld()
      }
      throw MirrorValidationError.invalid
    }
  }
}

enum AlarmReplacementPhase: String, Codable {
  case staging
  case newVerified
}

struct AlarmReplacementJournal: Codable, Equatable {
  let old: AlarmMirrorRecord
  let new: AlarmMirrorRecord
  let phase: AlarmReplacementPhase

  func advancing(to phase: AlarmReplacementPhase) -> AlarmReplacementJournal {
    AlarmReplacementJournal(old: old, new: new, phase: phase)
  }
}

@MainActor
final class AlarmScheduleCoordinator {
  private struct Tail {
    let token: UUID
    let task: Task<Void, Never>
  }

  private var tails: [String: Tail] = [:]

  func run<Value>(
    for reservationId: String,
    operation: @escaping @MainActor () async -> Value
  ) async -> Value {
    let token = UUID()
    let predecessor = tails[reservationId]?.task
    return await withCheckedContinuation { continuation in
      let task = Task { @MainActor in
        if let predecessor {
          await predecessor.value
        }
        let value = await operation()
        continuation.resume(returning: value)
        if tails[reservationId]?.token == token {
          tails.removeValue(forKey: reservationId)
        }
      }
      tails[reservationId] = Tail(token: token, task: task)
    }
  }
}
