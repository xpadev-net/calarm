import CryptoKit
import Foundation

let nativeAlarmMirrorKey = "net.xpadev.calarm/native_alarm_mirror"
let nativeAlarmPendingMirrorKey = "net.xpadev.calarm/native_alarm_pending_mirror"
let nativeAlarmMirrorEnvelopeKey = "net.xpadev.calarm/native_alarm_mirror_envelope"
let nativeAlarmMirrorTransactionKey = "net.xpadev.calarm/native_alarm_mirror_transaction"
let nativeAlarmReplacementJournalKey = "net.xpadev.calarm/native_alarm_replacement_journal"
let nativeAlarmReservationAuthorityKey = "net.xpadev.calarm/native_alarm_reservation_authority"
let nativeAlarmMirrorEnvelopeVersion = 1
let nativeAlarmReservationAuthorityVersion = 1

extension AlarmKitBridge {
  enum ScheduleFailureCleanupOutcome: Equatable {
    case nativePresent
    case nativeAbsent
    case uncertain
  }

  func loadMirrorSnapshot() throws -> MirrorSnapshot {
    let committedData = UserDefaults.standard.data(forKey: nativeAlarmMirrorKey)
    let legacyPendingData = UserDefaults.standard.data(forKey: nativeAlarmPendingMirrorKey)
    let envelopeData = UserDefaults.standard.data(forKey: nativeAlarmMirrorEnvelopeKey)
    let state: StoredMirrorState
    if let envelopeData {
      do {
        let envelope = try decodeMirrorEnvelope(envelopeData)
        let currentEnvelopeState = try validatedMirrorEnvelopeState(envelope)
        if let committedData, isMirrorEnvelope(committedData) {
          // The prior implementation wrote its complete envelope to the
          // legacy key. A current writer always replaces that key with a
          // plain committed projection before publishing the new envelope,
          // so a valid prior envelope here proves that an older reader wrote
          // after the current envelope. It is the deterministic latest state.
          // If it is malformed, do not silently fall back and resurrect rows.
          let priorEnvelope = try decodeMirrorEnvelope(committedData)
          let priorEnvelopeState = try validatedMirrorEnvelopeState(priorEnvelope)
          state = StoredMirrorState(
            committed: priorEnvelopeState.committed,
            pending: priorEnvelopeState.pending,
              isEnvelope: true,
              legacyPendingPresent: legacyPendingData != nil,
              needsProjectionRewrite: true,
              needsTransactionMarkerRewrite: true
          )
        } else if let committedData {
          // A present legacy key must be fully decodable and semantically
          // valid. Treating malformed prior-envelope/projection bytes as
          // absent would silently discard rollback evidence.
          let projection = try validatedMirror(decodeMirrorMap(committedData))
          let pendingProjection = try validatedMirror(decodeMirrorMap(legacyPendingData))
          var pending = currentEnvelopeState.pending
          for (key, record) in pendingProjection {
            if let existing = pending[key] {
              guard existing == record else { throw MirrorValidationError.invalid }
            } else {
              pending[key] = record
            }
          }
          // A valid legacy projection may have been changed by an older
          // binary after this envelope was written. It is therefore the
          // committed authority; never resurrect envelope-only committed
          // rows from a stale rollback projection.
          state = StoredMirrorState(
            committed: projection,
            pending: pending.filter { projection[$0.key] == nil },
            isEnvelope: true,
            legacyPendingPresent: legacyPendingData != nil,
            needsProjectionRewrite: projection != currentEnvelopeState.committed
              || pending != currentEnvelopeState.pending,
            needsTransactionMarkerRewrite: false
          )
        } else {
          state = StoredMirrorState(
            committed: currentEnvelopeState.committed,
            pending: currentEnvelopeState.pending,
              isEnvelope: true,
              legacyPendingPresent: false,
              needsProjectionRewrite: true,
              needsTransactionMarkerRewrite: true
          )
        }
      } catch {
        // A partially written/unsupported envelope can fall back to the
        // legacy projection, which is deliberately written before the new
        // envelope. If that projection is not readable, the state is truly
        // unrecoverable and must remain corrupt.
        if let committedData, isMirrorEnvelope(committedData) {
          // If the current envelope write is interrupted but the prior
          // reader's legacy envelope is complete, retain that recoverable
          // state. Decode and validate it fully before any reconciliation.
          let priorEnvelope = try decodeMirrorEnvelope(committedData)
          let priorEnvelopeState = try validatedMirrorEnvelopeState(priorEnvelope)
          state = StoredMirrorState(
            committed: priorEnvelopeState.committed,
            pending: priorEnvelopeState.pending,
            isEnvelope: false,
            legacyPendingPresent: legacyPendingData != nil,
            needsProjectionRewrite: true,
            needsTransactionMarkerRewrite: true
          )
        } else {
          guard committedData != nil || legacyPendingData != nil else {
            throw MirrorValidationError.invalid
          }
          let committed = try validatedMirror(decodeMirrorMap(committedData))
          let pending = try validatedMirror(decodeMirrorMap(legacyPendingData))
          let merged = try mergeLegacyMirrorState(committed: committed, pending: pending)
          state = StoredMirrorState(
            committed: merged.committed,
            pending: merged.pending,
            isEnvelope: false,
            legacyPendingPresent: legacyPendingData != nil,
            needsProjectionRewrite: true,
            needsTransactionMarkerRewrite: true
          )
        }
      }
    } else if let committedData, isMirrorEnvelope(committedData) {
      // Compatibility with the short-lived envelope-at-legacy-key layout
      // shipped before the rollback projection was split out.
      let envelope = try decodeMirrorEnvelope(committedData)
      state = StoredMirrorState(
        committed: envelope.committed,
        pending: envelope.pending,
        isEnvelope: false,
        legacyPendingPresent: legacyPendingData != nil,
        needsProjectionRewrite: true,
        needsTransactionMarkerRewrite: true
      )
    } else {
      let committed = try decodeMirrorMap(committedData)
      let pending = try decodeMirrorMap(legacyPendingData)
      let merged = try mergeLegacyMirrorState(committed: committed, pending: pending)
      state = StoredMirrorState(
        committed: merged.committed,
        pending: merged.pending,
        isEnvelope: false,
        legacyPendingPresent: legacyPendingData != nil,
        needsProjectionRewrite: true,
        needsTransactionMarkerRewrite: true
      )
    }

    let mirror = state.committed
    let pendingMirror = state.pending
    let normalizedMirror = try validatedMirror(mirror)
    let normalizedPendingMirror = try validatedMirror(pendingMirror)
    var combined = normalizedMirror
    for (key, record) in normalizedPendingMirror {
      guard combined[key] == nil else { throw MirrorValidationError.invalid }
      combined[key] = record
    }
    _ = try validatedMirror(combined)
    let needsTransactionMarkerRewrite = try transactionMarkerNeedsRewrite(
      markerData: UserDefaults.standard.data(forKey: nativeAlarmMirrorTransactionKey),
      committedData: committedData,
      pendingData: legacyPendingData,
      envelopeData: envelopeData,
      authoritativePriorEnvelope: committedData.map(isMirrorEnvelope) ?? false,
      normalizedMirror: normalizedMirror,
      normalizedPendingMirror: normalizedPendingMirror
    )
    return MirrorSnapshot(
      stored: mirror,
      normalized: normalizedMirror,
      pendingStored: pendingMirror,
      pendingNormalized: normalizedPendingMirror,
      isEnvelope: state.isEnvelope,
      legacyPendingPresent: state.legacyPendingPresent,
      needsProjectionRewrite: state.needsProjectionRewrite,
      needsTransactionMarkerRewrite: state.needsTransactionMarkerRewrite
        || needsTransactionMarkerRewrite
    )
  }

  // A marker or projection failure is not immediately terminal: a native
  // schedule may have committed before the durable publication crashed. Read
  // AlarmKit first, then combine only independently valid persisted artifacts.
  // Recovery never invents an identity; every live native ID must have one
  // unambiguous persisted ownership tuple.
  func recoverMirrorSnapshot(
    from nativeAlarms: [NativeAlarmSnapshot]
  ) throws -> MirrorSnapshot {
    let committedData = UserDefaults.standard.data(forKey: nativeAlarmMirrorKey)
    let pendingData = UserDefaults.standard.data(forKey: nativeAlarmPendingMirrorKey)
    let envelopeData = UserDefaults.standard.data(forKey: nativeAlarmMirrorEnvelopeKey)

    let committedArtifact = decodeRecoveryArtifact(
      committedData,
      allowEnvelope: true,
      requireGeneration: false
    )
    let envelopeArtifact = decodeRecoveryArtifact(
      envelopeData,
      allowEnvelope: true,
      requireGeneration: true
    )
    let pendingArtifact = decodeRecoveryArtifact(
      pendingData,
      allowEnvelope: false,
      requireGeneration: false,
      asPending: true
    )

    let artifacts = [committedArtifact, envelopeArtifact, pendingArtifact]
    let hasMalformedArtifact = artifacts.contains { $0.isPresent && !$0.isValid }
    guard !hasMalformedArtifact else {
      throw MirrorValidationError.invalid
    }

    var committed = [String: AlarmMirrorRecord]()
    var pending = [String: AlarmMirrorRecord]()
    if committedArtifact.isPresent, committedArtifact.isPlainProjection {
      // A valid plain map in the legacy committed key is the rollback/older
      // writer's authoritative key set. Enrich matching rows from newer
      // artifacts, but never resurrect rows omitted by that projection.
      committed = committedArtifact.committed
      for artifact in artifacts where artifact.isPresent && !artifact.isPlainProjection {
        for (key, record) in artifact.committed {
          guard let existing = committed[key] else { continue }
          committed[key] = try existing.mergedRecoveryRecord(with: record)
        }
      }
    } else {
      for artifact in artifacts where artifact.isPresent {
        try mergeRecoveryRecords(&committed, from: artifact.committed)
      }
    }
    for artifact in artifacts where artifact.isPresent {
      try mergeRecoveryRecords(&pending, from: artifact.pending)
    }

    for (key, record) in Array(pending) {
      if let committedRecord = committed[key] {
        guard committedRecord == record else { throw MirrorValidationError.invalid }
        pending.removeValue(forKey: key)
      }
    }
    let normalizedCommitted = try validatedMirror(committed)
    let normalizedPending = try validatedMirror(pending)
    var combined = normalizedCommitted
    for (key, record) in normalizedPending {
      guard combined[key] == nil else { throw MirrorValidationError.invalid }
      combined[key] = record
    }
    _ = try validatedMirror(combined)

    let canonicalIds = try canonicalNativeAlarmIds(
      nativeAlarms.map { $0.platformAlarmId }
    )
    var candidateIds = Set(normalizedCommitted.keys)
      .union(normalizedPending.keys)
    if let replacement = try loadReplacementJournal() {
      candidateIds.insert(replacement.old.platformAlarmId)
      candidateIds.insert(replacement.new.platformAlarmId)
    }
    guard Set(canonicalIds).subtracting(candidateIds).isEmpty else {
      throw NativeSnapshotValidationError.unknownIdentity
    }

    return MirrorSnapshot(
      stored: normalizedCommitted,
      normalized: normalizedCommitted,
      pendingStored: normalizedPending,
      pendingNormalized: normalizedPending,
      isEnvelope: false,
      legacyPendingPresent: pendingData != nil,
      needsProjectionRewrite: true,
      needsTransactionMarkerRewrite: true
    )
  }

  private func decodeRecoveryArtifact(
    _ data: Data?,
    allowEnvelope: Bool,
    requireGeneration: Bool,
    asPending: Bool = false
  ) -> RecoveryMirrorArtifact {
    guard let data else { return RecoveryMirrorArtifact() }
    do {
      if isMirrorEnvelope(data) {
        guard allowEnvelope else { return RecoveryMirrorArtifact.invalid }
        let envelope = try decodeMirrorEnvelope(data)
        if requireGeneration {
          guard let generation = envelope.generation,
            (try? canonicalMirrorGeneration(generation)) != nil
          else { return RecoveryMirrorArtifact.invalid }
        }
        let state = try validatedMirrorEnvelopeState(envelope)
        return RecoveryMirrorArtifact(
          committed: state.committed,
          pending: state.pending,
          isPresent: true,
          isValid: true
        )
      }
      let records = try validatedMirror(decodeMirrorMap(data))
      if asPending {
        return RecoveryMirrorArtifact(
          pending: records,
          isPresent: true,
          isValid: true
        )
      }
      return RecoveryMirrorArtifact(
        committed: records,
        isPresent: true,
        isValid: true,
        isPlainProjection: true
      )
    } catch {
      // Preserve invalidity as evidence. The recovery caller rejects any
      // present malformed artifact before considering valid alternatives.
      return RecoveryMirrorArtifact.invalid
    }
  }

  private func mergeRecoveryRecords(
    _ target: inout [String: AlarmMirrorRecord],
    from source: [String: AlarmMirrorRecord]
  ) throws {
    for (key, record) in source {
      if let existing = target[key] {
        target[key] = try existing.mergedRecoveryRecord(with: record)
      } else {
        target[key] = record
      }
    }
  }

  private func decodeMirrorEnvelope(_ data: Data) throws -> MirrorEnvelope {
    let envelope = try JSONDecoder().decode(MirrorEnvelope.self, from: data)
    guard envelope.version == nativeAlarmMirrorEnvelopeVersion else {
      throw MirrorValidationError.invalid
    }
    return envelope
  }

  private func validatedMirrorEnvelopeState(
    _ envelope: MirrorEnvelope
  ) throws -> (committed: [String: AlarmMirrorRecord], pending: [String: AlarmMirrorRecord]) {
    let committed = try validatedMirror(envelope.committed)
    let pending = try validatedMirror(envelope.pending)
    var combined = committed
    for (key, record) in pending {
      guard combined[key] == nil else { throw MirrorValidationError.invalid }
      combined[key] = record
    }
    _ = try validatedMirror(combined)
    return (committed, pending)
  }

  private func transactionMarkerNeedsRewrite(
    markerData: Data?,
    committedData: Data?,
    pendingData: Data?,
    envelopeData: Data?,
    authoritativePriorEnvelope: Bool,
    normalizedMirror: [String: AlarmMirrorRecord],
    normalizedPendingMirror: [String: AlarmMirrorRecord]
  ) throws -> Bool {
    guard let markerData else {
      // A legacy map-only layout is safe to migrate. Once an envelope exists,
      // however, the absence of a marker is not evidence that its projections
      // belong to one generation; recovery must consult native authority.
      if envelopeData == nil && !authoritativePriorEnvelope {
        return true
      }
      throw MirrorValidationError.invalid
    }
    let marker = try JSONDecoder().decode(MirrorTransactionMarker.self, from: markerData)
    try marker.validate()
    let markerMatches = marker.committedDigest == mirrorDigest(committedData)
      && marker.pendingDigest == mirrorDigest(pendingData)
      && marker.envelopeDigest == mirrorDigest(envelopeData)
    if markerMatches {
      guard let envelopeData,
        let envelope = try? decodeMirrorEnvelope(envelopeData),
        let generation = envelope.generation,
        try canonicalMirrorGeneration(generation) == marker.generation
      else { throw MirrorValidationError.invalid }
      return false
    }

    // Any mismatch is a crash boundary. Even semantically equal maps are not
    // proof of a shared transaction, so defer to recovery-first native
    // correlation instead of accepting or republishing them here.
    _ = authoritativePriorEnvelope
    _ = normalizedMirror
    _ = normalizedPendingMirror
    throw MirrorValidationError.invalid
  }

  private func mirrorDigest(_ data: Data?) -> String {
    let bytes = data ?? Data("<absent>".utf8)
    return SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
  }

  private func decodeMirrorMap(_ data: Data?) throws -> [String: AlarmMirrorRecord] {
    guard let data else {
      return [:]
    }
    return try JSONDecoder().decode([String: AlarmMirrorRecord].self, from: data)
  }

  private func isMirrorEnvelope(_ data: Data) -> Bool {
    guard let object = try? JSONSerialization.jsonObject(with: data),
      let dictionary = object as? [String: Any]
    else { return false }
    return dictionary["version"] != nil
      || dictionary["committed"] != nil
      || dictionary["pending"] != nil
  }

  private func mergeLegacyMirrorState(
    committed: [String: AlarmMirrorRecord],
    pending: [String: AlarmMirrorRecord]
  ) throws -> (committed: [String: AlarmMirrorRecord], pending: [String: AlarmMirrorRecord]) {
    let normalizedCommitted = try validatedMirror(committed)
    let normalizedPending = try validatedMirror(pending)
    var merged = normalizedCommitted
    var recoverablePending = normalizedPending
    for (key, record) in normalizedPending {
      if let committedRecord = normalizedCommitted[key] {
        guard committedRecord == record else { throw MirrorValidationError.invalid }
        recoverablePending.removeValue(forKey: key)
      } else {
        merged[key] = record
      }
    }
    _ = try validatedMirror(merged)
    return (normalizedCommitted, recoverablePending)
  }

  func validatedMirror(
    _ mirror: [String: AlarmMirrorRecord]
  ) throws -> [String: AlarmMirrorRecord] {
    var reservationIds = Set<String>()
    var occurrenceIds = Set<String>()
    var platformAlarmIds = Set<String>()
    var normalizedMirror = [String: AlarmMirrorRecord]()

    for (key, record) in mirror {
      let hasLegacyConfiguration = record.scheduledAt == nil &&
        record.targetAt == nil &&
        record.soundId == nil &&
        record.vibrationEnabled == nil
      let hasCompleteConfiguration = record.scheduledAt != nil &&
        record.targetAt != nil &&
        record.soundId?.isEmpty == false &&
        record.vibrationEnabled != nil
      guard let normalizedKey = try? canonicalPlatformAlarmId(key),
        let normalizedRecordId = try? canonicalPlatformAlarmId(record.platformAlarmId),
        normalizedKey == normalizedRecordId,
        !record.reservationId.isEmpty,
        !record.occurrenceId.isEmpty,
        record.generation >= 0,
        !record.wakePlanId.isEmpty,
        hasLegacyConfiguration || hasCompleteConfiguration,
        record.requiresNativeRestoration != false,
        record.requiresNativeRestoration != true || hasCompleteConfiguration,
        reservationIds.insert(record.reservationId).inserted,
        occurrenceIds.insert(record.occurrenceId).inserted,
        platformAlarmIds.insert(normalizedKey).inserted,
        normalizedMirror[normalizedKey] == nil
      else {
        throw MirrorValidationError.invalid
      }
      normalizedMirror[normalizedKey] = AlarmMirrorRecord(
        reservationId: record.reservationId,
        occurrenceId: record.occurrenceId,
        reservationGeneration: record.reservationGeneration,
        wakePlanId: record.wakePlanId,
        platformAlarmId: normalizedKey,
        scheduledAt: record.scheduledAt,
        targetAt: record.targetAt,
        soundId: record.soundId,
        vibrationEnabled: record.vibrationEnabled,
        requiresNativeRestoration: record.requiresNativeRestoration
      )
    }
    return normalizedMirror
  }

  func saveMirrorState(
    _ mirror: [String: AlarmMirrorRecord],
    pending: [String: AlarmMirrorRecord]
  ) throws {
    let envelope = MirrorEnvelope(
      version: nativeAlarmMirrorEnvelopeVersion,
      generation: UUID().uuidString,
      committed: mirror,
      pending: pending
    )
    let encoder = JSONEncoder()
    let envelopeData = try encoder.encode(envelope)
    let committedData = try encoder.encode(mirror)
    let pendingData = pending.isEmpty ? nil : try encoder.encode(pending)
    let marker = MirrorTransactionMarker(
      version: nativeAlarmMirrorEnvelopeVersion,
      generation: envelope.generation ?? UUID().uuidString,
      committedDigest: mirrorDigest(committedData),
      pendingDigest: mirrorDigest(pendingData),
      envelopeDigest: mirrorDigest(envelopeData)
    )
    let markerData = try encoder.encode(marker)

    // Publish a transaction marker before any artifact. A restart either
    // observes all matching digests or rejects a mixed-generation state;
    // ordering alone must never resurrect stale pending recovery rows. The
    // legacy projection remains decodable by older binaries and intentionally
    // excludes pending-only rows.
    UserDefaults.standard.set(markerData, forKey: nativeAlarmMirrorTransactionKey)
    UserDefaults.standard.set(committedData, forKey: nativeAlarmMirrorKey)
    if let pendingData {
      UserDefaults.standard.set(pendingData, forKey: nativeAlarmPendingMirrorKey)
    } else {
      UserDefaults.standard.removeObject(forKey: nativeAlarmPendingMirrorKey)
    }
    UserDefaults.standard.set(envelopeData, forKey: nativeAlarmMirrorEnvelopeKey)
  }

  func mirrorOwnsMatchingTuple(
    _ platformAlarmId: String,
    request: ScheduleRequest
  ) -> Bool {
    guard let snapshot = try? loadMirrorSnapshot() else { return false }
    return (snapshot.normalized[platformAlarmId]
      ?? snapshot.pendingNormalized[platformAlarmId])?.matches(request) == true
  }

  @available(iOS 26.0, *)
  func removeMirrorEntryIfNativeAlarmAbsent(
    _ platformAlarmId: String,
    request: ScheduleRequest,
    pendingEntryCreated: Bool
  ) -> ScheduleFailureCleanupOutcome {
    do {
      let snapshot: MirrorSnapshot
      do {
        snapshot = try loadMirrorSnapshot()
      } catch {
        let recoveryAlarms = try nativeClientForAlarmKit().inventory()
        snapshot = try recoverMirrorSnapshot(from: recoveryAlarms)
      }
      let currentNativeAlarmIds = Set(
        try authoritativeNativeAlarmIds(
          nativeClientForAlarmKit().inventory().map { $0.platformAlarmId },
          mirrorSnapshot: snapshot
        )
      )
      if currentNativeAlarmIds.contains(platformAlarmId) {
        return .nativePresent
      }

      var mirror = snapshot.stored
      var pendingMirror = snapshot.pendingStored
      let matchingKeys = try (pendingEntryCreated ? pendingMirror.keys : mirror.keys).filter {
        try canonicalPlatformAlarmId($0) == platformAlarmId
      }
      guard matchingKeys.count == 1,
        let matchingKey = matchingKeys.first,
        (pendingEntryCreated ? pendingMirror[matchingKey] : mirror[matchingKey])?.matches(request) == true
      else { return .uncertain }
      if pendingEntryCreated {
        pendingMirror.removeValue(forKey: matchingKey)
        try saveMirrorState(mirror, pending: pendingMirror)
      } else {
        mirror.removeValue(forKey: matchingKey)
        try saveMirrorState(mirror, pending: pendingMirror)
      }
      return .nativeAbsent
    } catch {
      // Preserve the mirror when native inventory or mirror persistence cannot
      // establish that the AlarmKit alarm is absent.
      return .uncertain
    }
  }
}

struct MirrorSnapshot {
  let stored: [String: AlarmMirrorRecord]
  let normalized: [String: AlarmMirrorRecord]
  let pendingStored: [String: AlarmMirrorRecord]
  let pendingNormalized: [String: AlarmMirrorRecord]
  let isEnvelope: Bool
  let legacyPendingPresent: Bool
  let needsProjectionRewrite: Bool
  let needsTransactionMarkerRewrite: Bool
}

private struct StoredMirrorState {
  let committed: [String: AlarmMirrorRecord]
  let pending: [String: AlarmMirrorRecord]
  let isEnvelope: Bool
  let legacyPendingPresent: Bool
  let needsProjectionRewrite: Bool
  let needsTransactionMarkerRewrite: Bool
}

private struct MirrorEnvelope: Codable {
  let version: Int
  let generation: String?
  let committed: [String: AlarmMirrorRecord]
  let pending: [String: AlarmMirrorRecord]
}

private struct MirrorTransactionMarker: Codable {
  let version: Int
  let generation: String
  let committedDigest: String
  let pendingDigest: String
  let envelopeDigest: String

  func validate() throws {
    guard version == nativeAlarmMirrorEnvelopeVersion,
      (try? canonicalMirrorGeneration(generation)) != nil,
      isDigest(committedDigest),
      isDigest(pendingDigest),
      isDigest(envelopeDigest)
    else {
      throw MirrorValidationError.invalid
    }
  }

  private func isDigest(_ value: String) -> Bool {
    value.count == 64
      && value.unicodeScalars.allSatisfy { scalar in
        (scalar.value >= 48 && scalar.value <= 57)
          || (scalar.value >= 97 && scalar.value <= 102)
      }
  }
}

private func canonicalMirrorGeneration(_ generation: String) throws -> String {
  guard let uuid = UUID(uuidString: generation),
    generation == uuid.uuidString
  else {
    throw MirrorValidationError.invalid
  }
  return generation
}

private struct RecoveryMirrorArtifact {
  let committed: [String: AlarmMirrorRecord]
  let pending: [String: AlarmMirrorRecord]
  let isPresent: Bool
  let isValid: Bool
  let isPlainProjection: Bool

  init(
    committed: [String: AlarmMirrorRecord] = [:],
    pending: [String: AlarmMirrorRecord] = [:],
    isPresent: Bool = false,
    isValid: Bool = true,
    isPlainProjection: Bool = false
  ) {
    self.committed = committed
    self.pending = pending
    self.isPresent = isPresent
    self.isValid = isValid
    self.isPlainProjection = isPlainProjection
  }

  static let invalid = RecoveryMirrorArtifact(
    isPresent: true,
    isValid: false
  )
}

struct AlarmMirrorRecord: Codable, Equatable {
  let reservationId: String
  let occurrenceId: String
  let reservationGeneration: Int?
  let wakePlanId: String
  let platformAlarmId: String
  // These fields were added after the initial mirror schema. They remain
  // optional so older committed rows can be read and safely replaced on the
  // next retry, rather than being treated as corrupt solely because they do
  // not contain native configuration metadata.
  let scheduledAt: Date?
  let targetAt: Date?
  let soundId: String?
  let vibrationEnabled: Bool?
  // True means the tuple is a recovery obligation, not authoritative
  // inventory, until its complete native configuration is rescheduled.
  let requiresNativeRestoration: Bool?

  init(request: ScheduleRequest, platformAlarmId: String) {
    reservationId = request.reservationId
    occurrenceId = request.occurrenceId
    reservationGeneration = request.reservationGeneration
    wakePlanId = request.wakePlanId
    self.platformAlarmId = platformAlarmId
    scheduledAt = request.scheduledAt
    targetAt = request.targetAt
    soundId = request.soundId
    vibrationEnabled = request.vibrationEnabled
    requiresNativeRestoration = nil
  }

  init(
    reservationId: String,
    occurrenceId: String,
    reservationGeneration: Int? = nil,
    wakePlanId: String,
    platformAlarmId: String,
    scheduledAt: Date? = nil,
    targetAt: Date? = nil,
    soundId: String? = nil,
    vibrationEnabled: Bool? = nil,
    requiresNativeRestoration: Bool? = nil
  ) {
    self.reservationId = reservationId
    self.occurrenceId = occurrenceId
    self.reservationGeneration = reservationGeneration
    self.wakePlanId = wakePlanId
    self.platformAlarmId = platformAlarmId
    self.scheduledAt = scheduledAt
    self.targetAt = targetAt
    self.soundId = soundId
    self.vibrationEnabled = vibrationEnabled
    self.requiresNativeRestoration = requiresNativeRestoration
  }

  func matches(_ request: ScheduleRequest) -> Bool {
    guard reservationId == request.reservationId &&
      occurrenceId == request.occurrenceId &&
      generation == request.reservationGeneration &&
      wakePlanId == request.wakePlanId,
      let scheduledAt,
      let targetAt,
      let soundId,
      let vibrationEnabled
    else {
      return false
    }
    return scheduledAt == request.scheduledAt &&
      targetAt == request.targetAt &&
      soundId == request.soundId &&
      vibrationEnabled == request.vibrationEnabled
  }

  func matchesStableReservation(_ request: ScheduleRequest) -> Bool {
    reservationId == request.reservationId &&
      wakePlanId == request.wakePlanId
  }

  var generation: Int { reservationGeneration ?? 0 }

  func scheduleRequest() -> ScheduleRequest? {
    guard let scheduledAt,
      let targetAt,
      let soundId,
      let vibrationEnabled
    else {
      return nil
    }
    return ScheduleRequest(
      occurrenceId: occurrenceId,
      reservationId: reservationId,
      reservationGeneration: generation,
      wakePlanId: wakePlanId,
      scheduledAt: scheduledAt,
      targetAt: targetAt,
      soundId: soundId,
      vibrationEnabled: vibrationEnabled
    )
  }

  func requiringNativeRestoration() -> AlarmMirrorRecord {
    AlarmMirrorRecord(
      reservationId: reservationId,
      occurrenceId: occurrenceId,
      reservationGeneration: generation,
      wakePlanId: wakePlanId,
      platformAlarmId: platformAlarmId,
      scheduledAt: scheduledAt,
      targetAt: targetAt,
      soundId: soundId,
      vibrationEnabled: vibrationEnabled,
      requiresNativeRestoration: true
    )
  }

  func markingNativeRestored() -> AlarmMirrorRecord {
    AlarmMirrorRecord(
      reservationId: reservationId,
      occurrenceId: occurrenceId,
      reservationGeneration: generation,
      wakePlanId: wakePlanId,
      platformAlarmId: platformAlarmId,
      scheduledAt: scheduledAt,
      targetAt: targetAt,
      soundId: soundId,
      vibrationEnabled: vibrationEnabled
    )
  }

  func mergedRecoveryRecord(with other: AlarmMirrorRecord) throws -> AlarmMirrorRecord {
    guard reservationId == other.reservationId,
      occurrenceId == other.occurrenceId,
      generation == other.generation,
      wakePlanId == other.wakePlanId,
      platformAlarmId == other.platformAlarmId
    else {
      throw MirrorValidationError.invalid
    }
    return AlarmMirrorRecord(
      reservationId: reservationId,
      occurrenceId: occurrenceId,
      reservationGeneration: generation,
      wakePlanId: wakePlanId,
      platformAlarmId: platformAlarmId,
      scheduledAt: try mergeRecoveryValue(scheduledAt, other.scheduledAt),
      targetAt: try mergeRecoveryValue(targetAt, other.targetAt),
      soundId: try mergeRecoveryValue(soundId, other.soundId),
      vibrationEnabled: try mergeRecoveryValue(vibrationEnabled, other.vibrationEnabled),
      requiresNativeRestoration:
        requiresNativeRestoration == true || other.requiresNativeRestoration == true
          ? true
          : nil
    )
  }
}

enum MirrorValidationError: Error {
  case invalid
}

enum NativeSnapshotValidationError: Error {
  case invalidOrDuplicate
  case unknownIdentity
}

private func mergeRecoveryValue<T: Equatable>(_ first: T?, _ second: T?) throws -> T? {
  guard let first else { return second }
  guard let second else { return first }
  guard first == second else { throw MirrorValidationError.invalid }
  return first
}

@MainActor
final class AlarmMirrorCoordinator {
  // UserDefaults stores the committed and pending mirrors as whole maps. Keep
  // every read/normalize/merge/write transaction in one shared FIFO so a
  // native await cannot let another bridge instance save a stale snapshot.
  static let shared = AlarmMirrorCoordinator()

  private struct Tail {
    let token: UUID
    let task: Task<Void, Never>
  }

  private var tail: Tail?

  func run<Value>(
    operation: @escaping @MainActor () async -> Value
  ) async -> Value {
    let token = UUID()
    let predecessor = tail?.task
    return await withCheckedContinuation { continuation in
      let task = Task { @MainActor in
        if let predecessor {
          await predecessor.value
        }
        let value = await operation()
        continuation.resume(returning: value)
        if tail?.token == token {
          tail = nil
        }
      }
      tail = Tail(token: token, task: task)
    }
  }
}

func calarmPlatformAlarmId(for reservationId: String) -> String {
  var bytes = Array(SHA256.hash(data: Data(reservationId.utf8)).prefix(16))
  bytes[6] = (bytes[6] & 0x0f) | 0x50
  bytes[8] = (bytes[8] & 0x3f) | 0x80
  let hex = bytes.map { String(format: "%02x", $0) }
  return "\(hex[0])\(hex[1])\(hex[2])\(hex[3])-\(hex[4])\(hex[5])-\(hex[6])\(hex[7])-\(hex[8])\(hex[9])-\(hex[10])\(hex[11])\(hex[12])\(hex[13])\(hex[14])\(hex[15])"
}

func isNativeSmokeTestReservation(_ request: ScheduleRequest) -> Bool {
  request.reservationId == "ci-smoke-test-alarm"
    && request.occurrenceId == "ci-smoke-test-alarm"
    && request.wakePlanId == "test"
}

func canonicalPlatformAlarmId(_ platformAlarmId: String) throws -> String {
  guard let uuid = UUID(uuidString: platformAlarmId) else {
    throw MirrorValidationError.invalid
  }
  return uuid.uuidString.lowercased()
}

func canonicalNativeAlarmIds(_ platformAlarmIds: [String]) throws -> [String] {
  var seen = Set<String>()
  return try platformAlarmIds.map { platformAlarmId in
    let canonicalId: String
    do {
      canonicalId = try canonicalPlatformAlarmId(platformAlarmId)
    } catch {
      throw NativeSnapshotValidationError.invalidOrDuplicate
    }
    guard seen.insert(canonicalId).inserted else {
      throw NativeSnapshotValidationError.invalidOrDuplicate
    }
    return canonicalId
  }
}

func authoritativeNativeAlarmIds(
  _ platformAlarmIds: [String],
  mirrorSnapshot: MirrorSnapshot
) throws -> [String] {
  let canonicalIds = try canonicalNativeAlarmIds(platformAlarmIds)
  let knownIds = Set(mirrorSnapshot.normalized.keys)
    .union(mirrorSnapshot.pendingNormalized.keys)
  guard Set(canonicalIds).subtracting(knownIds).isEmpty else {
    throw NativeSnapshotValidationError.unknownIdentity
  }
  return canonicalIds
}

func calarmShouldRemoveMirrorAfterScheduleFailure(
  currentNativeAlarmIds: Set<String>?,
  platformAlarmId: String
) -> Bool {
  guard let currentNativeAlarmIds,
    let normalizedPlatformAlarmId = try? canonicalPlatformAlarmId(platformAlarmId)
  else { return false }
  let normalizedCurrentIds = Set(
    currentNativeAlarmIds.compactMap { try? canonicalPlatformAlarmId($0) }
  )
  return !normalizedCurrentIds.contains(normalizedPlatformAlarmId)
}
